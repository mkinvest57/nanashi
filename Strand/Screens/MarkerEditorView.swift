import SwiftUI
import Foundation
import StrandDesign
import StrandImport
import StrandAnalytics
import WhoopStore

// MARK: - Marker editor (manual entry — MVP)
//
// The "+ add a reading" sheet for the Lab Book (Health Records pillar, spec §"Add / edit
// a marker"). Pick a marker from MarkerCatalog (searchable) OR add a custom marker (free
// name + unit), then: value (numeric, the marker's canonical unit prefilled, a unit
// switcher where sensible e.g. mmol/L↔mg/dL with the conversion shown transparently),
// date/time taken, an optional note, and an OPTIONAL "reference range from my report"
// free-text — NEVER a NOOP-shipped range. Blood pressure is a PAIRED marker (systolic +
// diastolic entered together, stored as two keys) so it reads naturally.
//
// On save it hands the caller `[LabMarkerRow]` drafts (one row, or two for BP) under the
// strap device id with a `lab-book`-projecting write path; the caller persists + refreshes.
// SELF-CONTAINED: no AppModel/Settings edits; the sheet owns all its state.
//
// NON-CLINICAL: this only captures what the user types. The reference field is theirs,
// shown back verbatim — NOOP defines no ranges and asserts no normality.

struct MarkerEditorView: View {
    /// Persist the validated draft row(s). Async so the caller can write + refresh.
    let onSave: (_ drafts: [LabMarkerRow]) async -> Void

    @EnvironmentObject var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Marker selection.
    @State private var selection: MarkerDefinition?
    @State private var customName = ""
    @State private var customUnit = ""
    @State private var addingCustom = false
    @State private var search = ""

    // Reading inputs.
    @State private var valueText = ""
    @State private var diastolicText = ""   // only used for the paired BP marker
    @State private var unit = ""
    @State private var unitChoice = 0       // index into the active unit options (the switcher)
    @State private var takenAt = Date()
    @State private var note = ""
    @State private var referenceText = ""

    @State private var saving = false

    private enum Field: Hashable { case value, diastolic, note, reference, customName, customUnit }
    @FocusState private var focused: Field?
    @FocusState private var searchFocused: Bool

    var body: some View {
        ScreenScaffold(title: "Add a reading",
                       subtitle: "Type in a number from your own report. It stays on \(Platform.deviceNounPhrase).") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                markerSection
                if selection != nil || addingCustom {
                    readingSection
                }
                disclaimerNote
                #if !os(iOS)
                footer
                #endif
            }
        }
        #if os(iOS)
        .presentationDragIndicator(.visible)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar
        }
        #else
        // A FIXED frame (not minWidth/minHeight): a macOS sheet hosting a ScrollView needs a definite
        // height, otherwise the scaffold's height stays ambiguous and every row collapses to the top,
        // rendering the title/fields/catalog on top of each other. Matches the other editor sheets.
        .frame(width: 520, height: 720)
        #endif
        .background(StrandPalette.surfaceBase)
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focused = nil
                    searchFocused = false
                }
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.accentInk)
            }
        }
        #else
        .keyboardDoneToolbar($focused)
        #endif
    }

    // MARK: - Marker picker

    private var markerSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Marker", overline: "what are you logging?")
            NoopCard {
                VStack(alignment: .leading, spacing: 12) {
                    if addingCustom {
                        customMarkerFields
                    } else if let selection {
                        chosenMarkerRow(selection)
                    } else {
                        searchField
                        catalogList
                        Button {
                            addingCustom = true
                            focused = .customName
                        } label: {
                            Label("Add a custom marker", systemImage: "plus")
                        }
                        .buttonStyle(.noopGhost)
                    }
                }
            }
        }
    }

    private var searchField: some View {
        NoopLiquidGlassSearchField(text: $search,
                                   prompt: String(localized: "Search markers (e.g. LDL, ferritin)"),
                                   accessibilityLabel: String(localized: "Search markers"),
                                   isFocused: $searchFocused)
    }

    private var filteredCatalog: [MarkerDefinition] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return MarkerCatalog.builtIn }
        return MarkerCatalog.builtIn.filter {
            $0.displayName.lowercased().contains(q) || $0.key.contains(q)
        }
    }

    private var catalogList: some View {
        // A ScrollView (capped at 280pt) so all ~30 markers are reachable — a bare VStack
        // under .frame(maxHeight: 280) clipped everything past the first handful with no scroll.
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(filteredCatalog.enumerated()), id: \.element.key) { idx, def in
                Button {
                    choose(def)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(def.displayName)
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text(def.category.displayName)
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                        Spacer()
                        Text(def.canonicalUnit)
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(def.displayName), \(def.canonicalUnit)")
                    if idx < filteredCatalog.count - 1 {
                        Divider().overlay(StrandPalette.hairline)
                    }
                }
                if filteredCatalog.isEmpty {
                    Text("No match. Add it as a custom marker below.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        #if os(iOS)
        .scrollBounceBasedOnSizeCompat(axes: .horizontal)
        #endif
        .frame(maxHeight: 280)
    }

    private func chosenMarkerRow(_ def: MarkerDefinition) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(def.displayName).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text(def.category.displayName).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer()
            Button("Change") { reset() }
                .buttonStyle(.plain)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.accentInk)
                .accessibilityLabel("Change marker")
        }
    }

    private var customMarkerFields: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            textBox(String(localized: "Name"), text: $customName, field: .customName,
                    hint: String(localized: "e.g. Magnesium"),
                    accessibility: String(localized: "Custom marker name"))
            textBox(String(localized: "Unit"), text: $customUnit, field: .customUnit,
                    hint: String(localized: "e.g. mmol/L"),
                    accessibility: String(localized: "Custom marker unit"))
            Button("Back to the marker list") { addingCustom = false }
                .buttonStyle(.plain)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.accentInk)
        }
    }

    // MARK: - Reading inputs

    private var readingSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Reading", overline: "your number, date and any note")
            NoopCard {
                VStack(alignment: .leading, spacing: 14) {
                    if isBloodPressure {
                        bloodPressureFields
                    } else {
                        valueField
                    }
                    field(String(localized: "Date taken")) {
                        DatePicker("", selection: $takenAt, in: ...Date(),
                                   displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .accessibilityLabel("Date and time taken")
                    }
                    textBox(String(localized: "Note (optional)"), text: $note, field: .note,
                            hint: String(localized: "e.g. fasting, morning draw"),
                            accessibility: String(localized: "Optional note"))
                    textBox(String(localized: "Reference range from my report (optional)"),
                            text: $referenceText, field: .reference,
                            hint: String(localized: "e.g. 2.0–5.0 (your report's own range)"),
                            accessibility: String(localized: "Reference range from your own report, optional"))
                    Text("NOOP never fills this in. It only shows back exactly what you type from your own report.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var valueField: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            if unitOptions.count > 1 {
                // The transparent unit switcher (e.g. mmol/L ↔ mg/dL).
                SegmentedPillControl(Array(unitOptions.indices), selection: $unitChoice) { unitOptions[$0] }
                    .accessibilityLabel("Unit")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            NoopFloatingField(String(localized: "Value"),
                              isFocused: focused == .value, isFilled: !valueText.isEmpty,
                              hint: String(localized: "e.g. 3.1"), unit: activeUnit,
                              accessibilityLabel: String(localized: "Value") + ", " + activeUnit) {
                TextField("", text: $valueText)
                    .textFieldStyle(.plain)
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .numericKeyboard()
                    .focused($focused, equals: .value)
            }
            if unitOptions.count > 1 {
                Text("Stored as \(MarkerUnits.canonicalUnit(for: markerKey, fallback: unit)). \(conversionNote)")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private var bloodPressureFields: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            HStack(spacing: NoopMetrics.space3) {
                numberBox(String(localized: "Systolic"),
                          placeholder: String(localized: "e.g. 120"), text: $valueText, unit: "mmHg", field: .value,
                          accessibility: String(localized: "Systolic blood pressure in mmHg"))
                numberBox(String(localized: "Diastolic"),
                          placeholder: String(localized: "e.g. 80"), text: $diastolicText, unit: "mmHg", field: .diastolic,
                          accessibility: String(localized: "Diastolic blood pressure in mmHg"))
            }
            Text("Entered together; stored as two markers so each lines up cleanly against your signals.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    private func textBox(_ label: String, text: Binding<String>, field: Field,
                         hint: String, accessibility: String) -> some View {
        NoopFloatingField(label, isFocused: focused == field, isFilled: !text.wrappedValue.isEmpty,
                          hint: hint, accessibilityLabel: accessibility) {
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .focused($focused, equals: field)
        }
        .frame(maxWidth: .infinity)
    }

    private func numberBox(_ label: String, placeholder: String, text: Binding<String>,
                           unit: String, field: Field, accessibility: String) -> some View {
        NoopFloatingField(label, isFocused: focused == field, isFilled: !text.wrappedValue.isEmpty,
                          hint: placeholder, unit: unit, accessibilityLabel: accessibility) {
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(StrandFont.bodyNumber)
                .foregroundStyle(StrandPalette.textPrimary)
                .numericKeyboard()
                .focused($focused, equals: field)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Disclaimer + footer

    private var disclaimerNote: some View {
        Text("Lab Book keeps your own numbers. It doesn't test, read, or judge them, and it's not medical advice. Everything stays on \(Platform.deviceNounPhrase).")
            .font(StrandFont.footnote)
            .foregroundStyle(StrandPalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var stackedFooter: Bool {
        #if os(iOS)
        dynamicTypeSize.isAccessibilitySize
        #else
        false
        #endif
    }

    private var footerLayout: AnyLayout {
        stackedFooter
            ? AnyLayout(VStackLayout(spacing: NoopMetrics.space3))
            : AnyLayout(HStackLayout(spacing: NoopMetrics.space3))
    }

    private var footer: some View {
        footerLayout {
            Button { dismiss() } label: {
                Text("Cancel")
                    .frame(maxWidth: stackedFooter ? .infinity : nil,
                           minHeight: NoopButtonMetrics.minHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(StrandFont.body)
            .foregroundStyle(StrandPalette.textSecondary)
            if !stackedFooter { Spacer() }
            Button("Save") { save() }
                .buttonStyle(.noopPrimary)
                .frame(maxWidth: stackedFooter ? .infinity : 160)
                .disabled(drafts.isEmpty || saving)
                .accessibilityLabel("Save reading")
        }
    }

    #if os(iOS)
    private var actionBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(StrandPalette.hairline)
                .frame(height: NoopMetrics.hairlineWidth)
            footer
                .padding(.horizontal, NoopMetrics.screenHPadding)
                .padding(.vertical, NoopMetrics.space3)
        }
        .background(StrandPalette.surfaceBase)
    }
    #endif

    // MARK: - Selection + units

    private func choose(_ def: MarkerDefinition) {
        selection = def
        unit = def.canonicalUnit
        unitChoice = 0
        focused = .value
    }

    private func reset() {
        selection = nil
        valueText = ""
        diastolicText = ""
        unitChoice = 0
        search = ""
    }

    /// The active marker key (catalog key, or a slug of the custom name).
    private var markerKey: String {
        if let selection { return selection.key }
        return MarkerUnits.slug(customName)
    }

    private var category: LabMarkerCategory {
        if let selection { return selection.category }
        return .other
    }

    private var isBloodPressure: Bool { markerKey == LabBookProjection.bpSystolicKey }

    /// The unit options for the active marker — a switcher list only for markers that have a
    /// well-known dual unit (lipids/glucose: mmol/L↔mg/dL). Everything else has one canonical unit.
    private var unitOptions: [String] {
        if addingCustom { return [customUnit.isEmpty ? "" : customUnit] }
        return MarkerUnits.options(for: markerKey, canonical: unit)
    }

    private var activeUnit: String {
        guard unitOptions.indices.contains(unitChoice) else { return unit }
        return unitOptions[unitChoice]
    }

    private var conversionNote: String {
        guard unitOptions.count > 1, activeUnit != MarkerUnits.canonicalUnit(for: markerKey, fallback: unit),
              let factor = MarkerUnits.factorToCanonical(markerKey: markerKey, from: activeUnit) else {
            return ""
        }
        return String(localized: "× \(MarkerUnits.factorLabel(factor)) on save.")
    }

    // MARK: - Build the draft rows

    /// The validated draft row(s): two for BP, one otherwise. Empty when inputs aren't usable yet.
    private var drafts: [LabMarkerRow] {
        // Custom marker needs a name + unit.
        if addingCustom {
            guard !customName.trimmingCharacters(in: .whitespaces).isEmpty,
                  !customUnit.trimmingCharacters(in: .whitespaces).isEmpty,
                  let v = parsed(valueText) else { return [] }
            return [row(key: markerKey, category: .other, value: v, unit: customUnit)]
        }
        guard selection != nil else { return [] }
        if isBloodPressure {
            guard let sys = parsed(valueText), let dia = parsed(diastolicText) else { return [] }
            return [
                row(key: LabBookProjection.bpSystolicKey, category: .bloodPressure, value: sys, unit: "mmHg"),
                row(key: LabBookProjection.bpDiastolicKey, category: .bloodPressure, value: dia, unit: "mmHg"),
            ]
        }
        guard let raw = parsed(valueText) else { return [] }
        // Convert the entered value to the canonical stored unit if a switcher is in use.
        let canonical = MarkerUnits.canonicalUnit(for: markerKey, fallback: unit)
        let stored = MarkerUnits.toCanonical(markerKey: markerKey, value: raw, from: activeUnit)
        return [row(key: markerKey, category: category, value: stored, unit: canonical)]
    }

    private func row(key: String, category: LabMarkerCategory, value: Double, unit: String) -> LabMarkerRow {
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let trimmedRef = referenceText.trimmingCharacters(in: .whitespaces)
        let epoch = Int(takenAt.timeIntervalSince1970)
        return LabMarkerRow(
            id: "\(key)-\(epoch)-\(UUID().uuidString.prefix(8))",
            deviceId: repo.deviceId,
            markerKey: key,
            category: category.rawValue,
            day: LabBookFormat.dayKey(takenAt),
            takenAt: epoch,
            value: value,
            valueText: nil,
            unit: unit,
            source: "manual",
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            referenceText: trimmedRef.isEmpty ? nil : trimmedRef
        )
    }

    private func parsed(_ s: String) -> Double? {
        DecimalEntryParser.parse(s)
    }

    private func save() {
        let rows = drafts
        guard !rows.isEmpty else { return }
        saving = true
        Task {
            await onSave(rows)
            dismiss()
        }
    }

    // MARK: - Small builders

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).strandOverline()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Unit handling (transparent mmol/L ↔ mg/dL switcher for lipids/glucose)
//
// Only the markers with a well-known dual unit get a switcher; everything else keeps its
// single canonical unit. Conversions are exact and reversible. The stored value is always
// the canonical unit, so the daily projection + correlation stay consistent regardless of
// what the user typed in.

enum MarkerUnits {
    /// Markers whose mg/dL → mmol/L factor we know (molar-mass derived, standard clinical factors).
    /// Lipids share 38.67; glucose uses 18.0.
    private static let mgdlToMmol: [String: Double] = [
        "total_cholesterol": 1.0 / 38.67,
        "ldl":               1.0 / 38.67,
        "hdl":               1.0 / 38.67,
        "triglycerides":     1.0 / 88.57,   // triglyceride molar conversion
        "fasting_glucose":   1.0 / 18.0,
    ]

    /// The canonical (stored) unit for a marker — the catalog's, or a fallback.
    static func canonicalUnit(for key: String, fallback: String) -> String {
        MarkerCatalog.definition(for: key)?.canonicalUnit ?? fallback
    }

    /// The unit options shown in the switcher. Two entries (canonical + mg/dL) for the dual-unit
    /// markers; otherwise just the single canonical unit.
    static func options(for key: String, canonical: String) -> [String] {
        if mgdlToMmol[key] != nil { return [canonicalUnit(for: key, fallback: canonical), "mg/dL"] }
        return [canonical]
    }

    /// Multiplicative factor turning a value in `from` into the canonical unit, or nil if no conversion.
    static func factorToCanonical(markerKey: String, from unit: String) -> Double? {
        guard unit == "mg/dL", let f = mgdlToMmol[markerKey] else { return nil }
        return f
    }

    /// Convert a typed value (in `from`) to the canonical stored unit. Identity when no conversion applies.
    static func toCanonical(markerKey: String, value: Double, from unit: String) -> Double {
        guard let f = factorToCanonical(markerKey: markerKey, from: unit) else { return value }
        return value * f
    }

    /// A short label for the conversion factor (4 sig figs), e.g. "0.02586".
    static func factorLabel(_ f: Double) -> String { String(format: "%.5g", f) }

    /// A lower-cased, underscored slug for a custom marker name → its stable key. Delegates to the CSV
    /// importer's `customKey` so a hand-added custom marker and an imported one always share one key.
    static func slug(_ name: String) -> String {
        let key = LabMarkerCsvImport.customKey(name)
        return key.isEmpty ? "custom_" : key
    }
}

#if DEBUG
@MainActor
private func markerEditorPreviewRepo() -> Repository {
    let repo = Repository(deviceId: "preview")
    repo.loaded = true
    return repo
}

#Preview("Marker Editor") {
    MarkerEditorView { _ in }
        .environmentObject(markerEditorPreviewRepo())
        .frame(width: 520, height: 720)
        .preferredColorScheme(.dark)
}
#endif
