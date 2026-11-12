import XCTest
@testable import Strand

final class PresentationLoadStateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    func testCompletedSnapshotSkipsQuickRevisitButExpiresForRawDataFreshness() throws {
        var state = PresentationLoadState<String>()
        let ticket = try XCTUnwrap(state.begin(key: "day-a", now: start))
        XCTAssertTrue(state.complete(ticket, key: "day-a", cancelled: false, now: start))
        state.finish(ticket)
        XCTAssertNil(state.begin(key: "day-a", now: start.addingTimeInterval(29)))
        XCTAssertNotNil(state.begin(key: "day-a", now: start.addingTimeInterval(30)))
    }

    func testExplicitRefreshSupersedesAnIdenticalCompletedSnapshot() throws {
        var state = PresentationLoadState<Int>()
        let ticket = try XCTUnwrap(state.begin(key: 4, now: start))
        XCTAssertTrue(state.complete(ticket, key: 4, cancelled: false, now: start))
        XCTAssertNotNil(state.begin(key: 4, now: start, force: true))
        XCTAssertFalse(state.isCurrent(ticket, key: 4, cancelled: false))
    }

    func testCancelledPartialLoadNeverBecomesReusable() throws {
        var state = PresentationLoadState<String>()
        let ticket = try XCTUnwrap(state.begin(key: "a", now: start))
        XCTAssertFalse(state.complete(ticket, key: "a", cancelled: true, now: start))
        state.finish(ticket)
        XCTAssertNotNil(state.begin(key: "a", now: start))
    }

    func testLateCompletionAndDeferCannotFinishNewerRequest() throws {
        var state = PresentationLoadState<String>()
        let old = try XCTUnwrap(state.begin(key: "a", now: start))
        let current = try XCTUnwrap(state.begin(key: "b", now: start))
        XCTAssertFalse(state.complete(old, key: "a", cancelled: false, now: start))
        state.finish(old)
        XCTAssertTrue(state.isCurrent(current, key: "b", cancelled: false))
        XCTAssertFalse(state.isCurrent(current, key: "c", cancelled: false))
        XCTAssertTrue(state.complete(current, key: "b", cancelled: false, now: start))
    }

    func testPartialDifferentDayInvalidatesPreviouslyCompletedDay() throws {
        var state = PresentationLoadState<String>()
        let first = try XCTUnwrap(state.begin(key: "a", now: start))
        XCTAssertTrue(state.complete(first, key: "a", cancelled: false, now: start))
        _ = state.begin(key: "b", now: start)
        XCTAssertNotNil(state.begin(key: "a", now: start))
    }

    func testClockRollbackAndChangedRevisionDoNotReuseSnapshot() throws {
        var state = PresentationLoadState<Int>()
        let ticket = try XCTUnwrap(state.begin(key: 1, now: start))
        XCTAssertTrue(state.complete(ticket, key: 1, cancelled: false, now: start))
        XCTAssertNotNil(state.begin(key: 1, now: start.addingTimeInterval(-1)))
        XCTAssertNotNil(state.begin(key: 2, now: start))
    }
}
