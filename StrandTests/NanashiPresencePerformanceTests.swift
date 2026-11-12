import XCTest
import Combine
import WhoopStore
@testable import Strand

/// Guards bounded presentation work without timing thresholds, real keys or provider requests.
@MainActor
final class NanashiPresencePerformanceTests: XCTestCase {
    private func preservingPreferences(_ operation: () async throws -> Void) async rethrows {
        let keys = ["ai.provider", "ai.model", "ai.dataConsent", "noop.coachEnabled", "ai.presence.connectionEpoch"]
        let saved = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        UserDefaults.standard.set(true, forKey: "noop.coachEnabled")
        defer {
            for (key, value) in saved {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        try await operation()
    }

    func testRepeatedPresentationAvailabilityReadsDoNotReadKeychainAgain() async {
        await preservingPreferences {
            let coach = AICoachEngine(repo: Repository(deviceId: "synthetic-presence-performance"))
            var reads = 0
            var present = true
            coach.keyReadOverride = { reads += 1; return present ? "synthetic-not-a-key" : nil }
            coach.provider = .openAI
            coach.dataConsent = true
            for _ in 0..<100 {
                XCTAssertTrue(coach.hasKey)
                XCTAssertTrue(coach.isConfigured)
                XCTAssertTrue(coach.presenceAvailable)
            }
            XCTAssertEqual(reads, 1)
            coach.model = "another-model"
            for _ in 0..<100 { XCTAssertTrue(coach.presenceAvailable) }
            XCTAssertEqual(reads, 1, "Model/UI changes do not require credential I/O")
            present = false
            coach.refreshPresenceAccess()
            XCTAssertFalse(coach.presenceAvailable)
            XCTAssertFalse(coach.hasKey)
            XCTAssertFalse(coach.isConfigured)
            XCTAssertEqual(reads, 2, "Foreground access refresh observes a credential removed externally")
            coach.dataConsent = false
            coach.refreshPresenceAccess()
            for _ in 0..<100 { XCTAssertFalse(coach.presenceAvailable) }
            XCTAssertEqual(reads, 2, "Revoked consent does not read credentials")
            coach.keyReadOverride = { reads += 1; return "replacement-fixture" }
            XCTAssertTrue(coach.hasKey)
            XCTAssertTrue(coach.isConfigured)
            XCTAssertEqual(reads, 3, "Replacing a key fixture invalidates its availability snapshot")
        }
    }

    func testAccessIdentityStaysStableWhileMeasurementRevisionTracksCorrections() async {
        await preservingPreferences {
            let repo = Repository(deviceId: "synthetic-presence-revision")
            repo.days = [DailyMetric(day: "2026-10-26", totalSleepMin: 420, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil, strain: nil, exerciseCount: nil)]
            let coach = AICoachEngine(repo: repo)
            coach.keyReadOverride = { XCTFail("A signature must never read Keychain"); return nil }
            let original = coach.presenceConfigurationKey
            let originalData = coach.presenceDataRevision
            coach.messages = [ChatMessage(role: .assistant, text: "A streaming answer")]
            XCTAssertEqual(coach.presenceConfigurationKey, original)
            repo.days = [DailyMetric(day: "2026-10-26", totalSleepMin: 450, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil, strain: nil, exerciseCount: nil)]
            let corrected = coach.presenceConfigurationKey
            XCTAssertEqual(corrected, original, "Live corrections must not cancel a dated observation during cooldown")
            XCTAssertNotEqual(coach.presenceDataRevision, originalData)
            let correctedRevision = coach.presenceDataRevision
            repo.days = [DailyMetric(day: "2026-10-26", totalSleepMin: 450, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil, strain: nil, exerciseCount: nil)]
            XCTAssertEqual(coach.presenceConfigurationKey, corrected)
            XCTAssertEqual(coach.presenceDataRevision, correctedRevision)
            XCTAssertFalse(corrected.contains("BIOMETRIC"))
            XCTAssertFalse(corrected.contains("450"))
        }
    }

    func testDisabledAndIdleEngineDoesNoRepeatedAvailabilityWorkOrPublishing() async {
        let name = "NanashiPresencePerformanceTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var availabilityReads = 0
        let engine = NanashiPresenceEngine(defaults: defaults,
            available: { availabilityReads += 1; return false },
            configuration: { "same" }, generate: { XCTFail("Disabled engine cannot generate"); return [] })
        var publications = 0
        let subscription = engine.objectWillChange.sink { publications += 1 }
        for _ in 0..<100 {
            engine.suspend()
            engine.synchronizeConfiguration()
            await engine.refreshIfNeeded()
            XCTAssertNil(engine.remark(for: .day))
        }
        XCTAssertEqual(availabilityReads, 0)
        XCTAssertEqual(publications, 0)
        withExtendedLifetime(subscription) {}
    }
}
