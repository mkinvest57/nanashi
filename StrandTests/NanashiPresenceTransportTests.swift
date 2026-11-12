import XCTest
import WhoopStore
@testable import Strand

/// Exercises the real provider payload/response path with synthetic summaries and intercepted HTTP.
/// The two DEBUG seams prevent access to Keychain and the application's default SQLite database.
@MainActor
final class NanashiPresenceTransportTests: XCTestCase {
    private let replyJSON = #"{"remarks":[{"scene":"sleep","text":"Your recorded night lasted 7.5 hours. Keep that schedule."}]}"#
    private let workouts = "Recent workouts (newest first):\n  2026-10-26 Synthetic Run, 30 min, avg HR 132"

    private func fixture(hold: Bool = false, onRequest: (() -> Void)? = nil) throws -> CoachHTTPFixture {
        let body = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": replyJSON], "finish_reason": "stop"]]
        ])
        return CoachHTTPFixture([.init(status: 200, body: String(decoding: body, as: UTF8.self))],
                                holdResponses: hold, onRequest: onRequest)
    }

    private func engine(session: URLSession) -> (AICoachEngine, Repository) {
        let repo = Repository(deviceId: "synthetic-presence-\(UUID())")
        repo.days = [DailyMetric(day: "2026-10-26", totalSleepMin: 450, efficiency: 0.94,
                                deepMin: 84, remMin: 114, lightMin: 252, disturbances: 2,
                                restingHr: 52, avgHrv: 65, recovery: 67, strain: 12.3, exerciseCount: 1,
                                spo2Red: 987654, spo2Ir: 876543)]
        let coach = AICoachEngine(repo: repo, session: session)
        coach.keyReadOverride = { nil }
        coach.recentWorkoutsOverride = { [workouts] in workouts }
        coach.provider = .custom
        coach.customBaseURL = "https://synthetic-provider.invalid/v1"
        coach.customConnected = true
        coach.dataConsent = true
        coach.model = "synthetic-model"
        return (coach, repo)
    }

    private func preservingPreferences(_ operation: () async throws -> Void) async rethrows {
        let keys = ["ai.provider", "ai.model", "ai.customConnected", "ai.dataConsent", "noop.coachEnabled",
                    AIProvider.customBaseURLKey, AIProvider.customAuthHeaderKey,
                    AICoachEngine.systemPromptKey, NanashiPresenceEngine.enabledKey,
                    "ai.includeOnDeviceSignals", "ai.multimodalChartEnabled", "ai.presence.connectionEpoch"]
        let saved = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        UserDefaults.standard.set(true, forKey: "noop.coachEnabled")
        UserDefaults.standard.set(true, forKey: NanashiPresenceEngine.enabledKey)
        defer {
            for (key, value) in saved {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        try await operation()
    }

    func testSeparateOptInAndEveryPreflightGatePreventRequestsAndWorkoutReads() async throws {
        try await preservingPreferences {
            let gates: [(String, (AICoachEngine, Repository) -> Void)] = [
                ("presence opt-in off", { _, _ in UserDefaults.standard.set(false, forKey: NanashiPresenceEngine.enabledKey) }),
                ("data consent off", { coach, _ in coach.dataConsent = false }),
                ("master off", { _, _ in UserDefaults.standard.set(false, forKey: "noop.coachEnabled") }),
                ("no data", { _, repo in repo.days = [] }),
                ("no configured local provider", { coach, _ in coach.customConnected = false }),
                ("cloud key absent", { coach, _ in coach.provider = .openAI }),
                ("chat already sending", { coach, _ in coach.sending = true })
            ]
            for (name, gate) in gates {
                UserDefaults.standard.set(true, forKey: "noop.coachEnabled")
                UserDefaults.standard.set(true, forKey: NanashiPresenceEngine.enabledKey)
                let fixture = CoachHTTPFixture([])
                defer { fixture.session.invalidateAndCancel() }
                let (coach, repo) = engine(session: fixture.session)
                var workoutReads = 0
                coach.recentWorkoutsOverride = { workoutReads += 1; return "Synthetic workouts" }
                gate(coach, repo)
                let result = try await coach.generatePresenceRemarks()
                XCTAssertTrue(result.isEmpty, name)
                XCTAssertTrue(fixture.requests.isEmpty, name)
                XCTAssertEqual(workoutReads, 0, name)
            }
        }
    }

    func testPresenceSendsOnlyCompactSummaryAndWorkoutsWithoutMutatingChat() async throws {
        try await preservingPreferences {
            let fixture = try fixture()
            defer { fixture.session.invalidateAndCancel() }
            let (coach, _) = engine(session: fixture.session)
            let chat = [ChatMessage(role: .user, text: "Private chat that must not be included"),
                        ChatMessage(role: .assistant, text: "Private answer that must stay in chat")]
            coach.messages = chat
            coach.errorText = "Existing chat status"
            coach.customSystemPrompt = "My preserved user override"
            coach.includeOnDeviceSignals = true
            coach.multimodalChartEnabled = true

            let result = try await coach.generatePresenceRemarks()

            XCTAssertEqual(result, [.init(scene: .sleep, text: "Your recorded night lasted 7.5 hours. Keep that schedule.")])
            XCTAssertEqual(coach.messages, chat)
            XCTAssertEqual(coach.errorText, "Existing chat status")
            XCTAssertFalse(coach.sending)
            XCTAssertEqual(coach.customSystemPrompt, "My preserved user override")
            XCTAssertEqual(fixture.requests.count, 1)
            let request = try XCTUnwrap(fixture.requests.first)
            XCTAssertEqual(request.urlRequest.url?.host, "synthetic-provider.invalid")
            XCTAssertNil(request.urlRequest.value(forHTTPHeaderField: "Authorization"))
            let body = try request.body()
            XCTAssertEqual(body["model"] as? String, "synthetic-model")
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertEqual(messages.count, 2)
            XCTAssertEqual(messages.first?["role"], "system")
            XCTAssertTrue(messages.first?["content"]?.contains(AICoachEngine.presencePrompt) == true)
            XCTAssertEqual(messages.last?["role"], "user")
            let context = try XCTUnwrap(messages.last?["content"])
            XCTAssertTrue(context.contains("2026-10-26:"))
            XCTAssertTrue(context.contains("charge 67"))
            XCTAssertTrue(context.contains(workouts))
            let payload = String(decoding: request.data, as: UTF8.self)
            XCTAssertFalse(payload.contains("Private chat"))
            XCTAssertFalse(payload.contains("Private answer"))
            XCTAssertFalse(payload.contains("987654"), "Raw optical sample must stay on device")
            XCTAssertFalse(payload.contains("876543"), "Raw optical sample must stay on device")
            XCTAssertFalse(payload.contains("My preserved user override"), "Ambient JSON contract is separate from the editable chat prompt")
            XCTAssertNil(body["stream"])
        }
    }

    func testChangedConfigurationAndWithdrawnConsentDiscardInFlightRemarks() async throws {
        try await preservingPreferences {
            let changes: [(String, (AICoachEngine, Repository) -> Void)] = [
                ("model changed away and back", { coach, _ in coach.model = "other"; coach.model = "synthetic-model" }),
                ("consent revoked and restored", { coach, _ in coach.dataConsent = false; coach.dataConsent = true }),
                ("endpoint changed", { coach, _ in coach.customBaseURL = "https://another-synthetic.invalid/v1" }),
                ("presence disabled", { _, _ in UserDefaults.standard.set(false, forKey: NanashiPresenceEngine.enabledKey) }),
                ("master disabled", { _, _ in UserDefaults.standard.set(false, forKey: "noop.coachEnabled") }),
                ("data removed", { _, repo in repo.days = [] })
            ]
            for (name, change) in changes {
                UserDefaults.standard.set(true, forKey: "noop.coachEnabled")
                UserDefaults.standard.set(true, forKey: NanashiPresenceEngine.enabledKey)
                let sent = expectation(description: name)
                let fixture = try fixture(hold: true, onRequest: { sent.fulfill() })
                defer { fixture.session.invalidateAndCancel() }
                let (coach, repo) = engine(session: fixture.session)
                let chat = [ChatMessage(role: .user, text: "Existing conversation")]
                coach.messages = chat
                let request = Task { try await coach.generatePresenceRemarks() }
                await fulfillment(of: [sent], timeout: 3)
                guard fixture.requests.count == 1 else {
                    request.cancel()
                    fixture.releaseNextResponse()
                    _ = try? await request.value
                    continue
                }
                change(coach, repo)
                fixture.releaseNextResponse()
                let result = try await request.value
                XCTAssertTrue(result.isEmpty, name)
                XCTAssertEqual(coach.messages, chat, name)
                XCTAssertEqual(fixture.requests.count, 1, name)
            }
        }
    }

    func testMalformedGeneratedJSONCannotBecomeAnInlineRemark() async throws {
        try await preservingPreferences {
            let fixture = CoachHTTPFixture([.init(status: 200, body: #"{"choices":[{"message":{"content":"not JSON"},"finish_reason":"stop"}]}"#)])
            defer { fixture.session.invalidateAndCancel() }
            let (coach, _) = engine(session: fixture.session)
            let result = try await coach.generatePresenceRemarks()
            XCTAssertTrue(result.isEmpty)
            XCTAssertTrue(coach.messages.isEmpty)
            XCTAssertNil(coach.errorText)
        }
    }
}
