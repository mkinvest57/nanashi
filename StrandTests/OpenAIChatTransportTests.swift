import Foundation
import XCTest
@testable import Strand

/// Real URLSession HTTP/SSE requests intercepted locally; no API key, network or health data is used.
final class OpenAIChatTransportTests: XCTestCase {
    private let question: [(role: ChatMessage.Role, content: String)] = [(.user, "Synthetic question")]
    private let answer = #"{"choices":[{"message":{"content":"Synthetic answer"},"finish_reason":"stop"}]}"#
    private let streamAnswer = "data: {\"choices\":[{\"delta\":{\"content\":\"Synthetic answer\"}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"

    func testOpenAIRegularRequestStartsWithModernParameters() async throws {
        let fixture = CoachHTTPFixture([.init(status: 200, body: answer)])
        defer { fixture.session.invalidateAndCancel() }
        let reply = try await OpenAIClient().send(key: "synthetic-key", model: "gpt-5", systemPrompt: "Synthetic context",
                                                 messages: question, session: fixture.session)
        XCTAssertEqual(reply, "Synthetic answer")
        XCTAssertEqual(fixture.requests.count, 1)
        try assertModern(fixture.requests[0], streaming: false)
    }

    func testOpenAIStreamingStartsWithModernParametersAndPreservesChosenModel() async throws {
        let fixture = CoachHTTPFixture([.init(status: 200, body: streamAnswer)])
        defer { fixture.session.invalidateAndCancel() }
        var deltas = ""
        try await OpenAIClient().stream(key: "synthetic-key", model: "gpt-5", systemPrompt: "Synthetic context",
                                       messages: question, session: fixture.session) { deltas += $0 }
        XCTAssertEqual(deltas, "Synthetic answer")
        XCTAssertEqual(fixture.requests.count, 1)
        try assertModern(fixture.requests[0], streaming: true)
    }

    func testCustomStreamingRetriesOnlyRejectedLegacyParametersAndStaysStreaming() async throws {
        let fixture = CoachHTTPFixture([
            .init(status: 400, body: #"{"error":{"message":"Unsupported parameter: 'max_tokens'. Use 'max_completion_tokens' instead."}}"#),
            .init(status: 200, body: streamAnswer)
        ])
        defer { fixture.session.invalidateAndCancel() }
        var deltas = ""
        try await OpenAIChatTransport.stream(request: request(), modernParams: false, allowModernRetry: true,
                                             session: fixture.session) { deltas += $0 }
        XCTAssertEqual(deltas, "Synthetic answer")
        XCTAssertEqual(fixture.requests.count, 2)
        let first = try fixture.requests[0].body()
        XCTAssertEqual(first["max_tokens"] as? Int, 4096)
        XCTAssertEqual(first["temperature"] as? Double, 0.6)
        XCTAssertEqual(first["stream"] as? Bool, true)
        try assertModern(fixture.requests[1], streaming: true)
    }

    func testCustomRegularRetryUsesSameModernContract() async throws {
        let fixture = CoachHTTPFixture([
            .init(status: 400, body: #"{"error":{"message":"Unsupported value: 'temperature' does not support 0.6 with this model. Only the default (1) value is supported."}}"#),
            .init(status: 200, body: answer)
        ])
        defer { fixture.session.invalidateAndCancel() }
        let reply = try await OpenAIChatTransport.send(request: request(), modernParams: false, allowModernRetry: true,
                                                       session: fixture.session)
        XCTAssertEqual(reply, "Synthetic answer")
        XCTAssertEqual(fixture.requests.count, 2)
        try assertModern(fixture.requests[1], streaming: false)
    }

    func testUnrelatedHTTPFailuresAreNeverAutomaticallyRetried() async throws {
        for status in [400, 401, 403, 429, 500, 503] {
            let fixture = CoachHTTPFixture([.init(status: status, body: #"{"error":{"message":"Unsupported model"}}"#)])
            defer { fixture.session.invalidateAndCancel() }
            do {
                try await OpenAIChatTransport.stream(request: request(), modernParams: false, allowModernRetry: true,
                                                     session: fixture.session) { _ in XCTFail("Unexpected text") }
                XCTFail("Expected HTTP failure")
            } catch {}
            XCTAssertEqual(fixture.requests.count, 1, "status \(status)")
        }
    }

    func testModernRequestFailureIsNotRetriedWithLegacyShape() async throws {
        let fixture = CoachHTTPFixture([.init(status: 400, body: #"{"error":{"message":"Unsupported parameter: max_completion_tokens"}}"#)])
        defer { fixture.session.invalidateAndCancel() }
        do {
            _ = try await OpenAIClient().send(key: "synthetic-key", model: "gpt-5", systemPrompt: "",
                                              messages: question, session: fixture.session)
            XCTFail("Expected error")
        } catch {}
        XCTAssertEqual(fixture.requests.count, 1)
    }

    func testFailedCompatibilityRetryStopsAtTwoRequests() async throws {
        let rejection = CoachHTTPFixture.Response(status: 400, body: #"{"error":{"message":"Unsupported parameter: max_tokens"}}"#)
        let fixture = CoachHTTPFixture([rejection, rejection])
        defer { fixture.session.invalidateAndCancel() }
        do {
            try await OpenAIChatTransport.stream(request: request(), modernParams: false, allowModernRetry: true,
                                                 session: fixture.session) { _ in XCTFail("Unexpected text") }
            XCTFail("Expected error")
        } catch {}
        XCTAssertEqual(fixture.requests.count, 2)
    }

    func testErrorEventKeepsPartialTextAndNeverRetries() async throws {
        let body = "data: {\"choices\":[{\"delta\":{\"content\":\"Partial\"}}]}\n\ndata: {\"error\":{\"message\":\"Unsupported parameter: max_tokens\"}}\n\n"
        let fixture = CoachHTTPFixture([.init(status: 200, body: body)])
        defer { fixture.session.invalidateAndCancel() }
        var text = ""
        do {
            try await OpenAIChatTransport.stream(request: request(), modernParams: false, allowModernRetry: true,
                                                 session: fixture.session) { text += $0 }
            XCTFail("Expected provider error event")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Unsupported parameter: max_tokens"))
        }
        XCTAssertEqual(text, "Partial")
        XCTAssertEqual(fixture.requests.count, 1)
    }

    func testEmptyStreamingResponseIsAnError() async throws {
        let fixture = CoachHTTPFixture([.init(status: 200, body: "data: [DONE]\n\n")])
        defer { fixture.session.invalidateAndCancel() }
        do {
            try await OpenAIChatTransport.stream(request: request(), modernParams: true, allowModernRetry: false,
                                                 session: fixture.session) { _ in XCTFail("Unexpected text") }
            XCTFail("An empty response must not count as success")
        } catch let error as AICoachError {
            guard case .emptyReply = error else { return XCTFail("Expected emptyReply") }
        }
        XCTAssertEqual(fixture.requests.count, 1)
    }

    func testTruncatedStreamAndRegularReplyHaveSameExplicitNotice() async throws {
        let fixture = CoachHTTPFixture([.init(status: 200, body: "data: {\"choices\":[{\"delta\":{\"content\":\"Partial\"},\"finish_reason\":\"length\"}]}\n\ndata: [DONE]\n\n")])
        defer { fixture.session.invalidateAndCancel() }
        var text = ""
        try await OpenAIChatTransport.stream(request: request(), modernParams: true, allowModernRetry: false,
                                             session: fixture.session) { text += $0 }
        XCTAssertEqual(text, "Partial" + CustomClient.truncationNote)
        XCTAssertEqual(try OpenAIChatTransport.parseContent([
            "choices": [["message": ["content": "Partial"], "finish_reason": "length"]]
        ]), text)
        XCTAssertEqual(fixture.requests.count, 1)
    }

    func testReasoningOnlyLengthLimitHasActionableErrorInsteadOfBlankSuccess() throws {
        var state = OpenAIChatTransport.StreamState()
        _ = try state.consume(#"{"choices":[{"delta":{},"finish_reason":"length"}]}"#)
        XCTAssertThrowsError(try state.finish()) {
            XCTAssertTrue($0.localizedDescription.contains("before returning an answer"))
        }
    }

    func testPrematureEOFIsNotACompleteAnswer() async throws {
        let fixture = CoachHTTPFixture([.init(status: 200, body: "data: {\"choices\":[{\"delta\":{\"content\":\"Partial\"}}]}\n\n")])
        defer { fixture.session.invalidateAndCancel() }
        var text = ""
        do {
            try await OpenAIChatTransport.stream(request: request(), modernParams: true, allowModernRetry: false,
                                                 session: fixture.session) { text += $0 }
            XCTFail("Expected interrupted stream")
        } catch { XCTAssertTrue(error.localizedDescription.contains("before completing")) }
        XCTAssertEqual(text, "Partial")
        XCTAssertEqual(fixture.requests.count, 1)
    }

    func testFinishReasonWithoutDoneIsAcceptedForCompatibleServers() throws {
        var state = OpenAIChatTransport.StreamState()
        XCTAssertEqual(try state.consume(#"{"choices":[{"delta":{"content":"Complete"},"finish_reason":"stop"}]}"#), "Complete")
        XCTAssertNoThrow(try state.finish())
    }

    func testRefusalTextIsVisibleInBothPaths() throws {
        let text = "I cannot answer that question."
        XCTAssertEqual(try OpenAIChatTransport.parseContent([
            "choices": [["message": ["refusal": text], "finish_reason": "stop"]]
        ]), text)
        var state = OpenAIChatTransport.StreamState()
        XCTAssertEqual(try state.consume(#"{"choices":[{"delta":{"refusal":"I cannot answer that question."},"finish_reason":"stop"}]}"#), text)
        XCTAssertNoThrow(try state.finish())
    }

    func testContentFilteringAndMalformedPayloadCannotBecomeSuccess() throws {
        var state = OpenAIChatTransport.StreamState()
        _ = try state.consume(#"{"choices":[{"delta":{"content":"Partial"},"finish_reason":"content_filter"}]}"#)
        XCTAssertThrowsError(try state.finish()) { XCTAssertTrue($0.localizedDescription.contains("filtered")) }
        XCTAssertThrowsError(try state.consume("not JSON"))
    }

    func testCancelledTaskDoesNotStartARequest() async throws {
        let fixture = CoachHTTPFixture([.init(status: 200, body: streamAnswer)])
        defer { fixture.session.invalidateAndCancel() }
        let request = try request()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await OpenAIChatTransport.stream(request: request, modernParams: true, allowModernRetry: false,
                                                 session: fixture.session) { _ in XCTFail("Unexpected text") }
        }
        do { try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    func testCancellationWhileReadingStreamRemainsCancellation() async throws {
        let fixture = CoachHTTPFixture([.init(status: 200, body: "", error: URLError(.cancelled))])
        defer { fixture.session.invalidateAndCancel() }
        do {
            try await OpenAIChatTransport.stream(request: request(), modernParams: true, allowModernRetry: false,
                                                 session: fixture.session) { _ in XCTFail("Unexpected text") }
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(fixture.requests.count, 1)
    }

    func testRetryPolicyMatchesAndroidOracle() {
        let cases: [(Int, String)] = [
            (400, "Unsupported parameter: 'max_tokens'. Use 'max_completion_tokens' instead."),
            (400, "Unsupported value: 'temperature'; only the default is supported"),
            (400, "Unsupported model"), (429, "Unsupported parameter: max_tokens"),
            (500, "Unsupported parameter: temperature"), (400, "max_tokens exceeds context window"),
            (400, "Unsupported parameter: max_completion_tokens"), (400, "unknown parameter max_tokens"),
            (400, "temperature must be between 0 and 2"), (400, "MAX_TOKENS is not supported"),
            (400, "temperature not allowed"), (401, "temperature not allowed")
        ]
        let actual = cases.map { OpenAIChatTransport.shouldRetryModernParams(status: $0.0, detail: $0.1) ? "1" : "0" }.joined(separator: ",")
        XCTAssertEqual(actual, "1,1,0,0,0,0,0,1,0,1,1,0")
    }

    private func request() throws -> URLRequest {
        try OpenAIChatTransport.request(url: URL(string: "https://provider.invalid/v1/chat/completions")!,
                                        model: "gpt-5", systemPrompt: "Synthetic context", messages: question)
    }

    private func assertModern(_ request: CoachHTTPFixture.RecordedRequest, streaming: Bool) throws {
        let body = try request.body()
        XCTAssertEqual(body["model"] as? String, "gpt-5")
        XCTAssertEqual(body["max_completion_tokens"] as? Int, 4096)
        XCTAssertNil(body["max_tokens"])
        XCTAssertNil(body["temperature"])
        XCTAssertEqual(body["stream"] as? Bool, streaming ? true : nil)
        XCTAssertEqual((body["messages"] as? [[String: String]])?.last?["content"], "Synthetic question")
    }
}

final class CoachHTTPFixture {
    struct Response { let status: Int; let body: String; var error: URLError? = nil }
    struct RecordedRequest {
        let data: Data
        let urlRequest: URLRequest
        func body() throws -> [String: Any] { try JSONSerialization.jsonObject(with: data) as! [String: Any] }
    }
    private let lock = NSLock()
    private var pending: [Response]
    private var recorded: [RecordedRequest] = []
    private var heldDeliveries: [() -> Void] = []
    private let holdResponses: Bool
    private let onRequest: (() -> Void)?
    var requests: [RecordedRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    let session: URLSession
    private let identifier = UUID().uuidString

    init(_ responses: [Response], holdResponses: Bool = false, onRequest: (() -> Void)? = nil) {
        pending = responses
        self.holdResponses = holdResponses
        self.onRequest = onRequest
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CoachHTTPProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Synthetic-Fixture": identifier]
        session = URLSession(configuration: configuration)
        CoachHTTPProtocol.register(self, id: identifier)
    }
    deinit { CoachHTTPProtocol.unregister(id: identifier) }

    /// A deterministic transport gate for configuration races; never blocks a URLSession thread.
    func deliver(_ response: @escaping () -> Void) {
        lock.lock()
        if holdResponses { heldDeliveries.append(response) }
        lock.unlock()
        onRequest?()
        if !holdResponses { response() }
    }

    func releaseNextResponse() {
        lock.lock()
        let delivery = heldDeliveries.isEmpty ? nil : heldDeliveries.removeFirst()
        lock.unlock()
        delivery?()
    }

    func next(_ request: URLRequest) -> Response {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        lock.lock(); defer { lock.unlock() }
        recorded.append(.init(data: data, urlRequest: request))
        return pending.isEmpty ? .init(status: 500, body: "Unexpected extra request") : pending.removeFirst()
    }
}

private final class CoachHTTPProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fixtures: [String: WeakFixture] = [:]
    private struct WeakFixture { weak var value: CoachHTTPFixture? }
    static func register(_ fixture: CoachHTTPFixture, id: String) {
        lock.lock(); defer { lock.unlock() }; fixtures[id] = WeakFixture(value: fixture)
    }
    static func unregister(id: String) { lock.lock(); defer { lock.unlock() }; fixtures.removeValue(forKey: id) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let fixture = Self.fixtures[request.value(forHTTPHeaderField: "X-Synthetic-Fixture") ?? ""]?.value
        Self.lock.unlock()
        guard let fixture else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return
        }
        let result = fixture.next(request)
        fixture.deliver { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: result.status, httpVersion: nil,
                                           headerFields: ["Content-Type": result.body.hasPrefix("data:") ? "text/event-stream" : "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(result.body.utf8))
            if let error = result.error { client?.urlProtocol(self, didFailWithError: error) }
            else { client?.urlProtocolDidFinishLoading(self) }
        }
    }
    override func stopLoading() {}
}
