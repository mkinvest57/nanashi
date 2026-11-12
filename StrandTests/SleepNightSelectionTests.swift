import XCTest
@testable import Strand

final class SleepNightSelectionTests: XCTestCase {
    private let nights = [
        SleepNightIdentity(wakeDay: "2026-10-25", starts: [250, 251]),
        SleepNightIdentity(wakeDay: "2026-10-24", starts: [240]),
        SleepNightIdentity(wakeDay: "2026-10-22", starts: [220])
    ]

    func testNewNightDoesNotMoveTheNightBeingRead() {
        var selection = SleepNightSelection()
        selection.select(1, in: nights)
        let refreshed = [SleepNightIdentity(wakeDay: "2026-10-26", starts: [260])] + nights
        selection.reconcile(with: refreshed)
        XCTAssertEqual(selection.index(in: refreshed), 2)
        XCTAssertEqual(selection.selectedStart, 240)
    }

    func testCorrectedWakeDayKeepsTheStoredStartIdentity() {
        var selection = SleepNightSelection()
        selection.select(1, in: nights)
        let corrected = [nights[0], SleepNightIdentity(wakeDay: "2026-10-23", starts: [240]), nights[2]]
        selection.reconcile(with: corrected)
        XCTAssertEqual(selection.selectedWakeDay, "2026-10-23")
    }

    func testReplacementImportFallsBackToSameWakeDay() {
        var selection = SleepNightSelection()
        selection.select(1, in: nights)
        let replacement = [nights[0], SleepNightIdentity(wakeDay: "2026-10-24", starts: [241, 242]), nights[2]]
        selection.reconcile(with: replacement)
        XCTAssertEqual(selection.selectedWakeDay, "2026-10-24")
        XCTAssertEqual(selection.selectedStart, 241)
    }

    func testEmptyReloadKeepsSelectionAndDeletionChoosesEarlierNeighbour() {
        var selection = SleepNightSelection()
        selection.select(1, in: nights)
        selection.reconcile(with: [])
        XCTAssertEqual(selection.selectedStart, 240)
        selection.reconcile(with: [nights[0], nights[2]])
        XCTAssertEqual(selection.selectedWakeDay, "2026-10-22")
    }

    func testInPlaceCorrectionAndDeviceSwitchInvalidateHistoryLoads() {
        let first = HistoricalSeriesRevision(deviceID: "a", generation: 4)
        XCTAssertNotEqual(first, HistoricalSeriesRevision(deviceID: "a", generation: 5))
        XCTAssertNotEqual(first, HistoricalSeriesRevision(deviceID: "b", generation: 4))
        XCTAssertNotEqual(SleepNightHRRevision(history: first, startTs: 100, endTs: 200),
                          SleepNightHRRevision(history: first, startTs: 100, endTs: 250))
    }
}
