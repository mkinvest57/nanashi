import Foundation

/// Stable presentation identity; stored starts survive time edits and the wake day survives imports.
struct SleepNightIdentity: Equatable {
    let wakeDay: String
    let starts: [Int]
}

/// Session-only selection. A transient empty reload never erases the night being read.
struct SleepNightSelection: Equatable {
    private(set) var selectedStart: Int?
    private(set) var selectedWakeDay: String?

    mutating func select(_ index: Int, in nights: [SleepNightIdentity]) {
        guard nights.indices.contains(index) else { return }
        selectedStart = nights[index].starts.first
        selectedWakeDay = nights[index].wakeDay
    }

    func index(in nights: [SleepNightIdentity]) -> Int? {
        guard !nights.isEmpty else { return nil }
        if let selectedStart,
           let index = nights.firstIndex(where: { $0.starts.contains(selectedStart) }) { return index }
        if let selectedWakeDay {
            if let index = nights.firstIndex(where: { $0.wakeDay == selectedWakeDay }) { return index }
            return nights.firstIndex(where: { $0.wakeDay < selectedWakeDay }) ?? (nights.count - 1)
        }
        return 0
    }

    mutating func reconcile(with nights: [SleepNightIdentity]) {
        guard let index = index(in: nights) else { return }
        select(index, in: nights)
    }
}

/// In-place corrections invalidate history just as a newly banked day does.
struct HistoricalSeriesRevision: Equatable {
    let deviceID: String
    let generation: Int
}

struct SleepNightHRRevision: Equatable {
    let history: HistoricalSeriesRevision
    let startTs: Int
    let endTs: Int
}
