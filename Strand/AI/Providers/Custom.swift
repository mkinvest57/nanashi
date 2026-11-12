import Foundation
import StrandAnalytics

/// A generic OpenAI-compatible provider pointed at a user-set base URL — e.g. a local LLM server such
/// as Ollama, LM Studio or llama.cpp (`http://localhost:11434/v1`), or any self-hosted gateway. Speaks
/// the OpenAI chat-completions wire format against `AIProvider.custom` endpoints. The API key is
/// optional — local servers usually need none — so the configured auth header is sent only when set.
struct CustomClient: AIProviderClient {

    func send(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession
    ) async throws -> String {
        try AIProvider.guardCustomBaseURL()
        return try await OpenAIChatTransport.send(
            request: request(key: key, model: model, systemPrompt: systemPrompt, messages: messages),
            modernParams: false, allowModernRetry: true, session: session
        )
    }

    /// Older local servers retain their classic parameters. A parameter-specific HTTP 400 may
    /// trigger one modern retry before any text arrives; a partial response is never replayed.
    func stream(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession,
        onDelta: (String) -> Void
    ) async throws {
        try AIProvider.guardCustomBaseURL()
        try await OpenAIChatTransport.stream(
            request: request(key: key, model: model, systemPrompt: systemPrompt, messages: messages),
            modernParams: false, allowModernRetry: true, session: session, onDelta: onDelta
        )
    }

    /// Appended to a reply when the server stopped early because it ran out of context window.
    /// Local OpenAI-compatible servers (notably Ollama, which defaults to a 2048-token window and
    /// IGNORES `num_ctx` on the `/v1` endpoint) truncate silently — no error, the text just stops
    /// mid-sentence. We can't raise the window over the OpenAI wire format, so we make the cutoff
    /// visible and tell the user exactly how to fix it.
    // #1074: kept provider-agnostic. The old note gave Ollama-specific `num_ctx` instructions that were
    // wrong for cloud providers (a DeepSeek user just hit the response-length cap, not a local window).
    static let truncationNote = "\n\n---\n*Reply cut off at the response-length limit. Ask a more "
        + "specific question for a shorter, complete answer — or, on a local server (e.g. Ollama), "
        + "raise its context window.*"

    /// Pure: unwrap an OpenAI-compatible chat-completions body into the assistant text. Appends
    /// `truncationNote` when the server stopped early (`finish_reason == "length"`) so a context-
    /// window cutoff is never silent. No network — unit-tested.
    func parseChatContent(_ json: [String: Any]) throws -> String {
        try OpenAIChatTransport.parseContent(json)
    }

    func fetchModels(key: String, session: URLSession) async throws -> [String] {
        try AIProvider.guardCustomBaseURL()   // #321: reject a public cleartext Custom URL before egress
        var req = URLRequest(url: AIProvider.custom.modelsEndpoint)
        req.httpMethod = "GET"
        AIProvider.applyCustomAuthHeader(key, to: &req)

        return parseModels(try await performRequest(req, session: session))
    }

    /// Pure: unwrap an OpenAI-compatible `/models` body into ids. Unlike OpenAI we keep *all* ids.
    /// Some enterprise gateways return a catalog (`catalog[].models`) rather than `data[].id`; keep
    /// those ids too so users do not have to type every supported model by hand.
    func parseModels(_ json: [String: Any]) -> [String] {
        if let list = json["data"] as? [[String: Any]] {
            return list.compactMap { row in
                guard let id = row["id"] as? String, !id.isEmpty else { return nil }
                return id
            }
        }
        guard let catalog = json["catalog"] as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        return catalog.flatMap { row -> [String] in
            guard let models = row["models"] as? [String] else { return [] }
            return models.filter { !$0.isEmpty }
        }.filter { id in
            if seen.contains(id) { return false }
            seen.insert(id)
            return true
        }
    }

    private func request(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)]
    ) throws -> URLRequest {
        var request = try OpenAIChatTransport.request(
            url: AIProvider.custom.endpoint, model: model, systemPrompt: systemPrompt, messages: messages
        )
        AIProvider.applyCustomAuthHeader(key, to: &request)
        return request
    }
}
