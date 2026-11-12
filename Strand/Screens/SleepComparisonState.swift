import Foundation
import StrandAnalytics
import WhoopStore

/// Presentation-only projections of the existing sleep model. No stored values or scoring change.
enum SleepHistoryPresentation {
    /// The unsaved phone composition leads with the recorded night. Explicit saved order and hidden
    /// cards remain authoritative; this does not rewrite the cross-platform preference registry.
    static func sectionOrder(orderRaw: String) -> [SleepSection] {
        let order = SleepLayoutPrefs.decodeOrder(orderRaw)
        guard orderRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return order }
        return [.stages] + order.filter { $0 != .stages && $0 != .sleepMarks } + [.sleepMarks]
    }

    static func visibleSections(orderRaw: String, hiddenRaw: String) -> [SleepSection] {
        let hidden = Set(SleepLayoutPrefs.decodeHidden(hiddenRaw))
        return sectionOrder(orderRaw: orderRaw).filter { !hidden.contains($0) }
    }

    static func layoutDraft(orderRaw: String, hiddenRaw: String) -> EditableLayoutDraft<SleepSection> {
        let order = sectionOrder(orderRaw: orderRaw)
        let hidden = Set(SleepLayoutPrefs.decodeHidden(hiddenRaw))
        return EditableLayoutDraft(visible: order.filter { !hidden.contains($0) },
                                   hidden: order.filter { hidden.contains($0) })
    }

    static func identities(_ groups: [[CachedSleepSession]]) -> [SleepNightIdentity] {
        groups.compactMap { blocks in
            guard let last = blocks.last else { return nil }
            return SleepNightIdentity(wakeDay: wakeDay(last), starts: blocks.map(\.startTs))
        }
    }

    static func wakeDay(_ session: CachedSleepSession) -> String {
        Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(session.endTs)))
    }

    /// Truncating inputs at the selected day makes every detail describe that same night. The
    /// existing builder remains the sole authority for stage merging, Rest and historical context.
    static func inputs(through day: String, from inputs: SleepModelInputs) -> SleepModelInputs {
        SleepModelInputs(days: inputs.days.filter { $0.day <= day },
                         sleeps: inputs.sleeps.filter { wakeDay($0) <= day },
                         allSessions: inputs.allSessions.filter { wakeDay($0) <= day },
                         importedSleep: inputs.importedSleep.filter { $0.key <= day },
                         habitualMidsleepSec: inputs.habitualMidsleepSec,
                         motionByStart: inputs.motionByStart)
    }

    static func model(inputs: SleepModelInputs, selection: SleepNightSelection) -> SleepModel? {
        let groups = SleepModel.navDays(navSessions: inputs.allSessions.isEmpty ? inputs.sleeps : inputs.allSessions)
        let identities = identities(groups)
        guard let index = selection.index(in: identities) else { return nil }
        let day = identities[index].wakeDay
        // Noon on the local wake day is after the 04:00 logical-day boundary, including DST days.
        let parts = day.split(separator: "-").compactMap { Int($0) }
        let reference = parts.count == 3
            ? Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
            : nil
        return SleepModel.build(Self.inputs(through: day, from: inputs), referenceDate: reference ?? Date())
    }
}

/// Exact-day values for comparing two recorded nights. Missing values remain absent; the comparison
/// never carries a newer day's vital backwards or substitutes zero for unavailable staging.
struct SleepComparisonSnapshot {
    let identity: SleepNightIdentity
    let onsetTs: Int
    let wakeTs: Int
    let asleepMinutes: Double?
    let deepMinutes: Double?
    let remMinutes: Double?
    let rest: Double?
    let hrv: Double?
    let restingHR: Double?
    let hasSparseStaging: Bool

    static func make(blocks: [CachedSleepSession], inputs: SleepModelInputs) -> Self? {
        guard let identity = SleepHistoryPresentation.identities([blocks]).first else { return nil }
        let night = SleepModel.mergeDay(blocks, habitualMidsleepSec: inputs.habitualMidsleepSec,
                                       motionByStart: inputs.motionByStart)
        guard let session = night?.session ?? SleepView.stubDaySession(blocks,
            habitualMidsleepSec: inputs.habitualMidsleepSec) else { return nil }
        let daily = inputs.days.last { $0.day == identity.wakeDay }
        let mainGroup = SleepView.mainNightGroup(blocks, habitualMidsleepSec: inputs.habitualMidsleepSec)
        let sparse = SleepView.stageSparseNoteApplies(stagingSparse: mainGroup.contains { $0.stagingSparse == true },
                                                      asleepMin: night?.stages.asleep ?? 0)
        let partial = HypnogramCoverage.groupFraction(mainGroup).map { $0 < HypnogramCoverage.minCoverage } ?? false
        let rest = inputs.importedSleep[identity.wakeDay]?.performancePct
            ?? daily.flatMap { AnalyticsEngine.Rest.composite(daily: $0) }
        return Self(identity: identity, onsetTs: session.effectiveStartTs, wakeTs: session.endTs,
                    asleepMinutes: finite(night?.stages.asleep), deepMinutes: finite(night?.stages.deep),
                    remMinutes: finite(night?.stages.rem), rest: finite(rest), hrv: finite(daily?.avgHrv),
                    restingHR: daily?.restingHr.map(Double.init),
                    hasSparseStaging: sparse || partial)
    }

    static func difference(_ first: Double?, _ second: Double?) -> Double? {
        guard let first = finite(first), let second = finite(second) else { return nil }
        return first - second
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }
}
