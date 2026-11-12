import XCTest
@testable import Strand

final class NanashiPresencePolicyTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    func testDecodesObjectAndTrimsCompleteRemark() {
        let response = #"{"remarks":[{"scene":" sleep ","text":"  A longer night than yesterday.  "}]}"#
        XCTAssertEqual(NanashiPresenceRemark.decode(response), [
            NanashiPresenceRemark(scene: .sleep, text: "A longer night than yesterday.")
        ])
        XCTAssertEqual(NanashiPresenceRemark.decode(response).first?.id, "sleep")
    }

    func testAcceptsArrayAndJSONFencesIncludingCRLF() {
        let json = #"[{"scene":"day","text":"Your latest readings are ready."}]"#
        let expected = [NanashiPresenceRemark(scene: .day, text: "Your latest readings are ready.")]
        XCTAssertEqual(NanashiPresenceRemark.decode(json), expected)
        XCTAssertEqual(NanashiPresenceRemark.decode("```json\n" + json + "\n```"), expected)
        XCTAssertEqual(NanashiPresenceRemark.decode("  ```JSON\r\n" + json + "\r\n``` \n"), expected)
        XCTAssertEqual(NanashiPresenceRemark.decode("```\n" + json + "\n```"), expected)
    }

    func testMalformedOrPartialResponsesDoNotSalvageEmbeddedJSON() {
        let json = #"[{"scene":"day","text":"Ready."}]"#
        for response in ["", "null", "{}", #"{"remarks":true}"#, "[", "Here is the answer: " + json,
                         "```json\n" + json, "```swift\n" + json + "\n```",
                         "```json\n" + json + "\n```\nExtra text"] {
            XCTAssertTrue(NanashiPresenceRemark.decode(response).isEmpty, response)
        }
    }

    func testInvalidEntriesDoNotDiscardValidSiblings() {
        let response = #"{"remarks":[null,42,"bad",{"scene":"sleep"},{"scene":"unsupported","text":"No."},{"scene":"activity","text":false},{"scene":"explore","text":"  "},{"scene":"trends","text":"Your recent days are available."}]}"#
        XCTAssertEqual(NanashiPresenceRemark.decode(response), [
            NanashiPresenceRemark(scene: .trends, text: "Your recent days are available.")
        ])
    }

    func testOnlyFirstValidRemarkForEachSceneSurvives() {
        let response = #"[{"scene":"sleep","text":""},{"scene":"sleep","text":"First valid."},{"scene":"sleep","text":"Second."},{"scene":"general","text":"A separate remark."}]"#
        XCTAssertEqual(NanashiPresenceRemark.decode(response), [
            NanashiPresenceRemark(scene: .sleep, text: "First valid."),
            NanashiPresenceRemark(scene: .general, text: "A separate remark.")
        ])
    }

    func testLengthLimitRejectsRatherThanTruncates() throws {
        let exact = String(repeating: "é", count: 320)
        let tooLong = exact + "!"
        let json = try encoded([
            ["scene": "sleep", "text": tooLong],
            ["scene": "day", "text": exact]
        ])
        XCTAssertEqual(NanashiPresenceRemark.decode(json), [NanashiPresenceRemark(scene: .day, text: exact)])
    }

    func testRejectsEmbeddedControlCharacters() throws {
        let entries = ["line\nbreak", "a\tb", "a\u{0000}b", "a\u{007F}b", "a\u{0085}b"].map {
            ["scene": "sleep", "text": $0]
        }
        XCTAssertTrue(NanashiPresenceRemark.decode(try encoded(entries)).isEmpty)
    }

    func testAtMostSixWhitelistedScenesAreReturned() throws {
        let entries = NanashiPresenceScene.allCases.flatMap { scene in
            [["scene": scene.rawValue, "text": "First " + scene.rawValue],
             ["scene": scene.rawValue, "text": "Duplicate " + scene.rawValue]]
        }
        let remarks = NanashiPresenceRemark.decode(try encoded(entries))
        XCTAssertEqual(remarks.count, 6)
        XCTAssertEqual(remarks.map(\.scene), NanashiPresenceScene.allCases)
        XCTAssertTrue(remarks.allSatisfy { $0.text.hasPrefix("First ") })
    }

    func testDefaultBudgetAndExactCooldownBoundary() {
        var budget = NanashiPresenceBudget()
        XCTAssertTrue(budget.canRequest(now: instant, dayKey: "2026-10-27"))
        budget.recordAttempt(now: instant, dayKey: "2026-10-27")
        XCTAssertEqual(budget.attemptCount, 1)
        XCTAssertFalse(budget.canRequest(now: instant.addingTimeInterval(1_799), dayKey: "2026-10-27"))
        XCTAssertTrue(budget.canRequest(now: instant.addingTimeInterval(1_800), dayKey: "2026-10-27"))
    }

    func testFourAttemptsIncludingFailuresExhaustDailyAllowance() {
        var budget = NanashiPresenceBudget()
        for index in 0..<4 {
            let now = instant.addingTimeInterval(Double(index) * 1_800)
            XCTAssertTrue(budget.canRequest(now: now, dayKey: "2026-10-27"))
            budget.recordAttempt(now: now, dayKey: "2026-10-27")
            budget.recordFailure(now: now)
        }
        XCTAssertEqual(budget.attemptCount, 4, "Failure must not count a recorded request twice.")
        XCTAssertFalse(budget.canRequest(now: instant.addingTimeInterval(20_000), dayKey: "2026-10-27"))
    }

    func testDayRolloverCannotBypassCooldownAndResetsOnlyCount() {
        var budget = NanashiPresenceBudget(dayKey: "2026-10-27", attemptCount: 4, lastAttempt: instant)
        XCTAssertFalse(budget.canRequest(now: instant.addingTimeInterval(600), dayKey: "2026-10-28"))
        let next = instant.addingTimeInterval(1_800)
        XCTAssertTrue(budget.canRequest(now: next, dayKey: "2026-10-28"))
        budget.recordAttempt(now: next, dayKey: "2026-10-28")
        XCTAssertEqual(budget.dayKey, "2026-10-28")
        XCTAssertEqual(budget.attemptCount, 1)
        XCTAssertEqual(budget.lastAttempt, next)
    }

    func testFailureBackoffStartsWhenLateRequestActuallyFails() {
        var budget = NanashiPresenceBudget()
        budget.recordAttempt(now: instant, dayKey: "2026-10-27")
        let failedAt = instant.addingTimeInterval(1_900)
        budget.recordFailure(now: failedAt)
        XCTAssertFalse(budget.canRequest(now: failedAt.addingTimeInterval(899), dayKey: "2026-10-27"))
        XCTAssertTrue(budget.canRequest(now: failedAt.addingTimeInterval(900), dayKey: "2026-10-27"))
        XCTAssertEqual(budget.attemptCount, 1)
    }

    func testDayRolloverCannotBypassFailureBackoff() {
        var budget = NanashiPresenceBudget(dayKey: "2026-10-27", attemptCount: 2,
                                           lastAttempt: instant.addingTimeInterval(-3_600))
        budget.recordFailure(now: instant)
        XCTAssertFalse(budget.canRequest(now: instant.addingTimeInterval(899), dayKey: "2026-10-28"))
        XCTAssertTrue(budget.canRequest(now: instant.addingTimeInterval(900), dayKey: "2026-10-28"))
    }

    func testClockRewindDoesNotResetCountOrMoveAttemptBackwards() {
        var budget = NanashiPresenceBudget(dayKey: "2026-10-27", attemptCount: 2, lastAttempt: instant)
        let earlier = instant.addingTimeInterval(-3_600)
        XCTAssertFalse(budget.canRequest(now: earlier, dayKey: "2026-10-26"))
        XCTAssertFalse(budget.canRequest(now: earlier, dayKey: "2026-10-28"))
        budget.recordAttempt(now: earlier, dayKey: "2026-10-28")
        XCTAssertEqual(budget.dayKey, "2026-10-27")
        XCTAssertEqual(budget.attemptCount, 3)
        XCTAssertEqual(budget.lastAttempt, instant)
    }

    func testOlderDayKeyDoesNotReplenishAllowance() {
        let budget = NanashiPresenceBudget(dayKey: "2026-10-28", attemptCount: 4, lastAttempt: instant)
        XCTAssertFalse(budget.canRequest(now: instant.addingTimeInterval(3_600), dayKey: "2026-10-27"))
    }

    func testClockRewindCannotShortenExistingFailureBlock() {
        var budget = NanashiPresenceBudget(lastAttempt: instant)
        budget.recordFailure(now: instant)
        budget.recordFailure(now: instant.addingTimeInterval(-3_600))
        XCTAssertEqual(budget.blockedUntil, instant.addingTimeInterval(900))
        XCTAssertFalse(budget.canRequest(now: instant.addingTimeInterval(-1), dayKey: "2026-10-27"))
    }

    func testBudgetRoundTripRetainsRequestGates() throws {
        var budget = NanashiPresenceBudget()
        budget.recordAttempt(now: instant, dayKey: "2026-10-27")
        budget.recordFailure(now: instant)
        let restored = try JSONDecoder().decode(NanashiPresenceBudget.self, from: JSONEncoder().encode(budget))
        XCTAssertEqual(restored, budget)
        XCTAssertFalse(restored.canRequest(now: instant.addingTimeInterval(1_799), dayKey: "2026-10-27"))
    }

    func testInvalidClockAndConfigurationFailClosed() {
        XCTAssertFalse(NanashiPresenceBudget().canRequest(now: Date(timeIntervalSince1970: .nan), dayKey: "2026-10-27"))
        XCTAssertFalse(NanashiPresenceBudget().canRequest(now: instant, dayKey: ""))
        XCTAssertFalse(NanashiPresenceBudget(maxAttemptsPerDay: 0).canRequest(now: instant, dayKey: "2026-10-27"))
        XCTAssertFalse(NanashiPresenceBudget(minInterval: -.infinity).canRequest(now: instant, dayKey: "2026-10-27"))
    }

    func testAttemptCounterSaturatesWithoutOverflow() {
        var budget = NanashiPresenceBudget(dayKey: "2026-10-27", attemptCount: Int.max, lastAttempt: instant)
        budget.recordAttempt(now: instant.addingTimeInterval(1_800), dayKey: "2026-10-27")
        XCTAssertEqual(budget.attemptCount, Int.max)
        XCTAssertFalse(budget.canRequest(now: instant.addingTimeInterval(3_600), dayKey: "2026-10-27"))
    }

    private func encoded(_ entries: [[String: String]]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: entries), as: UTF8.self)
    }
}
