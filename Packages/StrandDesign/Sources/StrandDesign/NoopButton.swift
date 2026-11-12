import SwiftUI

// MARK: - NoopButton — native adaptation of 21st Glass Button (4922, jahed)
//
// One button, four kinds: a frosted face catches diagonal light and compresses on press.
// Every colour is a token from `StrandPalette`; every dimension reads off `NoopMetrics`.
//
// Two front doors:
//   • `NoopButton("Save", kind: .primary) { … }`     — the convenience view.
//   • `Button("Save") { … }.buttonStyle(NoopButtonStyle(.primary))`  — adopt on an
//     existing Button (e.g. a Menu/role button) without rewriting it.
//
// Labels are sentence-case and wrap to their native Dynamic Type height. The
// optional leading icon stays with the label, and Reduce Motion keeps the
// press scale drops; only the dim remains).

/// The four button roles. Colour + emphasis differ; geometry is identical across all four.
public enum NoopButtonKind: Sendable {
    /// Filled accent with its contrast-aware label — the primary action on a screen.
    case primary
    /// Raised-surface fill, primary-text label, hairline edge — secondary actions.
    case secondary
    /// No fill, accent label — low-emphasis / inline actions.
    case tertiary
    /// Filled critical (red), white label — destructive / irreversible actions.
    case destructive
}

// MARK: - Shared geometry / resolved styling

/// Fixed geometry shared by the convenience view and the ButtonStyle so the two paths
/// are pixel-identical. The single source of truth for button shape.
public enum NoopButtonMetrics {
    /// Standard control height (48) — also the source for the min hit target floor.
    public static let height: CGFloat = NoopMetrics.controlHeight
    /// The source's pill silhouette, kept rounded when Dynamic Type adds a second line.
    public static let cornerRadius: CGFloat = NoopMetrics.controlHeight / 2
    /// Horizontal label inset.
    public static let hPadding: CGFloat = 18
    /// Vertical inset for labels that wrap or grow with Dynamic Type.
    public static let vPadding: CGFloat = NoopMetrics.space3
    /// Spacing between a leading icon and the label.
    public static let iconSpacing: CGFloat = 8
    /// Label tracking — a hair of openness on the semibold face.
    public static let tracking: CGFloat = 0
    /// Apple's minimum touch target. The button never reports a hit area below this.
    public static let minHitTarget: CGFloat = 44
    /// Pressed scale (spec: subtle 0.97). Reduce-Motion collapses this to 1 (dim only).
    public static let pressedScale: CGFloat = 0.99
    /// Pressed dim — a slight opacity drop, applied in BOTH motion modes.
    public static let pressedOpacity: Double = 0.96
    /// Disabled dim, shared so call sites don't invent their own.
    public static let disabledOpacity: Double = 0.4
}

/// Resolves a `NoopButtonKind` to its concrete fill / label / border tokens. Internal
/// so the fill model stays in one place; both the style and the view read from here.
struct NoopButtonAppearance {
    let fill: Color?          // nil = no fill (tertiary)
    let label: Color
    let border: Color?        // nil = no hairline edge
    let usesPanelSurface: Bool

    init(_ kind: NoopButtonKind) {
        switch kind {
        case .primary:
            fill = StrandPalette.accent
            label = StrandPalette.onAccent
            border = StrandPalette.accent.opacity(0.55)
            usesPanelSurface = false
        case .secondary:
            fill = nil
            label = StrandPalette.textPrimary
            border = nil
            usesPanelSurface = true
        case .tertiary:
            fill = nil
            label = StrandPalette.accentInk
            border = nil
            usesPanelSurface = false
        case .destructive:
            fill = StrandPalette.statusCritical
            label = NoopVisualStyle.onDestructive
            border = nil
            usesPanelSurface = false
        }
    }
}

// MARK: - Tactile face

/// Source-derived top light and shallow lift, compressed when held down.
private struct NoopButtonBackground: View {
    let appearance: NoopButtonAppearance
    let pressed: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: NoopButtonMetrics.cornerRadius, style: .continuous)
        ZStack {
            if appearance.usesPanelSurface {
                NoopGlassControlSurface(cornerRadius: NoopButtonMetrics.cornerRadius)
            }
            if let fill = appearance.fill {
                shape.fill(fill)
                    .overlay(shape.fill(LinearGradient(stops: [
                        .init(color: .clear, location: 0.2),
                        .init(color: NoopVisualStyle.controlHighlight.opacity(scheme == .dark ? 0.32 : 0.16), location: 0.43),
                        .init(color: .clear, location: 0.60)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .overlay(shape.strokeBorder(
                        LinearGradient(
                            colors: [NoopVisualStyle.controlHighlight.opacity(0.65), .clear,
                                     NoopVisualStyle.controlHighlight.opacity(0.18)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ), lineWidth: NoopMetrics.lineWidth
                    ))
            }
            if let border = appearance.border {
                shape.strokeBorder(border, lineWidth: NoopMetrics.lineWidth)
            }
        }
        .shadow(
            color: NoopVisualStyle.shadow.opacity(appearance.fill == nil && !appearance.usesPanelSurface ? 0 : (scheme == .dark ? 0.24 : 0.08)),
            radius: pressed ? NoopMetrics.lineWidth : NoopGlassMetrics.controlShadowRadius,
            x: 0, y: pressed ? 0 : NoopGlassMetrics.controlShadowOffset
        )
    }
}

// MARK: - ButtonStyle (adopt on any existing Button)

/// Apply the NOOP button look to ANY `Button` — e.g. a role/`Menu` button you can't
/// replace with `NoopButton`. Honours Reduce Motion: the press scale drops to a dim-only
/// state. Pixel-identical to `NoopButton` since both share `NoopButtonMetrics`/appearance.
public struct NoopButtonStyle: ButtonStyle {
    private let kind: NoopButtonKind
    private let fullWidth: Bool

    public init(_ kind: NoopButtonKind = .primary, fullWidth: Bool = false) {
        self.kind = kind
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        NoopButtonFace(label: configuration.label, kind: kind,
                       fullWidth: fullWidth, pressed: configuration.isPressed)
    }
}

/// Resolve environment in a View so both public and legacy styles inherit disabled and motion state.
private struct NoopButtonFace<Label: View>: View {
    let label: Label
    let kind: NoopButtonKind
    let fullWidth: Bool
    let pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let appearance = NoopButtonAppearance(kind)
        // Reduce Motion: no scale, dim only. Otherwise subtle scale + dim.
        let scale: CGFloat = (pressed && !reduceMotion) ? NoopButtonMetrics.pressedScale : 1
        let opacity: Double = pressed ? NoopButtonMetrics.pressedOpacity : 1

        label
            .labelStyle(.titleAndIcon)
            .font(StrandFont.body.weight(.semibold))
            .tracking(NoopButtonMetrics.tracking)
            .lineLimit(nil)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(appearance.label)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, NoopButtonMetrics.hPadding)
            .padding(.vertical, NoopButtonMetrics.vPadding)
            .frame(minHeight: NoopButtonMetrics.height)
            .contentShape(Rectangle())
            .background(NoopButtonBackground(appearance: appearance, pressed: pressed))
            .opacity(isEnabled ? opacity : NoopButtonMetrics.disabledOpacity)
            .scaleEffect(scale)
            .offset(y: pressed && !reduceMotion ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: pressed)
    }
}

// MARK: - NoopButton (the convenience view)

/// The unified button. A title (sentence-case `LocalizedStringKey`), an optional leading
/// SF Symbol, a `NoopButtonKind`, an optional `fullWidth`, and an action. Glass face,
/// directional rim, subtle press, 44pt hit floor and Reduce-Motion support.
///
/// ```swift
/// NoopButton("Save changes", systemImage: "checkmark", kind: .primary, fullWidth: true) {
///     save()
/// }
/// ```
public struct NoopButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let kind: NoopButtonKind
    private let fullWidth: Bool
    private let action: () -> Void

    public init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        kind: NoopButtonKind = .primary,
        fullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.fullWidth = fullWidth
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            // The ButtonStyle owns the chrome (fill / colour / press / padding). The label here is
            // just the icon + word as one centred unit at the exact 8pt token spacing. When there's
            // no icon the HStack holds a single Text, so the word sits dead-centre with no phantom gap.
            HStack(spacing: NoopButtonMetrics.iconSpacing) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.medium)  // optically centres to the cap height of the label
                        .fixedSize()
                }
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(NoopButtonStyle(kind, fullWidth: fullWidth))
    }
}

#if DEBUG
#Preview("NoopButton") {
    ScrollView {
        VStack(spacing: NoopMetrics.rowSpacing) {
            NoopButton("Primary action", systemImage: "checkmark", kind: .primary) {}
            NoopButton("Secondary action", systemImage: "square.and.arrow.up", kind: .secondary) {}
            NoopButton("Tertiary action", kind: .tertiary) {}
            NoopButton("Delete recording", systemImage: "trash", kind: .destructive) {}

            Divider().overlay(StrandPalette.hairline)

            NoopButton("Full-width primary", systemImage: "bolt.fill", kind: .primary, fullWidth: true) {}
            NoopButton("Full-width secondary", kind: .secondary, fullWidth: true) {}

            // Adopting the style on a vanilla Button.
            Button("Adopted via NoopButtonStyle") {}
                .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))

            NoopButton("Disabled", kind: .primary) {}
                .disabled(true)
        }
        .screenPadding()
        .padding(.vertical, NoopMetrics.space6)
    }
    .frame(width: 380, height: 560)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
