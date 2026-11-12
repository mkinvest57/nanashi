import XCTest
import WhoopStore
@testable import Strand

/// Holds reads at their suspension points to exercise actual engine state without a provider,
/// a disk database, or a Keychain mutation.
@MainActor
final class CoachStateRaceTests: XCTestCase {
    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var opened = false

        func wait() async {
            if opened { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            opened = true
            continuation?.resume()
            continuation = nil
        }
    }

    private enum ReadFailure: Error { case temporarilyUnavailable }

    private func engine() async throws -> AICoachEngine {
        let repo = Repository(deviceId: "test-coach-state-\(UUID())")
        repo.setStoreForTesting(try await WhoopStore.inMemory())
        let coach = AICoachEngine(repo: repo)
        coach.provider = .custom
        coach.customBaseURL = "http://localhost:11434/v1"
        coach.customAuthHeader = .bearer
        coach.customConnected = true
        coach.dataConsent = false
        coach.model = "test-model"
        return coach
    }

    private func savedRows() -> [CoachMessageRow] {
        [CoachMessageRow(id: UUID().uuidString, role: "user", text: "Previously saved question",
                         provider: AIProvider.custom.rawValue,
                         createdAt: Int(Date().timeIntervalSince1970), orderIndex: 0)]
    }

    private func preservingPreferences(_ operation: () async throws -> Void) async rethrows {
        let keys = ["ai.provider", "ai.model", "ai.customConnected", "ai.dataConsent", "noop.coachEnabled",
                    AIProvider.customBaseURLKey, AIProvider.customAuthHeaderKey,
                    AICoachEngine.modelsCacheKey(.custom), AICoachEngine.modelsRefreshedKey(.custom)]
        let before = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        UserDefaults.standard.set(true, forKey: "noop.coachEnabled")
        UserDefaults.standard.set(["cached-model"], forKey: AICoachEngine.modelsCacheKey(.custom))
        UserDefaults.standard.set(123.0, forKey: AICoachEngine.modelsRefreshedKey(.custom))
        defer {
            for (key, value) in before {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        try await operation()
    }

    func testDelayedHistoryDoesNotOverwriteNewQuestionAndAnswer() async throws {
        try await preservingPreferences {
            let coach = try await engine()
            let gate = Gate()
            let started = expectation(description: "history read started")
            let rows = savedRows()
            coach.loadMessagesOverride = {
                started.fulfill()
                await gate.wait()
                return rows
            }
            let restore = Task { await coach.loadPersistedMessagesIfNeeded() }
            await fulfillment(of: [started], timeout: 2)

            coach.streamOverride = { _, delta in delta("Fresh answer") }
            await coach.send("Fresh question")
            await gate.open()
            await restore.value

            XCTAssertEqual(coach.messages.map(\.text), ["Fresh question", "Fresh answer"])
        }
    }

    func testExplicitClearRetiresHistoryEvenWhenReadCompletesAfterward() async throws {
        try await preservingPreferences {
            let coach = try await engine()
            let gate = Gate()
            let started = expectation(description: "history read started")
            let rows = savedRows()
            var reads = 0
            coach.loadMessagesOverride = {
                reads += 1
                started.fulfill()
                await gate.wait()
                return rows
            }
            let restore = Task { await coach.loadPersistedMessagesIfNeeded() }
            await fulfillment(of: [started], timeout: 2)
            coach.clearConversation()
            await gate.open()
            await restore.value
            await coach.loadPersistedMessagesIfNeeded()

            XCTAssertTrue(coach.messages.isEmpty, "Cleared history must not reappear from an older read")
            XCTAssertEqual(reads, 1, "Opening Coach again must not undo an explicit clear")
        }
    }

    func testTemporaryHistoryReadFailureCanRetryOnNextVisit() async throws {
        try await preservingPreferences {
            let coach = try await engine()
            let rows = savedRows()
            var reads = 0
            coach.loadMessagesOverride = {
                reads += 1
                if reads == 1 { throw ReadFailure.temporarilyUnavailable }
                return rows
            }
            await coach.loadPersistedMessagesIfNeeded()
            XCTAssertTrue(coach.messages.isEmpty)
            await coach.loadPersistedMessagesIfNeeded()

            XCTAssertEqual(reads, 2)
            XCTAssertEqual(coach.messages.map(\.text), rows.map(\.text))
        }
    }

    func testCancelledHistoryReadCanRetryWithoutApplyingItsResult() async throws {
        try await preservingPreferences {
            let coach = try await engine()
            let gate = Gate()
            let started = expectation(description: "history read started")
            let rows = savedRows()
            coach.loadMessagesOverride = {
                started.fulfill()
                await gate.wait()
                return rows
            }
            let restore = Task { await coach.loadPersistedMessagesIfNeeded() }
            await fulfillment(of: [started], timeout: 2)
            restore.cancel()
            await gate.open()
            await restore.value
            XCTAssertTrue(coach.messages.isEmpty)

            coach.loadMessagesOverride = { rows }
            await coach.loadPersistedMessagesIfNeeded()
            XCTAssertEqual(coach.messages.map(\.text), rows.map(\.text))
        }
    }

    func testEndpointChangeRejectsOldCatalogueAndDoesNotMarkNewConnectionFresh() async throws {
        try await preservingPreferences {
            let coach = try await engine()
            let gate = Gate()
            let started = expectation(description: "catalogue fetch started")
            coach.fetchModelsOverride = { _, _ in
                started.fulfill()
                await gate.wait()
                return ["old-endpoint-model"]
            }
            let before = coach.availableModels
            let refresh = Task { await coach.refreshModels() }
            await fulfillment(of: [started], timeout: 2)
            coach.customBaseURL = "http://localhost:1234/v1"
            await gate.open()
            await refresh.value

            XCTAssertEqual(coach.availableModels, before)
            XCTAssertEqual(UserDefaults.standard.stringArray(forKey: AICoachEngine.modelsCacheKey(.custom)),
                           ["cached-model"])
            XCTAssertEqual(UserDefaults.standard.double(forKey: AICoachEngine.modelsRefreshedKey(.custom)), 123)
            XCTAssertFalse(coach.refreshingModels)
        }
    }

    func testProviderRoundTripStillRejectsRequestFromPreviousConnection() async throws {
        try await preservingPreferences {
            let coach = try await engine()
            let gate = Gate()
            let started = expectation(description: "catalogue fetch started")
            coach.fetchModelsOverride = { _, _ in
                started.fulfill()
                await gate.wait()
                return ["old-connection-model"]
            }
            let refresh = Task { await coach.refreshModels() }
            await fulfillment(of: [started], timeout: 2)
            coach.provider = .anthropic
            coach.provider = .custom
            let currentModels = coach.availableModels
            await gate.open()
            await refresh.value

            XCTAssertEqual(coach.availableModels, currentModels)
            XCTAssertFalse(coach.availableModels.contains("old-connection-model"))
        }
    }

    func testAuthChangeDropsPreviousConnectionsAuthenticationError() async throws {
        try await preservingPreferences {
            let coach = try await engine()
            let gate = Gate()
            let started = expectation(description: "catalogue fetch started")
            coach.fetchModelsOverride = { _, _ in
                started.fulfill()
                await gate.wait()
                throw AICoachError.badKey
            }
            let refresh = Task { await coach.refreshModels() }
            await fulfillment(of: [started], timeout: 2)
            coach.customAuthHeader = .xAPIKey
            await gate.open()
            await refresh.value

            XCTAssertNil(coach.errorText)
            XCTAssertFalse(coach.keyRejected, "The previous header cannot diagnose the new connection")
            XCTAssertFalse(coach.refreshingModels)
        }
    }

    func testCancelledCatalogueDoesNotReplaceModelsOrSurfaceAnError() async throws {
        try await preservingPreferences {
            let coach = try await engine()
            let gate = Gate()
            let started = expectation(description: "catalogue fetch started")
            coach.fetchModelsOverride = { _, _ in
                started.fulfill()
                await gate.wait()
                return ["cancelled-result"]
            }
            let before = coach.availableModels
            let refresh = Task { await coach.refreshModels() }
            await fulfillment(of: [started], timeout: 2)
            refresh.cancel()
            await gate.open()
            await refresh.value

            XCTAssertEqual(coach.availableModels, before)
            XCTAssertNil(coach.errorText)
            XCTAssertFalse(coach.refreshingModels)
        }
    }
}
