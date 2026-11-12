import XCTest
@testable import Strand

/// Exercises foreground remark orchestration without HTTP, a database, or the user's preferences.
@MainActor
final class NanashiPresenceEngineTests: XCTestCase {
    private final class Inputs {
        var available = true
        var busy = false
        var dataRevision: UInt64 = 0
        var demo = false
        var configuration = "provider:model:language:snapshot-1"
        var now = Date(timeIntervalSince1970: 1_790_000_000)
    }

    /// Deliberately ignores task cancellation so late transport completions exercise the engine gate.
    private actor Gate {
        private var continuations: [CheckedContinuation<Void, Never>] = []
        private var opened = false

        func wait() async {
            if opened { return }
            await withCheckedContinuation { continuations.append($0) }
        }

        func open() {
            opened = true
            for continuation in continuations { continuation.resume() }
            continuations = []
        }
    }

    private enum TransportFailure: Error { case unavailable }

    private func withDefaults(_ operation: (UserDefaults) async throws -> Void) async rethrows {
        let suite = "NanashiPresenceEngineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try await operation(defaults)
    }

    private func engine(defaults: UserDefaults, inputs: Inputs,
                        generate: @escaping () async throws -> [NanashiPresenceRemark]) -> NanashiPresenceEngine {
        NanashiPresenceEngine(defaults: defaults, available: { inputs.available },
                              busy: { inputs.busy }, demo: { inputs.demo },
                              configuration: { inputs.configuration },
                              dataRevision: { inputs.dataRevision }, clock: { inputs.now },
                              generate: generate)
    }

    private func batch(_ text: String = "Current observation") -> [NanashiPresenceRemark] {
        [.init(scene: .day, text: text), .init(scene: .sleep, text: "Current sleep observation")]
    }

    private func settled(_ engine: NanashiPresenceEngine,
                         file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1_000 {
            if !engine.isGenerating { return }
            await Task.yield()
        }
        XCTFail("The injected request did not settle", file: file, line: line)
    }

    private func drainActor() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private func persistedBudget(_ defaults: UserDefaults) throws -> NanashiPresenceBudget {
        let data = try XCTUnwrap(defaults.data(forKey: NanashiPresenceEngine.budgetKey))
        return try JSONDecoder().decode(NanashiPresenceBudget.self, from: data)
    }

    func testDefaultOffUnavailableAndBusyNeverCallTransportOrConsumeBudget() async {
        await withDefaults { defaults in
            let inputs = Inputs()
            var calls = 0
            let engine = engine(defaults: defaults, inputs: inputs) {
                calls += 1
                return self.batch()
            }
            XCTAssertFalse(engine.enabled)
            await engine.refreshIfNeeded()
            engine.enabled = true
            inputs.available = false
            await engine.refreshIfNeeded()
            inputs.available = true
            inputs.busy = true
            await engine.refreshIfNeeded()
            await drainActor()

            XCTAssertEqual(calls, 0)
            XCTAssertNil(defaults.data(forKey: NanashiPresenceEngine.budgetKey))
            XCTAssertNil(engine.generatedAt)
            XCTAssertFalse(engine.isGenerating)
        }
    }

    func testConcurrentVisibleHostsShareOneBatchAndRefreshCooldown() async throws {
        try await withDefaults { defaults in
            let inputs = Inputs(), gate = Gate()
            let started = expectation(description: "single shared request started")
            var calls = 0
            let engine = engine(defaults: defaults, inputs: inputs) {
                calls += 1
                started.fulfill()
                await gate.wait()
                return self.batch()
            }
            engine.enabled = true
            let hosts = (0..<8).map { _ in Task { await engine.refreshIfNeeded() } }
            for host in hosts { await host.value }
            await fulfillment(of: [started], timeout: 2)
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(try persistedBudget(defaults).attemptCount, 1,
                           "The allowance must be charged before transport completes")
            await gate.open()
            await settled(engine)
            XCTAssertEqual(engine.remark(for: .day)?.text, "Current observation")
            XCTAssertEqual(engine.remark(for: .sleep)?.text, "Current sleep observation")

            inputs.now = inputs.now.addingTimeInterval(29 * 60)
            await engine.refreshIfNeeded()
            await drainActor()
            XCTAssertEqual(calls, 1)
        }
    }

    func testFailedAttemptBudgetAndBackoffSurviveEngineRecreation() async throws {
        try await withDefaults { defaults in
            let inputs = Inputs(), originalTime = inputs.now
            var calls = 0
            let failed = engine(defaults: defaults, inputs: inputs) {
                calls += 1
                throw TransportFailure.unavailable
            }
            failed.enabled = true
            await failed.refreshIfNeeded()
            await settled(failed)
            let budget = try persistedBudget(defaults)
            XCTAssertEqual(budget.attemptCount, 1)
            XCTAssertEqual(budget.lastAttempt, originalTime)
            XCTAssertEqual(budget.blockedUntil, originalTime.addingTimeInterval(15 * 60))
            XCTAssertNil(failed.generatedAt)

            let recreated = engine(defaults: defaults, inputs: inputs) {
                calls += 1
                return self.batch()
            }
            XCTAssertTrue(recreated.enabled)
            inputs.now = originalTime.addingTimeInterval(29 * 60)
            await recreated.refreshIfNeeded()
            await drainActor()
            XCTAssertEqual(calls, 1)
            inputs.now = originalTime.addingTimeInterval(30 * 60)
            await recreated.refreshIfNeeded()
            await settled(recreated)
            XCTAssertEqual(calls, 2)
            XCTAssertEqual(try persistedBudget(defaults).attemptCount, 2)
            XCTAssertNotNil(recreated.remark(for: .day))
        }
    }

    func testLateFailureExtendsBackoffBeyondTheNormalRequestInterval() async throws {
        try await withDefaults { defaults in
            let inputs = Inputs(), gate = Gate(), originalTime = inputs.now
            let started = expectation(description: "slow failing request started")
            let engine = engine(defaults: defaults, inputs: inputs) {
                started.fulfill()
                await gate.wait()
                throw TransportFailure.unavailable
            }
            engine.enabled = true
            await engine.refreshIfNeeded()
            await fulfillment(of: [started], timeout: 2)
            inputs.now = originalTime.addingTimeInterval(25 * 60)
            await gate.open()
            await settled(engine)
            let budget = try persistedBudget(defaults)
            XCTAssertEqual(budget.blockedUntil, originalTime.addingTimeInterval(40 * 60))
            XCTAssertFalse(budget.canRequest(now: originalTime.addingTimeInterval(30 * 60),
                                            dayKey: Repository.localDayKey(originalTime)))
        }
    }

    func testEmptyResponseCountsAsFailureAndKeepsCurrentBatch() async throws {
        try await withDefaults { defaults in
            let inputs = Inputs(), originalTime = inputs.now
            var calls = 0
            let engine = engine(defaults: defaults, inputs: inputs) {
                calls += 1
                return calls == 1 ? self.batch() : []
            }
            engine.enabled = true
            await engine.refreshIfNeeded()
            await settled(engine)
            inputs.now = originalTime.addingTimeInterval(30 * 60)
            await engine.refreshIfNeeded()
            await settled(engine)

            XCTAssertEqual(calls, 2)
            XCTAssertEqual(engine.generatedAt, originalTime)
            XCTAssertEqual(engine.remark(for: .day)?.text, "Current observation")
            XCTAssertEqual(try persistedBudget(defaults).attemptCount, 2)
            XCTAssertEqual(try persistedBudget(defaults).blockedUntil, inputs.now.addingTimeInterval(15 * 60))
        }
    }

    func testDismissedSceneStaysQuietAcrossNewBatchesInTheSameSession() async {
        await withDefaults { defaults in
            let inputs = Inputs()
            var calls = 0
            let engine = engine(defaults: defaults, inputs: inputs) {
                calls += 1
                return self.batch("Batch \(calls)")
            }
            engine.enabled = true
            await engine.refreshIfNeeded()
            await settled(engine)
            engine.dismiss(.day)
            XCTAssertNil(engine.remark(for: .day))
            XCTAssertNotNil(engine.remark(for: .sleep))
            inputs.now = inputs.now.addingTimeInterval(30 * 60)
            await engine.refreshIfNeeded()
            await settled(engine)

            XCTAssertEqual(calls, 2)
            XCTAssertNil(engine.remark(for: .day))
            XCTAssertNotNil(engine.remark(for: .sleep))
            XCTAssertEqual(engine.generatedAt, inputs.now)
        }
    }

    func testDisablingCancelsPendingRequestAndRejectsItsLateResult() async throws {
        try await withDefaults { defaults in
            let inputs = Inputs(), gate = Gate()
            let started = expectation(description: "request started")
            let returned = expectation(description: "cancelled transport returned anyway")
            let engine = engine(defaults: defaults, inputs: inputs) {
                started.fulfill()
                await gate.wait()
                returned.fulfill()
                return self.batch("Must never appear")
            }
            engine.enabled = true
            await engine.refreshIfNeeded()
            await fulfillment(of: [started], timeout: 2)
            engine.enabled = false
            XCTAssertFalse(engine.isGenerating)
            XCTAssertFalse(defaults.bool(forKey: NanashiPresenceEngine.enabledKey))
            engine.enabled = true
            await gate.open()
            await fulfillment(of: [returned], timeout: 2)
            await drainActor()

            XCTAssertNil(engine.generatedAt)
            XCTAssertNil(engine.remark(for: .day))
            XCTAssertTrue(defaults.bool(forKey: NanashiPresenceEngine.enabledKey))
            XCTAssertEqual(try persistedBudget(defaults).attemptCount, 1)
            XCTAssertNil(try persistedBudget(defaults).blockedUntil,
                         "An explicit cancellation is not a provider failure")
        }
    }

    func testConfigurationChangeCancelsPendingRequestAndRejectsLateResult() async {
        await withDefaults { defaults in
            let inputs = Inputs(), gate = Gate()
            let started = expectation(description: "old configuration request started")
            let returned = expectation(description: "old configuration result returned")
            let engine = engine(defaults: defaults, inputs: inputs) {
                started.fulfill()
                await gate.wait()
                returned.fulfill()
                return self.batch("Old provider observation")
            }
            engine.enabled = true
            await engine.refreshIfNeeded()
            await fulfillment(of: [started], timeout: 2)
            inputs.configuration = "new-provider:new-model:language:snapshot-1"
            engine.synchronizeConfiguration()
            XCTAssertFalse(engine.isGenerating)
            XCTAssertEqual(engine.configurationKey, inputs.configuration)
            await gate.open()
            await fulfillment(of: [returned], timeout: 2)
            await drainActor()

            XCTAssertNil(engine.generatedAt)
            XCTAssertNil(engine.remark(for: .day))
        }
    }

    func testDataCorrectionKeepsDatedBatchDuringCooldownAndRefreshesLater() async {
        await withDefaults { defaults in
            let inputs = Inputs()
            var calls = 0
            let engine = engine(defaults: defaults, inputs: inputs) {
                calls += 1
                return self.batch("Observation \(calls)")
            }
            engine.enabled = true
            await engine.refreshIfNeeded()
            await settled(engine)
            inputs.dataRevision += 1
            engine.synchronizeConfiguration()
            XCTAssertEqual(engine.remark(for: .sleep)?.text, "Current sleep observation")
            XCTAssertTrue(engine.hasNewerReadings, "The retained analysis must be labelled as an earlier snapshot")
            await engine.refreshIfNeeded()
            await drainActor()
            XCTAssertEqual(calls, 1, "Sync must not spend another request or erase the earlier analysis")
            inputs.now = inputs.now.addingTimeInterval(30 * 60)
            await engine.refreshIfNeeded()
            await settled(engine)
            XCTAssertEqual(engine.remark(for: .day)?.text, "Observation 2")
            XCTAssertFalse(engine.hasNewerReadings)
        }
    }

    func testSyncDuringGenerationPublishesDatedSnapshotInsteadOfDiscardingResult() async {
        await withDefaults { defaults in
            let inputs = Inputs(), gate = Gate()
            let started = expectation(description: "snapshot request started")
            let engine = engine(defaults: defaults, inputs: inputs) {
                started.fulfill()
                await gate.wait()
                return self.batch()
            }
            engine.enabled = true
            await engine.refreshIfNeeded()
            await fulfillment(of: [started], timeout: 2)
            inputs.dataRevision += 1
            engine.synchronizeConfiguration()
            XCTAssertTrue(engine.isGenerating)
            await gate.open()
            await settled(engine)
            XCTAssertNotNil(engine.remark(for: .day))
            XCTAssertTrue(engine.hasNewerReadings)
        }
    }

    func testGeneralObservationReachesOtherPagesWithoutOverridingSpecificRemark() async {
        await withDefaults { defaults in
            let inputs = Inputs()
            let engine = engine(defaults: defaults, inputs: inputs) {
                [.init(scene: .general, text: "Overall observation"), .init(scene: .sleep, text: "Sleep observation")]
            }
            engine.enabled = true
            await engine.refreshIfNeeded()
            await settled(engine)
            XCTAssertEqual(engine.remark(for: .activity)?.text, "Overall observation")
            XCTAssertEqual(engine.remark(for: .sleep)?.text, "Sleep observation")
            engine.dismiss(.activity)
            XCTAssertNil(engine.remark(for: .activity))
            XCTAssertNotNil(engine.remark(for: .explore))
        }
    }

    func testRecreatedEngineRestoresDatedRemarksWithoutAnotherRequestAndRevocationRemovesCache() async throws {
        try await withDefaults { defaults in
            let inputs = Inputs()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let cache = NanashiPresenceCache(fileURL: directory.appendingPathComponent("remarks.json"))
            var calls = 0
            @MainActor func makeEngine() -> NanashiPresenceEngine {
                NanashiPresenceEngine(defaults: defaults, available: { inputs.available },
                    configuration: { inputs.configuration }, cache: cache, clock: { inputs.now }) {
                        calls += 1
                        return self.batch()
                    }
            }
            let first = makeEngine()
            first.enabled = true
            await first.refreshIfNeeded()
            await settled(first)
            XCTAssertNotNil(cache.load())
            let restored = makeEngine()
            await restored.refreshIfNeeded()
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(restored.remark(for: .day)?.text, "Current observation")
            XCTAssertEqual(restored.generatedAt, first.generatedAt)
            XCTAssertTrue(restored.hasNewerReadings, "A previous process snapshot is labelled as an earlier analysis")
            restored.enabled = false
            XCTAssertNil(cache.load())
            XCTAssertNil(restored.remark(for: .day))
        }
    }

    func testLosingAvailabilityImmediatelyHidesAndClearsTheBatch() async {
        await withDefaults { defaults in
            let inputs = Inputs()
            let engine = engine(defaults: defaults, inputs: inputs) { self.batch() }
            engine.enabled = true
            await engine.refreshIfNeeded()
            await settled(engine)
            inputs.available = false
            XCTAssertNil(engine.remark(for: .day))
            engine.synchronizeConfiguration()
            XCTAssertNil(engine.generatedAt)
            inputs.available = true
            XCTAssertNil(engine.remark(for: .day), "Revoked data must not reappear after reconnection")
        }
    }

    func testSuspendingKeepsCurrentBatchButRejectsPendingReplacement() async {
        await withDefaults { defaults in
            let inputs = Inputs(), gate = Gate(), originalTime = inputs.now
            let started = expectation(description: "replacement started")
            let returned = expectation(description: "replacement returned after suspension")
            var calls = 0
            let engine = engine(defaults: defaults, inputs: inputs) {
                calls += 1
                if calls == 1 { return self.batch("Current batch") }
                started.fulfill()
                await gate.wait()
                returned.fulfill()
                return self.batch("Suspended replacement")
            }
            engine.enabled = true
            await engine.refreshIfNeeded()
            await settled(engine)
            inputs.now = originalTime.addingTimeInterval(30 * 60)
            await engine.refreshIfNeeded()
            await fulfillment(of: [started], timeout: 2)
            engine.suspend()
            XCTAssertFalse(engine.isGenerating)
            XCTAssertEqual(engine.remark(for: .day)?.text, "Current batch")
            await gate.open()
            await fulfillment(of: [returned], timeout: 2)
            await drainActor()

            XCTAssertEqual(engine.generatedAt, originalTime)
            XCTAssertEqual(engine.remark(for: .day)?.text, "Current batch")
        }
    }

    func testCancelledOldTaskCannotClearANewerRequestsGeneratingState() async {
        await withDefaults { defaults in
            let inputs = Inputs(), oldGate = Gate(), newGate = Gate()
            let oldStarted = expectation(description: "old request started")
            let newStarted = expectation(description: "new request started")
            let oldReturned = expectation(description: "old request returned")
            var calls = 0
            let engine = engine(defaults: defaults, inputs: inputs) {
                calls += 1
                if calls == 1 {
                    oldStarted.fulfill()
                    await oldGate.wait()
                    oldReturned.fulfill()
                    return self.batch("Retired result")
                }
                newStarted.fulfill()
                await newGate.wait()
                return self.batch("New result")
            }
            engine.enabled = true
            await engine.refreshIfNeeded()
            await fulfillment(of: [oldStarted], timeout: 2)
            engine.suspend()
            inputs.now = inputs.now.addingTimeInterval(30 * 60)
            await engine.refreshIfNeeded()
            await fulfillment(of: [newStarted], timeout: 2)
            await oldGate.open()
            await fulfillment(of: [oldReturned], timeout: 2)
            await drainActor()
            XCTAssertTrue(engine.isGenerating, "The retired task must not clean up its successor")
            XCTAssertNil(engine.remark(for: .day))
            await newGate.open()
            await settled(engine)
            XCTAssertEqual(calls, 2)
            XCTAssertEqual(engine.remark(for: .day)?.text, "New result")
        }
    }

    func testCoachBecomingBusySuspendsThePendingRemarkRequest() async {
        await withDefaults { defaults in
            let inputs = Inputs(), gate = Gate()
            let started = expectation(description: "remark request started")
            let returned = expectation(description: "remark returned after Coach started")
            let engine = engine(defaults: defaults, inputs: inputs) {
                started.fulfill()
                await gate.wait()
                returned.fulfill()
                return self.batch("Superseded by explicit Coach request")
            }
            engine.enabled = true
            await engine.refreshIfNeeded()
            await fulfillment(of: [started], timeout: 2)
            inputs.busy = true
            engine.synchronizeConfiguration()
            XCTAssertFalse(engine.isGenerating)
            await gate.open()
            await fulfillment(of: [returned], timeout: 2)
            await drainActor()
            XCTAssertNil(engine.generatedAt)
            XCTAssertNil(engine.remark(for: .day))
        }
    }

    func testRemarksExpireAtSixHoursAndHideOnClockRewindWithoutTransport() async {
        await withDefaults { defaults in
            let inputs = Inputs(), originalTime = inputs.now
            var calls = 0
            let engine = engine(defaults: defaults, inputs: inputs) {
                calls += 1
                return self.batch()
            }
            engine.enabled = true
            await engine.refreshIfNeeded()
            await settled(engine)
            inputs.now = originalTime.addingTimeInterval(6 * 60 * 60 - 1)
            XCTAssertNotNil(engine.remark(for: .day))
            inputs.now = originalTime.addingTimeInterval(6 * 60 * 60)
            XCTAssertNil(engine.remark(for: .day))
            inputs.now = originalTime.addingTimeInterval(-1)
            XCTAssertNil(engine.remark(for: .day))
            await engine.refreshIfNeeded()
            await drainActor()
            XCTAssertEqual(calls, 1, "Read access and a backwards clock must never create new transport")
        }
    }

    func testDemoNeedsNoProviderAndNeverPersistsConsentOrBudget() async {
        await withDefaults { defaults in
            let inputs = Inputs()
            inputs.available = false
            inputs.demo = true
            var calls = 0
            let engine = engine(defaults: defaults, inputs: inputs) {
                calls += 1
                return self.batch()
            }
            engine.synchronizeConfiguration()
            XCTAssertTrue(engine.enabled)
            XCTAssertTrue(engine.isAvailable)
            await engine.refreshIfNeeded()
            for scene in NanashiPresenceScene.allCases { XCTAssertNotNil(engine.remark(for: scene)) }
            engine.enabled = false
            await engine.refreshIfNeeded()
            XCTAssertFalse(engine.enabled, "A demo opt-out must remain off on the next page")
            XCTAssertNil(engine.remark(for: .day))
            XCTAssertNil(defaults.object(forKey: NanashiPresenceEngine.enabledKey))
            XCTAssertNil(defaults.object(forKey: NanashiPresenceEngine.budgetKey))
            XCTAssertEqual(calls, 0)
        }
    }

    func testExpiredDemoBatchCanRefreshWithoutTransport() async {
        await withDefaults { defaults in
            let inputs = Inputs()
            inputs.demo = true
            var calls = 0
            let engine = engine(defaults: defaults, inputs: inputs) {
                calls += 1
                return self.batch()
            }
            await engine.refreshIfNeeded()
            inputs.now = inputs.now.addingTimeInterval(6 * 60 * 60)
            XCTAssertNil(engine.remark(for: .day))
            await engine.refreshIfNeeded()
            XCTAssertNotNil(engine.remark(for: .day))
            XCTAssertEqual(engine.generatedAt, inputs.now)
            XCTAssertEqual(calls, 0)
            XCTAssertNil(defaults.object(forKey: NanashiPresenceEngine.budgetKey))
        }
    }

    func testLeavingDemoDoesNotGrantRealDataConsentOrCallTransport() async {
        await withDefaults { defaults in
            let inputs = Inputs()
            inputs.demo = true
            var calls = 0
            let engine = engine(defaults: defaults, inputs: inputs) {
                calls += 1
                return self.batch()
            }
            await engine.refreshIfNeeded()
            XCTAssertNotNil(engine.remark(for: .day))
            inputs.demo = false
            inputs.configuration = "real-provider:real-snapshot"
            engine.synchronizeConfiguration()
            await engine.refreshIfNeeded()
            await drainActor()

            XCTAssertFalse(engine.enabled)
            XCTAssertNil(engine.generatedAt)
            XCTAssertNil(engine.remark(for: .day))
            XCTAssertNil(defaults.object(forKey: NanashiPresenceEngine.enabledKey))
            XCTAssertNil(defaults.object(forKey: NanashiPresenceEngine.budgetKey))
            XCTAssertEqual(calls, 0)
        }
    }

    func testLeavingDemoRestoresExistingExplicitPreferenceWithoutRetainingFixtures() async {
        await withDefaults { defaults in
            defaults.set(true, forKey: NanashiPresenceEngine.enabledKey)
            let inputs = Inputs()
            inputs.demo = true
            let engine = engine(defaults: defaults, inputs: inputs) { self.batch("Real observation") }
            await engine.refreshIfNeeded()
            XCTAssertNotNil(engine.remark(for: .day))
            inputs.demo = false
            inputs.configuration = "real-provider:real-snapshot"
            engine.synchronizeConfiguration()
            XCTAssertTrue(engine.enabled)
            XCTAssertNil(engine.remark(for: .day))
            await engine.refreshIfNeeded()
            await settled(engine)
            XCTAssertEqual(engine.remark(for: .day)?.text, "Real observation")
            XCTAssertTrue(defaults.bool(forKey: NanashiPresenceEngine.enabledKey))
        }
    }
}
