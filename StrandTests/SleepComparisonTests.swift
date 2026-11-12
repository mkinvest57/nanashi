import XCTest
import WhoopStore
@testable import Strand

final class SleepComparisonTests: XCTestCase {
    func testUnsavedLayoutLeadsWithChronologyAndKeepsHiddenStagesHidden() {
        let visible = SleepHistoryPresentation.visibleSections(orderRaw: "", hiddenRaw: "")
        XCTAssertEqual(visible.first, .stages)
        XCTAssertEqual(visible.last, .sleepMarks)
        let hidden = SleepHistoryPresentation.visibleSections(orderRaw: "", hiddenRaw: "stages")
        XCTAssertFalse(hidden.contains(.stages))
    }

    func testExplicitLayoutOrderRemainsAuthoritative() {
        let saved = "sleepMarks,nightDetail,stages,bodyClock,sleepDebt,stagesVsTypical,asleepDuration"
        XCTAssertEqual(SleepHistoryPresentation.visibleSections(orderRaw: saved, hiddenRaw: "bodyClock"),
                       SleepLayoutPrefs.visibleOrder(orderRaw: saved, hiddenRaw: "bodyClock"))
    }

    func testCustomizerAndItsSavedDraftKeepTheDisplayedOrder() {
        let draft = SleepHistoryPresentation.layoutDraft(orderRaw: "", hiddenRaw: "bodyClock")
        let displayed = SleepHistoryPresentation.visibleSections(orderRaw: "", hiddenRaw: "bodyClock")
        XCTAssertEqual(draft.visible, displayed)
        let savedOrder = SleepLayoutPrefs.encode(draft.visible + draft.hidden)
        let savedHidden = SleepLayoutPrefs.encodeHidden(draft.hidden)
        XCTAssertEqual(SleepHistoryPresentation.visibleSections(orderRaw: savedOrder, hiddenRaw: savedHidden), displayed)
        XCTAssertEqual(SleepHistoryPresentation.layoutDraft(orderRaw: "", hiddenRaw: "").visible.first, .stages)
    }

    func testSyntheticGapsCannotCreateARecordedTimeline() throws {
        let start = timestamp("2025-06-01", hour: 0)
        let blocks = (0..<3).map { index in
            CachedSleepSession(startTs: start + index * 140 * 60,
                               endTs: start + (index * 140 + 120) * 60,
                               efficiency: nil, restingHr: nil, avgHrv: nil,
                               stagesJSON: "{\"light\":120,\"deep\":0,\"rem\":0,\"awake\":0}")
        }
        let night = try XCTUnwrap(SleepModel.mergeDay(blocks, habitualMidsleepSec: nil, motionByStart: [:]))
        XCTAssertEqual(night.stages.asleep, 360)
        XCTAssertNil(night.realSegments, "Two inferred awake seams are not two recorded sleep segments")
        let model = try XCTUnwrap(SleepModel.build(inputs(blocks)))
        XCTAssertFalse(model.isPersistedHypnogram)
    }

    func testTimestampedSleepSegmentsStillProvideARecordedTimeline() throws {
        let start = timestamp("2025-06-01", hour: 0)
        let json = "[{\"start\":\(start),\"end\":\(start + 3600),\"stage\":\"light\"},{\"start\":\(start + 3600),\"end\":\(start + 7200),\"stage\":\"deep\"}]"
        let block = CachedSleepSession(startTs: start, endTs: start + 7200,
                                       efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: json)
        let night = try XCTUnwrap(SleepModel.mergeDay([block], habitualMidsleepSec: nil, motionByStart: [:]))
        XCTAssertEqual(night.realSegments?.count, 2)
        XCTAssertEqual(night.stages.asleep, 120)
    }

    private func timestamp(_ day: String, hour: Int) -> Int {
        let parts = day.split(separator: "-").map { Int($0)! }
        return Int(Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1],
                                                              day: parts[2], hour: hour))!.timeIntervalSince1970)
    }

    private func session(_ wakeDay: String, staged: Bool = true, hrv: Double? = nil) -> CachedSleepSession {
        let wake = timestamp(wakeDay, hour: 7)
        return CachedSleepSession(startTs: wake - 8 * 3_600, endTs: wake, efficiency: 0.9,
                                  restingHr: nil, avgHrv: hrv,
                                  stagesJSON: staged ? "{\"awake\":30,\"light\":270,\"deep\":90,\"rem\":90}" : nil)
    }

    private func daily(_ day: String, hrv: Double? = nil, resp: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 450, efficiency: 0.9375, deepMin: 90, remMin: 90,
                    lightMin: 270, disturbances: nil, restingHr: 52, avgHrv: hrv,
                    recovery: nil, strain: nil, exerciseCount: nil, spo2Pct: nil,
                    skinTempDevC: nil, respRateBpm: resp)
    }

    private func inputs(_ sessions: [CachedSleepSession], days: [DailyMetric] = [],
                        imported: [String: ImportedSleepFigures] = [:]) -> SleepModelInputs {
        SleepModelInputs(days: days, sleeps: sessions, allSessions: sessions, importedSleep: imported,
                         habitualMidsleepSec: nil, motionByStart: [:])
    }

    func testHistoricalSelectionUsesItsOwnNightAndMetricClock() throws {
        let old = session("2025-06-01"), latest = session("2025-06-02")
        let source = inputs([old, latest], days: [daily("2025-06-01", resp: 14), daily("2025-06-02", resp: 18)],
                            imported: ["2025-06-01": .init(performancePct: 64, consistencyPct: nil, needMin: nil, debtMin: nil),
                                       "2025-06-02": .init(performancePct: 93, consistencyPct: nil, needMin: nil, debtMin: nil)])
        let groups = SleepModel.navDays(navSessions: source.allSessions)
        var selected = SleepNightSelection()
        selected.select(1, in: SleepHistoryPresentation.identities(groups))
        let model = try XCTUnwrap(SleepHistoryPresentation.model(inputs: source, selection: selected))
        XCTAssertEqual(model.night.session.endTs, old.endTs)
        XCTAssertEqual(model.performance.latest, 64)
        XCTAssertEqual(model.respiratory.latest, 14)
        XCTAssertNil(model.respiratory.latestDay, "A historical measurement is current for the displayed day")
        XCTAssertEqual(model.trendPoints.count, 1)
    }

    func testHistoricalUnstagedNightDoesNotBorrowNewestNight() throws {
        let old = session("2025-06-01", staged: false), latest = session("2025-06-02")
        let source = inputs([old, latest])
        var selection = SleepNightSelection()
        selection.select(1, in: SleepHistoryPresentation.identities(SleepModel.navDays(navSessions: source.allSessions)))
        let model = try XCTUnwrap(SleepHistoryPresentation.model(inputs: source, selection: selection))
        XCTAssertTrue(model.isStubNight)
        XCTAssertEqual(model.night.session.endTs, old.endTs)
        XCTAssertEqual(model.night.editTarget?.startTs, old.startTs)
    }

    func testComparisonNeverCarriesVitalsFromAnotherDay() throws {
        let old = session("2025-06-01"), latest = session("2025-06-02")
        let source = inputs([old, latest], days: [daily("2025-06-02", hrv: 80)])
        let snapshot = try XCTUnwrap(SleepComparisonSnapshot.make(blocks: [old], inputs: source))
        XCTAssertNil(snapshot.hrv)
        XCTAssertNil(snapshot.restingHR)
        XCTAssertNil(snapshot.rest)
        XCTAssertEqual(snapshot.asleepMinutes, 450)
    }

    func testComparisonUsesExactImportedRestAndDailyVitals() throws {
        let night = session("2025-06-01", hrv: 999)
        let source = inputs([night], days: [daily("2025-06-01", hrv: 61)],
                            imported: ["2025-06-01": .init(performancePct: 84, consistencyPct: nil, needMin: nil, debtMin: nil)])
        let snapshot = try XCTUnwrap(SleepComparisonSnapshot.make(blocks: [night], inputs: source))
        XCTAssertEqual(snapshot.rest, 84)
        XCTAssertEqual(snapshot.hrv, 61)
        XCTAssertEqual(snapshot.restingHR, 52)
    }

    func testComparisonReusesCanonicalMainNightAndExcludesNap() throws {
        let night = session("2025-06-01")
        let nap = CachedSleepSession(startTs: timestamp("2025-06-01", hour: 15),
                                    endTs: timestamp("2025-06-01", hour: 16), efficiency: nil,
                                    restingHr: nil, avgHrv: nil,
                                    stagesJSON: "{\"light\":60,\"awake\":0,\"deep\":0,\"rem\":0}")
        let source = inputs([night, nap])
        let snapshot = try XCTUnwrap(SleepComparisonSnapshot.make(blocks: [night, nap], inputs: source))
        let canonical = try XCTUnwrap(SleepModel.mergeDay([night, nap], habitualMidsleepSec: nil, motionByStart: [:]))
        XCTAssertEqual(snapshot.asleepMinutes, canonical.stages.asleep)
        XCTAssertEqual(snapshot.asleepMinutes, 450)
        XCTAssertEqual(snapshot.wakeTs, night.endTs)
    }

    func testMissingStagesDoNotBecomeZeroDuration() throws {
        let night = session("2025-06-01", staged: false)
        let snapshot = try XCTUnwrap(SleepComparisonSnapshot.make(blocks: [night], inputs: inputs([night])))
        XCTAssertNil(snapshot.asleepMinutes)
        XCTAssertNil(snapshot.deepMinutes)
        XCTAssertNil(SleepComparisonSnapshot.difference(snapshot.asleepMinutes, 400))
        XCTAssertEqual(snapshot.wakeTs, night.endTs)
    }

    func testDifferenceIsSignedAndDoesNotInventMissingOrNonfiniteValues() {
        XCTAssertEqual(SleepComparisonSnapshot.difference(420, 480), -60)
        XCTAssertEqual(SleepComparisonSnapshot.difference(480, 480), 0)
        XCTAssertNil(SleepComparisonSnapshot.difference(.nan, 480))
        XCTAssertNil(SleepComparisonSnapshot.difference(480, .infinity))
        XCTAssertNil(SleepComparisonSnapshot.difference(nil, 480))
    }
}
