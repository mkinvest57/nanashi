import Foundation
import StrandAnalytics

struct OpenAIClient: AIProviderClient {

    func send(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession
    ) async throws -> String {
        try await OpenAIChatTransport.send(
            request: request(key: key, model: model, systemPrompt: systemPrompt, messages: messages),
            modernParams: true, allowModernRetry: false, session: session
        )
    }

    /// Streaming and regular requests share the current Chat Completions parameter shape.
    func stream(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession,
        onDelta: (String) -> Void
    ) async throws {
        try await OpenAIChatTransport.stream(
            request: request(key: key, model: model, systemPrompt: systemPrompt, messages: messages),
            modernParams: true, allowModernRetry: false, session: session, onDelta: onDelta
        )
    }

    func fetchModels(key: String, session: URLSession) async throws -> [String] {
        var req = URLRequest(url: AIProvider.openAI.modelsEndpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        return parseModels(try await performRequest(req, session: session))
    }

    /// Pure: retain text-coaching candidates while excluding known incompatible/specialized models.
    /// The model list has no endpoint-capability field; manually entered IDs remain available.
    func parseModels(_ json: [String: Any], now: Date = Date()) -> [String] {
        guard let list = json["data"] as? [[String: Any]] else { return [] }
        let dateParser = ISO8601DateFormatter()
        dateParser.formatOptions = [.withFullDate]
        return list.compactMap { row in
            guard let id = row["id"] as? String, !id.isEmpty else { return nil }
            if let shutdown = row["shutdown_date"] as? String,
               let date = dateParser.date(from: shutdown), date <= now { return nil }
            return OpenAIChatTransport.isModelCandidate(id) ? id : nil
        }
    }

    private func request(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)]
    ) throws -> URLRequest {
        var request = try OpenAIChatTransport.request(
            url: AIProvider.openAI.endpoint, model: model, systemPrompt: systemPrompt, messages: messages
        )
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }
}
