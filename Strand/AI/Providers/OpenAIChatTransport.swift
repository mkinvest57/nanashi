import Foundation
import StrandAnalytics

/// The shared Chat Completions request/response contract for OpenAI and compatible servers.
/// A rejected legacy request may be retried once, before generation starts. Completed/partial
/// generations and transient errors are never automatically replayed (which could bill twice).
enum OpenAIChatTransport {
    static let outputTokenLimit = 4096

    /// Catalog-only filter, never a rewrite of the user's selected model. The public model index
    /// does not expose endpoint capabilities. Exclude specialized families and documented
    /// Responses-only IDs; remaining candidates still require access from the user's own account.
    /// Source: https://developers.openai.com/api/docs/models (verified 2026-10-27).
    static func isModelCandidate(_ id: String) -> Bool {
        guard id.hasPrefix("gpt-") || id.range(of: #"^o[0-9]+(?:-|$)"#, options: .regularExpression) != nil else {
            return false
        }
        let specialized = ["audio", "realtime", "live", "transcribe", "tts", "image", "embedding", "deep-research", "codex"]
        guard !specialized.contains(where: { id.contains("-" + $0) }) else { return false }
        let responsesOnly = ["gpt-5-pro", "gpt-5.2-pro", "gpt-5.4-pro", "gpt-5.5-pro", "o1-pro", "o3-pro"]
        return !responsesOnly.contains { id == $0 || id.hasPrefix($0 + "-") }
    }

    static func request(
        url: URL,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)]
    ) throws -> URLRequest {
        var wire: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        for message in messages {
            wire.append(["role": message.role.rawValue, "content": message.content])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "messages": wire])
        return request
    }

    static func configured(_ request: URLRequest, modernParams: Bool, streaming: Bool) throws -> URLRequest {
        var request = request
        guard let data = request.httpBody,
              var body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AICoachError.decode
        }
        // max_completion_tokens covers both visible output and reasoning tokens. Omitting
        // temperature also works with GPT-5/o-series configurations that reject custom sampling.
        body[modernParams ? "max_completion_tokens" : "max_tokens"] = outputTokenLimit
        if !modernParams { body["temperature"] = 0.6 }
        if streaming { body["stream"] = true }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue(streaming ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Only an explicit rejection of one of our legacy parameters warrants a compatibility retry.
    /// "Unsupported model", quota errors and unrelated malformed inputs must remain single requests.
    static func shouldRetryModernParams(status: Int, detail: String) -> Bool {
        guard status == 400 else { return false }
        let detail = detail.lowercased()
        let legacyParameter = detail.contains("max_tokens") || detail.contains("temperature")
        let rejection = ["unsupported", "not supported", "not support", "unknown parameter",
                         "unrecognized", "not allowed", "only the default", "use 'max_completion_tokens'",
                         "use max_completion_tokens"].contains { detail.contains($0) }
        return legacyParameter && rejection
    }

    static func send(
        request: URLRequest,
        modernParams: Bool,
        allowModernRetry: Bool,
        session: URLSession
    ) async throws -> String {
        try Task.checkCancellation()
        let json: [String: Any]
        do {
            json = try await performRequest(configured(request, modernParams: modernParams, streaming: false),
                                            session: session)
        } catch let AICoachError.server(status, detail)
                    where allowModernRetry && !modernParams && shouldRetryModernParams(status: status, detail: detail) {
            try Task.checkCancellation()
            json = try await performRequest(configured(request, modernParams: true, streaming: false), session: session)
        }
        return try parseContent(json)
    }

    static func parseContent(_ json: [String: Any]) throws -> String {
        if json["error"] != nil { throw emptyReplyError(json) }
        guard let first = (json["choices"] as? [[String: Any]])?.first,
              let message = first["message"] as? [String: Any] else { throw emptyReplyError(json) }
        let content = ((message["content"] as? String) ?? (message["refusal"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = (first["finish_reason"] as? String)?.lowercased()
        try validateReply(content: content, finishReason: reason, json: json)
        return reason == "length" ? content + CustomClient.truncationNote : content
    }

    static func stream(
        request: URLRequest,
        modernParams: Bool,
        allowModernRetry: Bool,
        session: URLSession,
        onDelta: (String) -> Void
    ) async throws {
        var state = StreamState()
        func attempt(modern: Bool) async throws {
            try Task.checkCancellation()
            try await performStreamingRequest(configured(request, modernParams: modern, streaming: true),
                                              session: session) { payload in
                if let text = try state.consume(payload) { onDelta(text) }
            }
        }
        do {
            try await attempt(modern: modernParams)
        } catch let AICoachError.server(status, detail)
                    where allowModernRetry && !modernParams && !state.receivedPayload
                    && shouldRetryModernParams(status: status, detail: detail) {
            try await attempt(modern: true)
        }
        try state.finish()
        if state.finishReason == "length" { onDelta(CustomClient.truncationNote) }
    }

    private static func validateReply(content: String, finishReason: String?, json: [String: Any]) throws {
        if finishReason == "content_filter" {
            throw AICoachError.emptyReply("The provider filtered this reply. Rephrase your question and try again.")
        }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if finishReason == "length" {
                throw AICoachError.emptyReply("The model reached its response limit before returning an answer. "
                    + "Ask a shorter question or select another model.")
            }
            throw emptyReplyError(json)
        }
    }

    /// Tracks the terminal event so a closed connection cannot masquerade as a complete answer.
    /// Unknown non-text fields (usage/reasoning/tool metadata) never become fabricated visible text.
    struct StreamState {
        private(set) var receivedPayload = false
        private(set) var text = ""
        private(set) var finishReason: String?
        private var completed = false

        mutating func consume(_ payload: String) throws -> String? {
            receivedPayload = true
            if SseDeltas.isDone(payload) { completed = true; return nil }
            guard let data = payload.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw AICoachError.decode
            }
            if json["error"] != nil { throw emptyReplyError(json) }
            guard let choice = (json["choices"] as? [[String: Any]])?.first else { return nil }
            if let reason = choice["finish_reason"] as? String, !reason.isEmpty {
                finishReason = reason.lowercased()
                completed = true
            }
            let delta = choice["delta"] as? [String: Any]
            let piece = (delta?["content"] as? String) ?? (delta?["refusal"] as? String)
            if let piece { text += piece }
            return piece
        }

        func finish() throws {
            try validateReply(content: text, finishReason: finishReason, json: [:])
            guard completed else {
                throw AICoachError.network("The provider closed the stream before completing its reply")
            }
        }
    }
}
