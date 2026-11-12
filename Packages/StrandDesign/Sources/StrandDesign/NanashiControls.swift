import SwiftUI

/// Floating Label (21st 23565): the label lifts into a reserved slot on focus or fill.
/// The caller retains the native field, binding, focus, keyboard, and validation logic.
public struct NoopFloatingField<Content: View>: View {
    private let label: String
    private let isFocused: Bool
    private let isFilled: Bool
    private let isInvalid: Bool
    private let hint: String?
    private let unit: String?
    private let spokenLabel: String?
    private let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    public init(_ label: String, isFocused: Bool, isFilled: Bool,
                isInvalid: Bool = false, hint: String? = nil, unit: String? = nil,
                accessibilityLabel: String? = nil,
                @ViewBuilder content: () -> Content) {
        self.label = label
        self.isFocused = isFocused
        self.isFilled = isFilled
        self.isInvalid = isInvalid
        self.hint = hint
        self.unit = unit
        self.spokenLabel = accessibilityLabel
        self.content = content()
    }

    private var raised: Bool { isFocused || isFilled }
    private var edge: Color {
        isInvalid ? StrandPalette.statusCritical : (isFocused ? StrandPalette.focusRing : StrandPalette.hairline)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
            Text(label)
                .font(StrandFont.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: NoopMetrics.space5, alignment: .bottomLeading)
                .foregroundStyle(isInvalid ? StrandPalette.statusCritical : StrandPalette.textSecondary)
                .opacity(raised ? 1 : 0)
                .offset(y: raised ? 0 : NoopMetrics.space2)
                .accessibilityHidden(true)

            HStack(spacing: NoopMetrics.space2) {
                ZStack(alignment: .leading) {
                    // A long localized label reserves its natural height instead of clipping.
                    Text(label).font(StrandFont.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(0).accessibilityHidden(true)
                    content
                        .textFieldStyle(.plain)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .accessibilityLabel(Text(spokenLabel ?? (unit.map { label + ", " + $0 } ?? label)))
                        .accessibilityHint(Text(hint ?? ""))
                    Text(label)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(raised ? 0 : 1)
                        .offset(y: raised ? -NoopMetrics.space3 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if let unit {
                    Text(unit).font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize().accessibilityHidden(true)
                }
            }
            .padding(.horizontal, NoopMetrics.space3)
            .padding(.vertical, NoopMetrics.space2)
            .frame(minHeight: NoopMetrics.controlHeight)
            .background(NoopGlassControlSurface(isSelected: isFocused))
            .overlay(RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius)
                .strokeBorder(isFocused || isInvalid ? edge : .clear,
                              lineWidth: isFocused || isInvalid ? NoopMetrics.spaceHalf : NoopMetrics.lineWidth))

            if let hint, !hint.isEmpty {
                Text(hint).font(StrandFont.footnote)
                    .foregroundStyle(isInvalid ? StrandPalette.statusCritical : StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(isEnabled ? 1 : NoopButtonMetrics.disabledOpacity)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 1), value: raised)
    }
}

/// One value in a Reshaped Radio card group (21st 17933).
public struct NoopRadioOption<Value: Hashable>: Identifiable {
    public let id: Value
    public let title: String
    public let detail: String?
    public let systemImage: String?

    public init(id: Value, title: String, detail: String? = nil, systemImage: String? = nil) {
        self.id = id; self.title = title; self.detail = detail; self.systemImage = systemImage
    }
}

/// A single controlled choice: its leading outline/dot remains visible beside multiline copy.
public struct NoopRadioCard: View {
    private let title: String
    private let detail: String?
    private let systemImage: String?
    private let isSelected: Bool
    private let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    public init(title: String, detail: String? = nil, systemImage: String? = nil,
                isSelected: Bool, action: @escaping () -> Void) {
        self.title = title; self.detail = detail; self.systemImage = systemImage
        self.isSelected = isSelected; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: NoopMetrics.space3) {
                Circle().strokeBorder(isSelected ? StrandPalette.accentInk : StrandPalette.textSecondary,
                                      lineWidth: NoopMetrics.spaceHalf)
                    .overlay { if isSelected { Circle().fill(StrandPalette.accentInk).padding(NoopMetrics.space1) } }
                    .frame(width: NoopMetrics.radioDiameter, height: NoopMetrics.radioDiameter)
                    .padding(.top, NoopMetrics.spaceHalf)
                    .accessibilityHidden(true)
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(StrandPalette.accentInk)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Text(title).font(StrandFont.body.weight(.medium))
                        .foregroundStyle(StrandPalette.textPrimary)
                    if let detail {
                        Text(detail).font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(NoopMetrics.space4)
            .frame(minHeight: NoopMetrics.controlHeight)
            .background(NoopGlassControlSurface(isSelected: isSelected))
            .overlay(RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius)
                .strokeBorder(isSelected ? StrandPalette.accentInk.opacity(0.50) : .clear,
                              lineWidth: NoopMetrics.lineWidth))
            .opacity(isEnabled ? 1 : NoopButtonMetrics.disabledOpacity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Exclusive selection stays in one binding, rather than independent toggles.
public struct NoopRadioGroup<Value: Hashable>: View {
    @Binding private var selection: Value
    private let options: [NoopRadioOption<Value>]

    public init(selection: Binding<Value>, options: [NoopRadioOption<Value>]) {
        self._selection = selection; self.options = options
    }

    public var body: some View {
        VStack(spacing: NoopMetrics.space3) {
            ForEach(options) { option in
                NoopRadioCard(title: option.title, detail: option.detail, systemImage: option.systemImage,
                              isSelected: selection == option.id) { selection = option.id }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Notice Alert (21st 19366): pale tone, colored edge, leading symbol and compact copy.
public enum NoopNoticeTone {
    case primary, info, success, warning, destructive
    fileprivate var color: Color {
        switch self {
        case .primary: return StrandPalette.accent
        case .info: return StrandPalette.metricCyan
        case .success: return StrandPalette.statusPositive
        case .warning: return StrandPalette.statusWarning
        case .destructive: return StrandPalette.statusCritical
        }
    }
    fileprivate var symbol: String {
        switch self {
        case .primary, .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .destructive: return "exclamationmark.circle"
        }
    }
}

public struct NoopNotice: View {
    private let title: String
    private let message: String?
    private let tone: NoopNoticeTone
    private let systemImage: String?

    public init(_ title: String, message: String? = nil, tone: NoopNoticeTone = .info,
                systemImage: String? = nil) {
        self.title = title; self.message = message; self.tone = tone; self.systemImage = systemImage
    }

    public var body: some View {
        HStack(alignment: .top, spacing: NoopMetrics.space3) {
            Image(systemName: systemImage ?? tone.symbol)
                .font(StrandFont.body)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text(title).font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                if let message {
                    Text(message).font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textPrimary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(NoopMetrics.space3)
        .background(tone.color.opacity(0.10), in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius))
        .overlay(RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius)
            .strokeBorder(tone.color.opacity(0.25), lineWidth: NoopMetrics.lineWidth))
        .accessibilityElement(children: .combine)
    }
}

/// Sync Status Toast (21st 19146), with product state supplied by its host.
public enum NoopSyncStatus {
    case connected, syncing, disconnected, failed
    fileprivate var label: String {
        switch self {
        case .connected: return String(localized: "Connected", bundle: .module)
        case .syncing: return String(localized: "Syncing", bundle: .module)
        case .disconnected: return String(localized: "Disconnected", bundle: .module)
        case .failed: return String(localized: "Sync failed", bundle: .module)
        }
    }
    fileprivate var symbol: String {
        switch self {
        case .connected: return "checkmark"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .disconnected: return "link"
        case .failed: return "exclamationmark.triangle"
        }
    }
    fileprivate var color: Color {
        switch self {
        case .connected: return StrandPalette.statusPositive
        case .syncing: return StrandPalette.accent
        case .disconnected: return StrandPalette.textSecondary
        case .failed: return StrandPalette.statusCritical
        }
    }
}

public struct NoopSyncStatusCard<Actions: View>: View {
    private let title: String
    private let detail: String?
    private let status: NoopSyncStatus
    private let progress: Double?
    private let metadata: String?
    private let actions: Actions

    public init(title: String, detail: String? = nil, status: NoopSyncStatus,
                progress: Double? = nil, metadata: String? = nil,
                @ViewBuilder actions: () -> Actions) {
        self.title = title; self.detail = detail; self.status = status
        self.progress = progress; self.metadata = metadata; self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            HStack(alignment: .top, spacing: NoopMetrics.space3) {
                Image(systemName: status.symbol)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.onAccent)
                    .frame(width: NoopMetrics.space10, height: NoopMetrics.space10)
                    .background(StrandPalette.accent,
                                in: RoundedRectangle(cornerRadius: NoopMetrics.iconRadius))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
                    Text(title).font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    if let detail {
                        Text(detail).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: NoopMetrics.space1) {
                    Circle().fill(status.color).frame(width: NoopMetrics.space1, height: NoopMetrics.space1)
                    Text(status.label).font(StrandFont.caption.weight(.medium))
                }
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.horizontal, NoopMetrics.space2).padding(.vertical, NoopMetrics.space1)
                .background(status.color.opacity(0.10), in: Capsule())
                .overlay(Capsule().strokeBorder(status.color.opacity(0.20), lineWidth: NoopMetrics.lineWidth))
            }
            if status == .syncing, let progress, progress.isFinite {
                ProgressView(value: min(max(progress, 0), 1)).tint(StrandPalette.accent)
                    .accessibilityLabel(Text(status.label))
            }
            if let metadata {
                Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.lineWidth)
                    .accessibilityHidden(true)
                Text(metadata).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .padding(NoopMetrics.space4)
        .background { NoopPanelSurface(cornerRadius: NoopVisualStyle.compactRadius, elevated: true) }
    }
}

public extension NoopSyncStatusCard where Actions == EmptyView {
    init(title: String, detail: String? = nil, status: NoopSyncStatus,
         progress: Double? = nil, metadata: String? = nil) {
        self.init(title: title, detail: detail, status: status, progress: progress, metadata: metadata) { EmptyView() }
    }
}

/// Slider (21st 35040 / upstream Kuratli): inset thin track, white thumb and drag-only value bubble.
/// A native Slider supplies hit testing, scroll recognition, keyboard focus and range accessibility.
public struct NoopSlider: View {
    @Binding private var value: Double
    private let bounds: ClosedRange<Double>
    private let step: Double
    private let label: String
    private let marks: [Double]
    private let valueLabel: (Double) -> String
    private let onEditingChanged: (Bool) -> Void
    @State private var editing = false
    @FocusState private var keyboardFocused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    private var poseStill: Bool { motion.poseStill(reduceMotion) }

    public init(value: Binding<Double>, in bounds: ClosedRange<Double>, step: Double = 1,
                label: String, marks: [Double] = [], valueLabel: @escaping (Double) -> String,
                onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self._value = value; self.bounds = bounds; self.step = step
        self.label = label; self.marks = marks
        self.valueLabel = valueLabel; self.onEditingChanged = onEditingChanged
    }

    private func fraction(_ v: Double) -> CGFloat {
        guard bounds.upperBound > bounds.lowerBound, v.isFinite else { return 0 }
        return CGFloat(min(max((v - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound), 0), 1))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space4) {
                Text(label).font(StrandFont.subhead.weight(.medium))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                NoopRollingValue(text: valueLabel(value), poseStill: poseStill)
                    .font(StrandFont.subhead).monospacedDigit()
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .accessibilityHidden(true)

            GeometryReader { geometry in
                let thumb = NoopMetrics.sliderThumbDiameter
                let inset = thumb / 2
                let trackWidth = max(geometry.size.width - thumb, 1)
                let position = inset + trackWidth * fraction(value)
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.hairline)
                        .frame(height: NoopMetrics.sliderTrackHeight)
                        .padding(.horizontal, inset)
                    Capsule().fill(StrandPalette.textPrimary)
                        .frame(width: trackWidth * fraction(value), height: NoopMetrics.sliderTrackHeight)
                        .offset(x: inset)
                    ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                        if bounds.contains(mark), mark.isFinite {
                            Circle().fill(mark <= value ? StrandPalette.surfaceBase : StrandPalette.textSecondary)
                                .frame(width: NoopMetrics.space1, height: NoopMetrics.space1)
                                .offset(x: inset + trackWidth * fraction(mark) - NoopMetrics.spaceHalf)
                        }
                    }
                    Circle().fill(NoopVisualStyle.controlHighlight)
                        .overlay(Circle().strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.lineWidth))
                        .shadow(color: NoopVisualStyle.shadow.opacity(0.16), radius: NoopMetrics.space1, y: NoopMetrics.spaceHalf)
                        .frame(width: thumb, height: thumb)
                        .scaleEffect((editing || keyboardFocused) && !poseStill ? 1.16 : 1)
                        .offset(x: position - inset)
                    if editing || keyboardFocused {
                        NoopRollingValue(text: valueLabel(value), poseStill: poseStill)
                            .font(StrandFont.subhead.weight(.medium)).monospacedDigit()
                            .foregroundStyle(StrandPalette.surfaceBase)
                            .padding(.horizontal, NoopMetrics.space3)
                            .frame(minHeight: NoopMetrics.sliderBubbleMinHeight)
                            .background(StrandPalette.textPrimary, in: Capsule())
                            .fixedSize()
                            // The bubble stays inside the control's edges, as in the source CSS clamp.
                            .position(x: min(max(position, NoopMetrics.space10), geometry.size.width - NoopMetrics.space10),
                                      y: -NoopMetrics.space2)
                            .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottom)))
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .overlay {
                    // The native interaction layer replaces a pan gesture that could consume a vertical scroll.
                    Slider(value: $value, in: bounds, step: step, onEditingChanged: { active in
                        editing = active
                        onEditingChanged(active)
                    }) { Text(label) }
                    .labelsHidden()
                    .focused($keyboardFocused)
                    .opacity(0.02)
                    .accessibilityLabel(Text(label))
                    .accessibilityValue(Text(valueLabel(value)))
                    .disabled(!isEnabled)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius)
                        .strokeBorder(StrandPalette.focusRing, lineWidth: NoopMetrics.spaceHalf)
                        .opacity(keyboardFocused ? 1 : 0)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                .animation(poseStill ? nil : .spring(response: 0.26, dampingFraction: 1), value: editing)
                .animation(poseStill ? nil : .spring(response: 0.26, dampingFraction: 1), value: keyboardFocused)
            }
            .frame(height: NoopMetrics.formRowMinHeight)
        }
        .opacity(isEnabled ? 1 : NoopButtonMetrics.disabledOpacity)
    }
}

private struct NoopRollingValue: View {
    let text: String
    let poseStill: Bool
    @ViewBuilder var body: some View {
        if #available(iOS 17, macOS 14, *) {
            Text(text).contentTransition(.numericText())
                .animation(poseStill ? nil : .easeOut(duration: 0.16), value: text)
        } else {
            Text(text)
        }
    }
}

/// Expandable Card (21st 35717 / upstream Kuratli): one controlled header, inset divider and size morph.
public struct NoopExpandableCard<Header: View, Content: View>: View {
    @Binding private var isExpanded: Bool
    private let collapsedWidth: CGFloat?
    private let expandedWidth: CGFloat?
    private let header: Header
    private let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    private var poseStill: Bool { motion.poseStill(reduceMotion) }

    public init(isExpanded: Binding<Bool>, collapsedWidth: CGFloat? = nil, expandedWidth: CGFloat? = nil,
                @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self._isExpanded = isExpanded
        self.collapsedWidth = collapsedWidth; self.expandedWidth = expandedWidth
        self.header = header(); self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(poseStill ? nil : .spring(response: 0.40, dampingFraction: 1)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: NoopMetrics.space5) {
                    header.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(StrandFont.subhead.weight(.medium))
                        .foregroundStyle(isExpanded ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, NoopMetrics.space5)
                .padding(.vertical, NoopMetrics.space4)
                .frame(minHeight: NoopMetrics.expandableHeaderMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isExpanded ? [.isSelected] : [])
            .accessibilityValue(Text(isExpanded
                ? String(localized: "Expanded", bundle: .module)
                : String(localized: "Collapsed", bundle: .module)))

            if isExpanded {
                VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                    Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.lineWidth)
                        .accessibilityHidden(true)
                    content.padding(.horizontal, NoopMetrics.space5).padding(.bottom, NoopMetrics.space5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StrandPalette.surfaceInset)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: isExpanded ? expandedWidth ?? collapsedWidth : collapsedWidth)
        .background { NoopPanelSurface() }
        .clipShape(RoundedRectangle(cornerRadius: NoopVisualStyle.cardRadius))
    }
}

#if os(iOS)
/// Drawer (21st 31360): native snap points/dismissal retain platform interaction and focus trapping.
public struct NoopSheetModifier: ViewModifier {
    private let largeFirst: Bool
    public init(largeFirst: Bool) { self.largeFirst = largeFirst }

    public func body(content: Content) -> some View {
        content
            .background(StrandPalette.surfaceBase)
            .safeAreaInset(edge: .top, spacing: 0) {
                Capsule().fill(StrandPalette.textSecondary.opacity(0.35))
                    .frame(width: NoopMetrics.sheetHandleWidth, height: NoopMetrics.sheetHandleHeight)
                    .padding(.top, NoopMetrics.space2).padding(.bottom, NoopMetrics.space3)
                    .frame(maxWidth: .infinity)
                    .background(StrandPalette.surfaceBase)
                    .accessibilityHidden(true)
            }
            .presentationDragIndicator(.hidden)
            .presentationDetents(largeFirst ? [.large] : [.medium, .large])
            .modifier(NoopSheetBackground())
    }
}

private struct NoopSheetBackground: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackground(StrandPalette.surfaceBase)
                .presentationCornerRadius(NoopVisualStyle.cardRadius)
        } else {
            content
        }
    }
}
#endif
