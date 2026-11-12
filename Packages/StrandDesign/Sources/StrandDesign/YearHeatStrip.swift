#if !os(watchOS)
// YearHeatStrip uses .onContinuousHover + .help() tooltips (unavailable on watchOS); the watch
// never shows the year heat strip, so the whole view is excluded there. iOS/macOS unchanged.
import SwiftUI

// MARK: - Year Heat Strip (§9.4 Trends)
//
// HeatCalendar (21st 30542): columns = weeks, rows = weekdays. Each cell is tinted
// by that day's recovery score via the signature recovery gradient. Empty days
// (no data) render as a faint inset square. Hover shows a tooltip via SwiftUI's
// built-in help. Tapping pins a whole week on its faint plate; tapping it again releases it.
// Recovery is not an additive activity count, so the footer shows the selected day's actual score.

/// A day's recovery datum for the heat strip.
public struct RecoveryDay: Identifiable, Sendable {
    public let id = UUID()
    public var date: Date
    /// Recovery 0...100, or nil if no data for that day.
    public var score: Double?

    public init(date: Date, score: Double?) {
        self.date = date
        self.score = score
    }
}

public struct YearHeatStrip: View {

    public var days: [RecoveryDay]
    public var cellSize: CGFloat
    public var spacing: CGFloat
    public var showsMonthLabels: Bool
    /// Whether hovering a cell highlights it with a ring and shows a tooltip
    /// (date + score + recovery state word). Defaults on.
    public var showsHover: Bool
    /// Formats a day's score for the tooltip's bold line.
    public var valueFormat: (Double) -> String

    /// The week-column layout, built ONCE here in `init` from the sorted days rather than on every
    /// `body` eval. `buildWeeks()` reads `.component` for up to 365 days, and `body` re-ran on every
    /// hover (which mutates `@State hoverCell`) — so the layout was being recomputed on each pointer
    /// move. Since the struct is only re-created when `days` actually changes, computing it here
    /// memoizes the layout on `days` identity for free, with no behaviour change.
    private let weeks: [Week]

    public init(
        days: [RecoveryDay],
        cellSize: CGFloat = NoopMetrics.heatCellSize,
        spacing: CGFloat = NoopMetrics.heatCellSpacing,
        showsMonthLabels: Bool = true,
        showsHover: Bool = true,
        valueFormat: @escaping (Double) -> String = YearHeatStrip.localizedRecoveryValue
    ) {
        let sorted = days.sorted { $0.date < $1.date }
        self.days = sorted
        self.cellSize = cellSize
        self.spacing = spacing
        self.showsMonthLabels = showsMonthLabels
        self.showsHover = showsHover
        self.valueFormat = valueFormat
        self.weeks = YearHeatStrip.buildWeeks(from: sorted)
    }

    /// Localized default value label; specialized hosts can keep supplying their own formatter.
    public static func localizedRecoveryValue(_ score: Double) -> String {
        String(localized: "Recovery", bundle: .module) + " \(Int(score.rounded()))"
    }

    // The grid layout constants used both for drawing and hover hit-testing.
    private let gutterWidth: CGFloat = NoopMetrics.heatGutterWidth
    private let monthLabelHeight: CGFloat = NoopMetrics.heatMonthLabelHeight

    /// Hovered cell as (weekIndex, row), or nil.
    @State private var hoverCell: (week: Int, row: Int)? = nil
    @State private var pinnedCell: (week: Int, row: Int)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    private var poseStill: Bool { motion.poseStill(reduceMotion) }

    // A fixed Monday-first Gregorian calendar, stored once as a constant rather than a computed
    // property. `buildWeeks()` runs on every render (including each hover, which mutates @State)
    // and reads `.component` for up to 365 days, so the old computed form allocated a fresh
    // Calendar on every one of those ~730 accesses per render.
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday-first columns read nicely
        return c
    }()

    // Group days into week columns. weekday 0 = Monday ... 6 = Sunday.
    private struct Week: Identifiable {
        let id = UUID()
        var cells: [RecoveryDay?] // length 7, indexed by weekday row
        var monthLabel: String?
    }

    /// Pure: group the (already-sorted) days into Monday-first week columns. Static so it can run once
    /// from `init` (no instance state is read — only the static calendar + formatter cache).
    private static func buildWeeks(from days: [RecoveryDay]) -> [Week] {
        guard let first = days.first?.date else { return [] }
        var weeks: [Week] = []
        var current = Week(cells: Array(repeating: nil, count: 7), monthLabel: nil)
        var lastMonth = -1
        // Pad the first week so the first day lands on its weekday row.
        let firstRow = weekdayRow(first)
        var filledThisWeek = 0
        for _ in 0..<firstRow { filledThisWeek += 1 }

        for day in days {
            let row = weekdayRow(day.date)
            if row == 0 && filledThisWeek > 0 {
                weeks.append(current)
                current = Week(cells: Array(repeating: nil, count: 7), monthLabel: nil)
                filledThisWeek = 0
            }
            current.cells[row] = day
            // tag month label at the first cell of a new month
            let month = calendar.component(.month, from: day.date)
            if month != lastMonth {
                current.monthLabel = monthShort(day.date)
                lastMonth = month
            }
            filledThisWeek += 1
        }
        if filledThisWeek > 0 { weeks.append(current) }
        return weeks
    }

    private static func weekdayRow(_ date: Date) -> Int {
        // Map Calendar weekday (1=Sun...7=Sat) to Monday-first 0...6.
        let wd = calendar.component(.weekday, from: date)
        return (wd + 5) % 7
    }

    private static func monthShort(_ date: Date) -> String {
        let f = DateFormatterCache.month
        return f.string(from: date)
    }

    private let rowLabels = ["Mon", "", "Wed", "", "Fri", "", "Sun"]

    public var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            calendarGrid
            if let summary = selectedSummary {
                Text(summary)
                    .font(StrandFont.footnote).monospacedDigit()
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // One element for the entire strip, including its selected value; no per-day AX subtree.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(axSummary))
        .accessibilityValue(Text(selectedSummary ?? ""))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: selectAdjacentWeek(1)
            case .decrement: selectAdjacentWeek(-1)
            @unknown default: break
            }
        }
        .accessibilityAction(named: Text(String(localized: "Previous week", bundle: .module))) {
            selectAdjacentWeek(-1)
        }
        .accessibilityAction(named: Text(String(localized: "Next week", bundle: .module))) {
            selectAdjacentWeek(1)
        }
        .accessibilityAction(named: Text(String(localized: "Clear selection", bundle: .module))) {
            pinnedCell = nil
            hoverCell = nil
        }
    }

    @ViewBuilder private var calendarGrid: some View {
        // `weeks` is the layout built ONCE in init (see the stored property), not rebuilt per body eval.
        // Total drawn size, so the hover overlay can be laid over the grid and
        // a tooltip can be clamped within bounds.
        let gridWidth = gridOriginX + CGFloat(weeks.count) * (cellSize + spacing) - spacing
        let gridHeight = gridOriginY + 7 * (cellSize + spacing) - spacing

        VStack(alignment: .leading, spacing: spacing) {
            if showsMonthLabels {
                // #1021: month labels were each boxed to ONE cell width (~12pt), so a 3-letter month
                // ("Jul"/"May") truncated to "J…"/"M…". A month marker also needs to sit at the exact x of
                // the week column where the month starts. Positioning each label absolutely (topLeading +
                // .offset) at its column x, and letting it render at its natural width (.fixedSize), gives
                // the full month name room to overflow to the right — the ~4 empty columns before the next
                // month absorb it, and the grid cells below stay column-aligned (they're in their own HStack).
                ZStack(alignment: .topLeading) {
                    // Reserve the row's height + full grid width so the ZStack lays out over the columns.
                    Color.clear.frame(width: gridWidth, height: monthLabelHeight)
                    ForEach(Array(weeks.enumerated()), id: \.element.id) { weekIndex, week in
                        if let label = week.monthLabel, !label.isEmpty {
                            Text(label)
                                .font(StrandFont.overlineScaled(NoopMetrics.heatAxisLabelSize))
                                .foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize()
                                .offset(x: gridOriginX + CGFloat(weekIndex) * (cellSize + spacing))
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: spacing) {
                // weekday gutter
                VStack(alignment: .trailing, spacing: spacing) {
                    ForEach(0..<7, id: \.self) { r in
                        Text(rowLabels[r])
                            .font(StrandFont.overlineScaled(NoopMetrics.heatAxisLabelSize))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .frame(width: gutterWidth, height: cellSize, alignment: .trailing)
                    }
                }
                // week columns
                ForEach(Array(weeks.enumerated()), id: \.element.id) { weekIndex, week in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            cell(week.cells[row], week: weekIndex, row: row)
                        }
                    }
                    .background {
                        RoundedRectangle(cornerRadius: NoopMetrics.heatWeekRadius)
                            .fill(StrandPalette.textPrimary.opacity(pinnedCell?.week == weekIndex ? 0.06 : 0))
                            .padding(-spacing / 2)
                    }
                }
            }
        }
        .frame(width: gridWidth, height: gridHeight, alignment: .topLeading)
        .overlay(hoverOverlay(weeks: weeks, gridSize: CGSize(width: gridWidth, height: gridHeight)))
        .contentShape(Rectangle())
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .local).onEnded { tap in
            guard let hit = cellIndex(at: tap.location, weekCount: weeks.count),
                  weeks[hit.week].cells[hit.row] != nil else { return }
            // The tap selects real stored dates only; empty padding has no invented day or score.
            pinnedCell = pinnedCell?.week == hit.week ? nil : hit
        })
        .onContinuousHover(coordinateSpace: .local) { phase in
            guard showsHover else { return }
            switch phase {
            case .active(let location):
                hoverCell = cellIndex(at: location, weekCount: weeks.count)
            case .ended:
                hoverCell = nil
            }
        }
        .animation(poseStill ? nil : StrandMotion.fade, value: pinnedCell?.week)
    }

    private func selectAdjacentWeek(_ direction: Int) {
        let availableRows = weeks.map { week in
            week.cells.indices.filter { week.cells[$0] != nil }
        }
        guard let selection = HeatCalendarSelection.adjacent(
            current: pinnedCell, direction: direction, availableRows: availableRows
        ) else { return }
        pinnedCell = selection
        hoverCell = nil
    }

    private var selectedSummary: String? {
        guard let pinnedCell, pinnedCell.week < weeks.count,
              let day = weeks[pinnedCell.week].cells[pinnedCell.row] else { return nil }
        return daySummary(day)
    }

    private func daySummary(_ day: RecoveryDay) -> String {
        let value = day.score.map(valueFormat) ?? String(localized: "No data", bundle: .module)
        return DateFormatterCache.day.string(from: day.date) + " · " + value
    }

    /// A spoken one-line summary of the whole strip for VoiceOver.
    private var axSummary: String {
        let scored = days.compactMap { $0.score }
        guard let lo = scored.min(), let hi = scored.max() else {
            return String(localized: "Recovery calendar, no data", bundle: .module)
        }
        let avg = scored.reduce(0, +) / Double(scored.count)
        return String(localized: "Recovery calendar, \(scored.count) days, average \(Int(avg.rounded())), low \(Int(lo.rounded())), high \(Int(hi.rounded()))", bundle: .module)
    }

    // MARK: Grid geometry

    /// x of the first week column (after the weekday gutter + HStack spacing).
    private var gridOriginX: CGFloat { gutterWidth + spacing }
    /// y of the first cell row (below the optional month-label row).
    private var gridOriginY: CGFloat { showsMonthLabels ? monthLabelHeight + spacing : 0 }

    private func isHovered(_ week: Int, _ row: Int) -> Bool {
        guard let h = hoverCell else { return false }
        return h.week == week && h.row == row
    }

    /// Map a local cursor location to a (week, row) cell, or nil if outside the
    /// grid or in the inter-cell gaps.
    private func cellIndex(at point: CGPoint, weekCount: Int) -> (week: Int, row: Int)? {
        let stride = cellSize + spacing
        let lx = point.x - gridOriginX
        let ly = point.y - gridOriginY
        guard lx >= 0, ly >= 0 else { return nil }
        let week = Int(lx / stride)
        let row = Int(ly / stride)
        guard week >= 0, week < weekCount, row >= 0, row < 7 else { return nil }
        // Reject hits in the spacing gutter between cells.
        let withinX = lx - CGFloat(week) * stride
        let withinY = ly - CGFloat(row) * stride
        guard withinX <= cellSize, withinY <= cellSize else { return nil }
        return (week, row)
    }

    /// Centre of a cell in local coordinates.
    private func cellCenter(week: Int, row: Int) -> CGPoint {
        let stride = cellSize + spacing
        return CGPoint(
            x: gridOriginX + CGFloat(week) * stride + cellSize / 2,
            y: gridOriginY + CGFloat(row) * stride + cellSize / 2
        )
    }

    // MARK: Hover overlay (ring + tooltip)

    @ViewBuilder
    private func hoverOverlay(weeks: [Week], gridSize: CGSize) -> some View {
        if let h = (showsHover ? hoverCell : nil) ?? pinnedCell, h.week < weeks.count,
           let day = weeks[h.week].cells[h.row] {
            let center = cellCenter(week: h.week, row: h.row)
            let value = day.score.map(valueFormat) ?? String(localized: "No data", bundle: .module)
            let date = DateFormatterCache.day.string(from: day.date)
            let label = day.score.map { date + " · " + StrandPalette.recoveryState($0) } ?? date
            ZStack(alignment: .topLeading) {
                // subtle highlight ring on the hovered cell
                RoundedRectangle(cornerRadius: NoopMetrics.heatCellRadius, style: .continuous)
                    .stroke(StrandPalette.hairlineStrong, lineWidth: NoopMetrics.lineWidth)
                    .frame(width: cellSize + spacing, height: cellSize + spacing)
                    .position(center)
                PositionedTooltip(
                    anchor: center,
                    container: gridSize,
                    tooltip: ChartTooltip(
                        value: value,
                        label: label,
                        accent: day.score.map { StrandPalette.recoveryColor($0) } ?? StrandPalette.textSecondary
                    )
                )
            }
            .animation(poseStill ? nil : StrandMotion.fade, value: h.week)
            .animation(poseStill ? nil : StrandMotion.fade, value: h.row)
            .allowsHitTesting(false)
        }
    }

    private func cellLift(week: Int, row: Int) -> CGFloat {
        guard !poseStill, let hoverCell else { return 1 }
        let distance = max(abs(hoverCell.week - week), abs(hoverCell.row - row))
        switch distance {
        case 0: return NoopMetrics.heatHoveredScale
        case 1: return NoopMetrics.heatNeighborScale
        case 2: return NoopMetrics.heatOuterScale
        default: return 1
        }
    }

    @ViewBuilder
    private func cell(_ day: RecoveryDay?, week: Int, row: Int) -> some View {
        let hovered = isHovered(week, row)
        let shape = RoundedRectangle(cornerRadius: NoopMetrics.heatCellRadius)
        if let day, let score = day.score {
            shape
                .fill(StrandPalette.recoveryColor(score))
                .overlay(shape.strokeBorder(StrandPalette.textPrimary.opacity(
                    hovered ? 0.40 : (pinnedCell?.week == week ? 0.14 : 0.07)), lineWidth: NoopMetrics.lineWidth))
                .frame(width: cellSize, height: cellSize)
                .opacity(hovered ? 1.0 : (hoverCell == nil ? 1.0 : 0.78))
                .scaleEffect(cellLift(week: week, row: row))
                .animation(poseStill ? nil : .spring(response: 0.26, dampingFraction: 0.9), value: hoverCell?.week)
                .animation(poseStill ? nil : .spring(response: 0.26, dampingFraction: 0.9), value: hoverCell?.row)
                .help(daySummary(day))
                // No per-cell a11y element: the whole strip is one collapsed VoiceOver element (see the
                // `children: .ignore` summary on the body), so per-day detail no longer builds an O(days)
                // semantics subtree. The `.help` above stays — it's a macOS pointer tooltip, not an a11y node.
        } else if day != nil {
            shape
                .fill(StrandPalette.surfaceInset)
                .overlay(shape.stroke(StrandPalette.hairline.opacity(0.6), lineWidth: 0.5))
                .frame(width: cellSize, height: cellSize)
        } else {
            shape
                .fill(Color.clear)
                .frame(width: cellSize, height: cellSize)
        }
    }
}

/// Resolves a neighboring week to an actual cell, retaining the weekday where possible.
private enum HeatCalendarSelection {
    static func adjacent(current: (week: Int, row: Int)?, direction: Int,
                         availableRows: [[Int]]) -> (week: Int, row: Int)? {
        guard !availableRows.isEmpty, direction != 0 else { return nil }
        let step = direction > 0 ? 1 : -1
        let base = current?.week ?? (step > 0 ? -1 : availableRows.count)
        let start = min(max(base + step, 0), availableRows.count - 1)
        let boundary = step > 0 ? availableRows.count - 1 : 0
        let preferredRow = current?.row ?? (step > 0 ? 0 : 6)
        for week in stride(from: start, through: boundary, by: step) {
            if let row = availableRows[week].min(by: {
                abs($0 - preferredRow) < abs($1 - preferredRow)
            }) {
                return (week, row)
            }
        }
        return nil
    }
}

// Small cached formatters (creating DateFormatter is expensive).
private enum DateFormatterCache {
    static let month: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f
    }()
    static let day: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
    }()
}

#if DEBUG
private func sampleYear() -> [RecoveryDay] {
    let cal = Calendar.current
    let today = Date()
    return (0..<365).map { i in
        let date = cal.date(byAdding: .day, value: -(364 - i), to: today)!
        // Some gaps + a wavy recovery profile.
        let gap = (i % 23 == 0)
        let v = 55 + 28 * sin(Double(i) / 11.0) + Double((i * 31) % 17) - 8
        return RecoveryDay(date: date, score: gap ? nil : max(2, min(99, v)))
    }
}

#Preview("YearHeatStrip") {
    VStack(alignment: .leading, spacing: 12) {
        Text("Recovery — past year").strandOverline()
        Text("Hover a cell: ring + date, score and recovery-state tooltip.")
            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        YearHeatStrip(days: sampleYear())
    }
    .padding(28)
    .frame(width: 900, height: 240)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
#endif
