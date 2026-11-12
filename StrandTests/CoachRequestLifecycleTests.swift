import XCTest
@testable import Strand

/// Exercises actual request state with an injected stream: no provider, API key or strap required.
@MainActor
final class CoachRequestLifecycleTests: XCTestCase {
    private var briefPrefix: String { String(localized: "Today's brief") + "\n\n" }

    private func engine() -> AICoachEngine {
        let result = AICoachEngine(repo: Repository(deviceId: "test-coach-lifecycle-\(UUID())"))
        result.provider = .custom
        result.customConnected = true
        result.dataConsent = false
        result.model = "test-model"
        return result
    }

    /// These preferences belong to the test host; restore them so test order cannot change behavior.
    private func preservingPreferences(_ operation: () async throws -> Void) async rethrows {
        let keys = ["ai.provider", "ai.model", "ai.customConnected", "ai.dataConsent", "noop.coachEnabled",
                    AICoachEngine.modelsCacheKey(.custom), AICoachEngine.modelsRefreshedKey(.custom),
                    AICoachEngine.modelsCacheKey(.openAI)]
        let before = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        UserDefaults.standard.set(true, forKey: "noop.coachEnabled")
        defer {
            for (key, value) in before {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        try await operation()
    }

    func testExplicitRetryReplacesFailedPartialWithoutDuplicatingQuestion() async throws {
        await preservingPreferences {
            let coach = engine()
            coach.streamOverride = { _, delta in
                delta("Partial advice")
                throw AICoachError.server(500, "Temporary failure")
            }
            await coach.send("How was my sleep?")
            let questionID = coach.messages.first?.id
            XCTAssertTrue(coach.canRetryLastQuestion)
            XCTAssertNotNil(coach.errorText)
            XCTAssertTrue(coach.messages.last?.text.contains("Partial advice") == true)

            var receivedQuestions = 0
            coach.streamOverride = { wire, delta in
                receivedQuestions = wire.filter { $0.role == .user }.count
                XCTAssertFalse(wire.contains { $0.content.contains("Partial advice") })
                delta("A complete answer")
            }
            await coach.retryLastQuestion()
            XCTAssertEqual(receivedQuestions, 1)
            XCTAssertEqual(coach.messages.count, 2)
            XCTAssertEqual(coach.messages.first?.id, questionID)
            XCTAssertEqual(coach.messages.last?.text, "A complete answer")
            XCTAssertNil(coach.errorText)
            XCTAssertFalse(coach.canRetryLastQuestion)
        }
    }

    func testStopCancelsTransportAndConcurrentSendCannotInterleave() async {
        await preservingPreferences {
            let coach = engine()
            let started = expectation(description: "stream started")
            coach.streamOverride = { _, _ in
                started.fulfill()
                try await Task.sleep(nanoseconds: 30_000_000_000)
            }
            let first = Task { await coach.send("First question") }
            await fulfillment(of: [started], timeout: 2)
            await coach.send("Must not overlap")
            coach.stopResponse()
            await first.value
            XCTAssertFalse(coach.sending)
            XCTAssertNil(coach.errorText, "A user-requested stop is not a network failure")
            XCTAssertEqual(coach.messages.map(\.text), ["First question"])
            XCTAssertTrue(coach.canRetryLastQuestion)
        }
    }

    func testEmptyReplyIsAnActionableFailureRatherThanSuccessfulPlaceholder() async {
        await preservingPreferences {
            let coach = engine()
            coach.streamOverride = { _, delta in delta(" \n ") }
            await coach.send("My training plan?")
            XCTAssertNotNil(coach.errorText)
            XCTAssertEqual(coach.messages.count, 1)
            XCTAssertEqual(coach.messages.first?.role, .user)
            XCTAssertTrue(coach.canRetryLastQuestion)
        }
    }

    func testLiveCatalogueSurvivesEngineRecreationWithoutChangingSelectedModel() async {
        await preservingPreferences {
            let coach = engine()
            coach.fetchModelsOverride = { _, _ in ["live-new-model", "test-model"] }
            await coach.refreshModels()
            let recreated = AICoachEngine(repo: Repository(deviceId: "test-coach-catalogue-relaunch"))
            XCTAssertTrue(recreated.availableModels.contains("live-new-model"))
            XCTAssertEqual(recreated.model, "test-model")
        }
    }

    func testCatalogueRefreshFailureRetainsLastSuccessfulListDateAndSelection() async {
        await preservingPreferences {
            let coach = engine()
            coach.fetchModelsOverride = { _, _ in ["available-model"] }
            await coach.refreshModels()
            let lastList = coach.availableModels
            let lastDate = coach.modelCatalogueUpdatedAt
            XCTAssertNotNil(lastDate)
            XCTAssertEqual(coach.selectedModelIsListed, false, "A retained selection is not a live listing")
            coach.fetchModelsOverride = { _, _ in throw AICoachError.server(503, "Unavailable") }
            await coach.refreshModels()
            XCTAssertEqual(coach.availableModels, lastList)
            XCTAssertEqual(coach.modelCatalogueUpdatedAt, lastDate)
            XCTAssertEqual(coach.model, "test-model")
            XCTAssertNotNil(coach.errorText)
        }
    }

    func testEmptyCatalogueCannotOverwriteCacheOrBecomeFresh() async {
        await preservingPreferences {
            let coach = engine()
            coach.fetchModelsOverride = { _, _ in ["test-model", "new-model"] }
            await coach.refreshModels()
            let lastList = coach.availableModels
            let lastDate = coach.modelCatalogueUpdatedAt
            XCTAssertEqual(coach.selectedModelIsListed, true)
            coach.fetchModelsOverride = { _, _ in ["", " \n "] }
            await coach.refreshModels()
            XCTAssertEqual(coach.availableModels, lastList)
            XCTAssertEqual(coach.modelCatalogueUpdatedAt, lastDate)
            XCTAssertNotNil(coach.errorText)
        }
    }

    func testCatalogueRefreshDueDailyAndClockRollbackKeepsCache() {
        let last: TimeInterval = 1_800_000_000
        XCTAssertFalse(AICoachEngine.isCatalogueStale(last: last, now: last + 86_399))
        XCTAssertTrue(AICoachEngine.isCatalogueStale(last: last, now: last + 86_400))
        XCTAssertFalse(AICoachEngine.isCatalogueStale(last: last, now: last - 3600))
    }

    func testRestoredUnansweredQuestionCanBeRetriedWithoutDuplicate() async {
        await preservingPreferences {
            let coach = engine()
            let unanswered = ChatMessage(role: .user, text: "Saved question")
            coach.messages = [unanswered]
            coach.streamOverride = { _, delta in delta("Answer after relaunch") }
            XCTAssertTrue(coach.canRetryLastQuestion)
            await coach.retryLastQuestion()
            XCTAssertEqual(coach.messages.count, 2)
            XCTAssertEqual(coach.messages.first?.id, unanswered.id)
        }
    }

    func testRelaunchDoesNotReintroduceRetiredBuiltinModels() async {
        await preservingPreferences {
            UserDefaults.standard.set(AIProvider.openAI.rawValue, forKey: "ai.provider")
            UserDefaults.standard.set("gpt-5", forKey: "ai.model")
            UserDefaults.standard.set(["gpt-5", "live-new-model"],
                                      forKey: AICoachEngine.modelsCacheKey(.openAI))
            let recreated = AICoachEngine(repo: Repository(deviceId: "test-coach-retired-catalogue"))
            XCTAssertEqual(recreated.availableModels, ["gpt-5", "live-new-model"])
            XCTAssertFalse(recreated.availableModels.contains("gpt-4o"))
            XCTAssertEqual(recreated.model, "gpt-5")
        }
    }

    func testInterleavedBriefCannotBeOverwrittenOrDeletedByQuestionRetry() async {
        await preservingPreferences {
            for fails in [false, true] {
                let coach = engine()
                coach.streamOverride = { _, delta in
                    delta("Streamed answer")
                    coach.appendGeneratedBrief("Independent brief")
                    delta(" continues")
                    if fails { throw AICoachError.server(500, "Synthetic failure") }
                }
                await coach.send("Synthetic question")
                coach.streamOverride = nil
                XCTAssertEqual(coach.messages.count, 3)
                XCTAssertEqual(Set(coach.messages.map(\.id)).count, 3, "No duplicate placeholder identity")
                XCTAssertTrue(coach.messages[1].text.hasPrefix("Streamed answer continues"))
                XCTAssertEqual(coach.messages[2].text, briefPrefix + "Independent brief")
                XCTAssertFalse(coach.canRetryLastQuestion, "A later independent turn must never be deleted by retry")
                let before = coach.messages
                await coach.retryLastQuestion()
                XCTAssertEqual(coach.messages, before)
            }
        }
    }

    func testEmptyFailedStreamRemovesOnlyItsOwnPlaceholder() async {
        await preservingPreferences {
            let coach = engine()
            coach.streamOverride = { _, _ in
                coach.appendGeneratedBrief("Independent brief")
                throw AICoachError.server(500, "Synthetic failure")
            }
            await coach.send("Synthetic question")
            coach.streamOverride = nil
            XCTAssertEqual(coach.messages.map(\.text), ["Synthetic question", briefPrefix + "Independent brief"])
            XCTAssertFalse(coach.canRetryLastQuestion)
        }
    }

    func testInterleavedManualBriefPreservesBothBriefIdentitiesOnSuccessAndError() async {
        await preservingPreferences {
            for fails in [false, true] {
                let coach = engine()
                coach.dataConsent = true
                coach.streamOverride = { _, delta in
                    delta("Streamed brief")
                    coach.appendGeneratedBrief("Independent brief")
                    delta(" continues")
                    if fails { throw AICoachError.server(500, "Synthetic failure") }
                }
                await coach.startBriefIfNeeded()
                coach.streamOverride = nil
                XCTAssertEqual(coach.messages.count, 2)
                XCTAssertEqual(Set(coach.messages.map(\.id)).count, 2)
                XCTAssertTrue(coach.messages[0].text.hasPrefix(briefPrefix + "Streamed brief continues"))
                XCTAssertEqual(coach.messages[1].text, briefPrefix + "Independent brief")
            }
        }
    }
}
