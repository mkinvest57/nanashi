import XCTest
@testable import Strand

/// HTTP-shaped fixtures intercept every request before networking; no key or provider access.
final class AIProviderCataloguePaginationTests: XCTestCase {
    func testAnthropicLoadsAllPagesAndPreservesAuthentication() async throws {
        let fixture = CoachHTTPFixture([
            .init(status: 200, body: #"{"data":[{"id":"claude-sonnet-5-5"}],"has_more":true,"last_id":"cursor one"}"#),
            .init(status: 200, body: #"{"data":[{"id":"claude-sonnet-5-5"},{"id":"claude-haiku-5-5"}],"has_more":false}"#)
        ])
        defer { fixture.session.invalidateAndCancel() }
        let ids = try await AnthropicClient().fetchModels(key: "synthetic-only", session: fixture.session)
        XCTAssertEqual(ids, ["claude-sonnet-5-5", "claude-haiku-5-5"])
        XCTAssertEqual(fixture.requests.count, 2)
        let requests = fixture.requests.map(\.urlRequest)
        XCTAssertNil(query("after_id", requests[0]))
        XCTAssertEqual(query("after_id", requests[1]), "cursor one")
        for request in requests {
            XCTAssertEqual(query("limit", request), "1000")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "synthetic-only")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        }
    }

    func testGeminiLoadsAllPagesAndPreservesAuthentication() async throws {
        let fixture = CoachHTTPFixture([
            .init(status: 200, body: #"{"models":[{"name":"models/gemini-3.8-flash"}],"nextPageToken":"token/+ one"}"#),
            .init(status: 200, body: #"{"models":[{"name":"models/gemini-3.8-flash"},{"name":"models/gemini-4-argon"}]}"#)
        ])
        defer { fixture.session.invalidateAndCancel() }
        let ids = try await GeminiClient().fetchModels(key: "synthetic-only", session: fixture.session)
        XCTAssertEqual(ids, ["gemini-3.8-flash", "gemini-4-argon"])
        XCTAssertEqual(fixture.requests.count, 2)
        let requests = fixture.requests.map(\.urlRequest)
        XCTAssertNil(query("pageToken", requests[0]))
        XCTAssertEqual(query("pageToken", requests[1]), "token/+ one")
        for request in requests {
            XCTAssertEqual(query("pageSize", request), "1000")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "synthetic-only")
        }
    }

    func testLaterPageFailureNeverReturnsPartialCatalogue() async {
        for provider in [AIProvider.anthropic, .gemini] {
            let fixture = CoachHTTPFixture([
                .init(status: 200, body: firstPage(provider)),
                .init(status: 503, body: #"{"error":{"message":"Fixture unavailable"}}"#)
            ])
            defer { fixture.session.invalidateAndCancel() }
            do {
                _ = try await provider.client.fetchModels(key: "synthetic-only", session: fixture.session)
                XCTFail("Partial catalogue must not escape a failed second page")
            } catch {
                guard case AICoachError.server(503, _) = error else { XCTFail("Unexpected error: \(error)"); continue }
            }
            XCTAssertEqual(fixture.requests.count, 2)
        }
    }

    func testRepeatedCursorStopsWithoutReturningPartialCatalogue() async {
        for provider in [AIProvider.anthropic, .gemini] {
            let fixture = CoachHTTPFixture([
                .init(status: 200, body: firstPage(provider)),
                .init(status: 200, body: firstPage(provider))
            ])
            defer { fixture.session.invalidateAndCancel() }
            do {
                _ = try await provider.client.fetchModels(key: "synthetic-only", session: fixture.session)
                XCTFail("Repeated cursor must fail")
            } catch {
                guard case AICoachError.decode = error else { XCTFail("Unexpected error: \(error)"); continue }
            }
            XCTAssertEqual(fixture.requests.count, 2)
        }
    }

    func testMalformedLaterPageDoesNotLookLikeCatalogueCompletion() async {
        for provider in [AIProvider.anthropic, .gemini] {
            let fixture = CoachHTTPFixture([
                .init(status: 200, body: firstPage(provider)),
                .init(status: 200, body: "{}")
            ])
            defer { fixture.session.invalidateAndCancel() }
            do {
                _ = try await provider.client.fetchModels(key: "synthetic-only", session: fixture.session)
                XCTFail("Malformed catalogue must fail")
            } catch {
                guard case AICoachError.decode = error else { XCTFail("Unexpected error: \(error)"); continue }
            }
            XCTAssertEqual(fixture.requests.count, 2)
        }
    }

    private func firstPage(_ provider: AIProvider) -> String {
        provider == .anthropic
            ? #"{"data":[{"id":"claude-sonnet-5-5"}],"has_more":true,"last_id":"next"}"#
            : #"{"models":[{"name":"models/gemini-3.8-flash"}],"nextPageToken":"next"}"#
    }

    private func query(_ name: String, _ request: URLRequest) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}
