import SwiftUI
import StrandDesign
import WhoopStore

// Native adaptation of 21st.dev Stats Card (7841): compact header, leading statistic and named
// proportional bars; Preferences Card (30553) supplies the separated FieldRow register. Sources are
// preserved in .21st/cache. Hover lift/count-up are omitted so comparisons remain still and readable.
struct SleepComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let inputs: SleepModelInputs
    let revision: HistoricalSeriesRevision
    let loadedGeneration: Int?
    @State private var primary: SleepNightSelection
    @State private var secondary: SleepNightSelection
    @State private var first: SleepComparisonSnapshot?
    @State private var second: SleepComparisonSnapshot?

    init(inputs: SleepModelInputs, revision: HistoricalSeriesRevision, loadedGeneration: Int?,
         initialSelection: SleepNightSelection) {
        self.inputs = inputs
        self.revision = revision
        self.loadedGeneration = loadedGeneration
        let groups = SleepModel.navDays(navSessions: inputs.allSessions.isEmpty ? inputs.sleeps : inputs.allSessions)
        let identities = SleepHistoryPresentation.identities(groups)
        var first = initialSelection
        first.reconcile(with: identities)
        var second = SleepNightSelection()
        let index = first.index(in: identities) ?? 0
        second.select(index + 1 < identities.count ? index + 1 : max(0, index - 1), in: identities)
        _primary = State(initialValue: first)
        _secondary = State(initialValue: second)
    }

    private var groups: [[CachedSleepSession]] {
        SleepModel.navDays(navSessions: inputs.allSessions.isEmpty ? inputs.sleeps : inputs.allSessions)
    }

    private var identities: [SleepNightIdentity] { SleepHistoryPresentation.identities(groups) }

    private struct SnapshotRevision: Equatable {
        let history: HistoricalSeriesRevision
        let loadedGeneration: Int?
        let first: SleepNightSelection
        let second: SleepNightSelection
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: NoopMetrics.space3))
                        : AnyLayout(HStackLayout(spacing: NoopMetrics.space3))
                    layout {
                        nightPicker("Night A", selection: $primary, excluding: secondary.selectedWakeDay)
                        nightPicker("Night B", selection: $secondary, excluding: primary.selectedWakeDay)
                    }

                    if let first, let second {
                        durationComparison(first, second)
                        comparisonRegister(first, second)
                        if first.hasSparseStaging || second.hasSparseStaging {
                            Label("Some stages may be incomplete. Compare these durations with care.", systemImage: "info.circle")
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        Text("Differences describe these two nights. More is not always better; they do not explain a cause.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                    } else {
                        Text("Two recorded nights are needed to compare.")
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                .padding(NoopMetrics.screenHPadding)
                .frame(maxWidth: NoopMetrics.pageMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .background(StrandPalette.surfaceBase)
            .navigationTitle("Compare nights")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: SnapshotRevision(history: revision, loadedGeneration: loadedGeneration,
                                       first: primary, second: secondary)) {
                refreshSnapshots()
            }
        }
        #if os(macOS)
        .frame(minWidth: NoopMetrics.detailSheetMinWidth, minHeight: NoopMetrics.detailSheetMinHeight)
        #endif
    }

    private func refreshSnapshots() {
        let groups = groups
        let ids = SleepHistoryPresentation.identities(groups)
        primary.reconcile(with: ids)
        secondary.reconcile(with: ids)
        if primary.index(in: ids) == secondary.index(in: ids), ids.count > 1 {
            let index = primary.index(in: ids) ?? 0
            secondary.select(index + 1 < ids.count ? index + 1 : index - 1, in: ids)
        }
        first = primary.index(in: ids).flatMap { SleepComparisonSnapshot.make(blocks: groups[$0], inputs: inputs) }
        second = secondary.index(in: ids).flatMap { SleepComparisonSnapshot.make(blocks: groups[$0], inputs: inputs) }
    }

    private func nightPicker(_ title: LocalizedStringKey, selection: Binding<SleepNightSelection>, excluding day: String?) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(title).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Picker(title, selection: Binding(
                get: { selection.wrappedValue.selectedWakeDay ?? "" },
                set: { day in
                    let ids = identities
                    if let index = ids.firstIndex(where: { $0.wakeDay == day }) {
                        selection.wrappedValue.select(index, in: ids)
                    }
                })) {
                ForEach(identities.filter { $0.wakeDay != day }, id: \.wakeDay) { identity in
                    Text(dateLabel(identity.wakeDay)).tag(identity.wakeDay)
                }
            }
            .pickerStyle(.menu)
            .font(StrandFont.headline)
            .tint(StrandPalette.accent)
            .frame(maxWidth: .infinity, minHeight: NoopMetrics.controlHeight, alignment: .leading)
        }
        .padding(NoopMetrics.space3)
        .noopPanel()
    }

    private func durationComparison(_ first: SleepComparisonSnapshot, _ second: SleepComparisonSnapshot) -> some View {
        NoopCard(tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                Text("Time asleep").strandOverline()
                Text(first.asleepMinutes.map(durationText) ?? "—")
                    .font(StrandFont.title1.monospacedDigit())
                    .foregroundStyle(StrandPalette.textPrimary)
                if let delta = SleepComparisonSnapshot.difference(first.asleepMinutes, second.asleepMinutes) {
                    Text(delta == 0
                         ? String(localized: "The same recorded duration")
                         : String(localized: "Compared with night B: \(delta > 0 ? "+" : "−")\(durationText(abs(delta)))"))
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                } else {
                    Text("A duration is unavailable; no difference is calculated.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                }
                let maximum = max(max(first.asleepMinutes ?? 0, second.asleepMinutes ?? 0), 1)
                HStack(alignment: .bottom, spacing: NoopMetrics.space6) {
                    durationBar(first, maximum: maximum, emphasis: true)
                    durationBar(second, maximum: maximum, emphasis: false)
                }
            }
        }
    }

    private func durationBar(_ snapshot: SleepComparisonSnapshot, maximum: Double, emphasis: Bool) -> some View {
        VStack(spacing: NoopMetrics.space2) {
            Text(snapshot.asleepMinutes.map(durationText) ?? "—")
                .font(StrandFont.bodyNumber).foregroundStyle(StrandPalette.textPrimary)
            GeometryReader { geometry in
                VStack {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: NoopMetrics.space2, style: .continuous)
                        .fill(emphasis ? StrandPalette.accent : StrandPalette.accent.opacity(0.28))
                        .frame(height: geometry.size.height * CGFloat((snapshot.asleepMinutes ?? 0) / maximum))
                }
            }
            .frame(height: NoopMetrics.heroPrimaryGaugeDiameter)
            Text(dateLabel(snapshot.identity.wakeDay))
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(dateLabel(snapshot.identity.wakeDay)), \(snapshot.asleepMinutes.map(durationText) ?? String(localized: "Not available"))")
    }

    private func comparisonRegister(_ first: SleepComparisonSnapshot, _ second: SleepComparisonSnapshot) -> some View {
        NoopCard {
            VStack(spacing: NoopMetrics.space4) {
                comparisonRow("Night", dateLabel(first.identity.wakeDay), dateLabel(second.identity.wakeDay))
                comparisonRow("Asleep", Night.clockString(first.onsetTs), Night.clockString(second.onsetTs))
                comparisonRow("Woke", Night.clockString(first.wakeTs), Night.clockString(second.wakeTs))
                comparisonRow("Deep", first.deepMinutes.map(durationText) ?? "—", second.deepMinutes.map(durationText) ?? "—")
                comparisonRow("REM", first.remMinutes.map(durationText) ?? "—", second.remMinutes.map(durationText) ?? "—")
                comparisonRow("Rest", number(first.rest, unit: "%"), number(second.rest, unit: "%"))
                comparisonRow("HRV", number(first.hrv, unit: "ms"), number(second.hrv, unit: "ms"))
                comparisonRow("Resting HR", number(first.restingHR, unit: "bpm"), number(second.restingHR, unit: "bpm"), last: true)
            }
        }
    }

    private func comparisonRow(_ title: LocalizedStringKey, _ first: String, _ second: String, last: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text(title).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space4) {
                Text(first).frame(maxWidth: .infinity, alignment: .leading)
                Text(second).frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(StrandFont.bodyNumber)
            .foregroundStyle(StrandPalette.textPrimary)
            if !last { Divider().overlay(StrandPalette.hairline) }
        }
        .accessibilityElement(children: .combine)
    }

    private func dateLabel(_ day: String) -> String {
        "\(SleepModel.shortDayLabel(day)) \(day.prefix(4))"
    }

    /// Matches SleepView's minute display, retaining the catalog's localized hour/minute units.
    private func durationText(_ minutes: Double) -> String {
        let rounded = minutes.rounded()
        guard rounded.isFinite, rounded >= 0, rounded < Double(Int.max) else { return "—" }
        let value = Int(rounded)
        if value < 60 { return String(localized: "\(value)m") }
        return String(localized: "\(value / 60)h \(value % 60)m")
    }

    private func number(_ value: Double?, unit: String) -> String {
        guard let value, value.isFinite,
              value > Double(Int.min), value < Double(Int.max) else { return "—" }
        return "\(Int(value.rounded())) \(unit)"
    }
}
