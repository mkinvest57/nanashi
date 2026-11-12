import Foundation
import StrandAnalytics

struct AnthropicClient: AIProviderClient {

    func send(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession
    ) async throws -> String {
        var wire: [[String: Any]] = []
        for m in messages { wire.append(["role": m.role.rawValue, "content": m.content]) }

        // Anthropic: system prompt is a top-level field, not a message role.
        let body: [String: Any] = [
            "model": model,
            // #1074: 900 truncated detailed coaching replies mid-sentence; 4096 lets a full multi-section
            // reply complete (a cap, not a target — the system prompt keeps it short). Matches the others.
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": wire
        ]

        var req = URLRequest(url: AIProvider.anthropic.endpoint)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let json = try await performRequest(req, session: session)
        return try parseTextReply(json)
    }

    /// Reasoning models can lead with thinking/tool blocks. Only visible text belongs in the reply.
    func parseTextReply(_ json: [String: Any]) throws -> String {
        if json["error"] != nil { throw emptyReplyError(json) }
        let text = (json["content"] as? [[String: Any]] ?? []).compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw emptyReplyError(json) }
        return text
    }

    /// K1: Stream via `stream: true`. Anthropic SSE uses typed events; we extract `content_block_delta`
    /// with `text_delta` via `SseDeltas.anthropicDelta`. Byte-parity pin in
    /// `SseDeltasTests.anthropicReassembleMatchesFullReply`.
    func stream(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession,
        onDelta: (String) -> Void
    ) async throws {
        var wire: [[String: Any]] = []
        for m in messages { wire.append(["role": m.role.rawValue, "content": m.content]) }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": wire,
            "stream": true
        ]

        var req = URLRequest(url: AIProvider.anthropic.endpoint)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        try await performStreamingRequest(req, session: session) { payload in
            if let delta = SseDeltas.anthropicDelta(payload) {
                onDelta(delta)
            }
        }
    }

    func fetchModels(key: String, session: URLSession) async throws -> [String] {
        var ids: [String] = []
        var seenIDs = Set<String>()
        var seenCursors = Set<String>()
        var cursor: String?
        // A failed or malformed later page must never become a successful partial catalogue.
        for _ in 0..<64 {
            try Task.checkCancellation()
            var url = URLComponents(url: AIProvider.anthropic.modelsEndpoint, resolvingAgainstBaseURL: false)!
            url.queryItems = [URLQueryItem(name: "limit", value: "1000")]
            if let cursor { url.queryItems?.append(URLQueryItem(name: "after_id", value: cursor)) }
            var req = URLRequest(url: url.url!)
            req.httpMethod = "GET"
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let page = try await performRequest(req, session: session)
            guard page["data"] is [[String: Any]], let hasMore = page["has_more"] as? Bool else {
                throw AICoachError.decode
            }
            ids.append(contentsOf: parseModels(page).filter { seenIDs.insert($0).inserted })
            guard hasMore else { return ids }
            guard let next = page["last_id"] as? String, !next.isEmpty,
                  seenCursors.insert(next).inserted else { throw AICoachError.decode }
            cursor = next
        }
        throw AICoachError.decode
    }

    /// Pure: unwrap the catalogue, excluding models explicitly marked retired by the provider.
    func parseModels(_ json: [String: Any]) -> [String] {
        guard let list = json["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { row in
            guard row["lifecycle"] as? String != "retired",
                  let id = row["id"] as? String, !id.isEmpty else { return nil }
            return id
        }
    }
}
