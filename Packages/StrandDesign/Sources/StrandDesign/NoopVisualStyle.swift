import SwiftUI

// MARK: - NOOP visual foundation
//
// Nanashi Cold Glass adapts the retrieved 21st Harbor Blue theme by serafimcloud.
// The pale chart-5 becomes the dark-mode chrome accent; physiological colors stay separate.

public enum NoopVisualStyle {
    public static let canvas = Color(light: "#F1F5F9", dark: "#0F172A")
    public static let surface = Color(light: "#FFFFFF", dark: "#1E293B")
    public static let surfaceTop = Color(light: "#FFFFFF", dark: "#334155")
    public static let surfaceBottom = Color(light: "#F1F5F9", dark: "#0F172A")
    public static let input = Color(light: "#F1F5F9", dark: "#0F172A")
    public static let inset = input
    public static let secondarySurface = Color(light: "#DCE6F9", dark: "#1E293B")
    public static let onSecondary = Color(light: "#194391", dark: "#DCE6F9")
    public static let mutedSurface = Color(light: "#F1F5F9", dark: "#1E293B")
    public static let hoverSurface = Color(light: "#DCE6F9", dark: "#334155")
    public static let onHover = Color(light: "#194391", dark: "#F8FAFC")

    public static let border = Color(light: "#E2E8F0", dark: "#334155")
    public static let borderHighlight = Color(light: "#A5C2F9", dark: "#94A3B8")
    public static let divider = border

    public static let primaryText = Color(light: "#0F172A", dark: "#F8FAFC")
    public static let secondaryText = Color(light: "#64748B", dark: "#94A3B8")
    public static let tertiaryText = secondaryText

    // Source theme primary/foreground roles. Legacy names retain source compatibility.
    public static let primary = Color(light: "#194391", dark: "#BFDBFE")
    public static let primaryPressed = Color(light: "#194391", dark: "#93C5FD")
    public static var primaryInk: Color { StrandPalette.accentInk }
    public static let onPrimary = Color(light: "#FFFFFF", dark: "#0F172A")
    public static let brandAccent = primary
    public static let brandViolet = brandAccent
    public static let invertedSurface = Color(hex: "#0F172A")
    public static let invertedBorder = Color(hex: "#334155")
    public static let onInverted = Color(hex: "#F8FAFC")
    public static let onInvertedMuted = Color(hex: "#94A3B8")
    // Selection on fixed graphite surfaces has its own foreground pair in both appearances.
    public static let invertedSelection = Color(hex: "#BFDBFE")
    public static let onInvertedSelection = Color(hex: "#0F172A")
    public static let mint = primary
    public static let mintDeep = primary
    public static let mintGlow = primaryPressed
    public static let brandGraphite = invertedSurface
    public static let brandAmber = primary
    public static let brandBorder = invertedBorder
    public static let shadow = Color(hex: "#000000")
    public static let dockShadow = shadow.opacity(0.18)
    public static let controlHighlight = Color(hex: "#FFFFFF")
    public static let glassLight = Color(hex: "#BFDBFE")
    public static let glassMidtone = Color(hex: "#7CA3F5")
    public static let backdropPatternOpacity: Double = 0
    public static let toggleThumb = Color(hex: "#FFFFFF")
    public static let onAmber = onPrimary
    public static let onDestructive = Color(hex: "#FFFFFF")

    public static let cardRadius: CGFloat = 24
    public static let compactRadius: CGFloat = 16
    public static let pillRadius: CGFloat = 999
    public static let pagePadding: CGFloat = 16
    public static let cardPadding: CGFloat = 16
    public static let itemGap: CGFloat = 12
    public static let sectionGap: CGFloat = 24
}

/// Static optical geometry adapted from 21st Glass Card (28259, educalvolpz).
/// Native material replaces web displacement; sharp layered rims preserve the pane's thickness.
public enum NoopGlassMetrics {
    public static let rimInset: CGFloat = 2.5
    public static let rimWidth: CGFloat = 0.75
    public static let specularRadius: CGFloat = 260
    public static let shadowRadius: CGFloat = 16
    public static let elevatedShadowRadius: CGFloat = 24
    public static let shadowOffset: CGFloat = 8
    public static let backdropRadius: CGFloat = 580
    public static let controlShadowRadius: CGFloat = 5
    public static let controlShadowOffset: CGFloat = 3
}

/// Glass Card (21st 28259): a frosted face, polished inner rim and directional cold light.
/// Its SVG refraction and pointer tracking become static native material for phone efficiency.
public struct NoopPanelSurface: View {
    public var tint: Color?
    public var cornerRadius: CGFloat
    public var elevated: Bool
    public var surfaceOpacity: Double
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        tint: Color? = nil,
        cornerRadius: CGFloat = NoopVisualStyle.cardRadius,
        elevated: Bool = false,
        surfaceOpacity: Double = 1
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.elevated = elevated
        self.surfaceOpacity = surfaceOpacity
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if reduceTransparency {
                shape.fill(NoopVisualStyle.surface)
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(NoopVisualStyle.surface.opacity(scheme == .dark ? 0.64 : 0.58))
                shape.fill(LinearGradient(
                    colors: [NoopVisualStyle.controlHighlight.opacity(scheme == .dark ? 0.075 : 0.48),
                             .clear, NoopVisualStyle.surfaceBottom.opacity(0.18)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                shape.fill(RadialGradient(
                    colors: [(tint ?? NoopVisualStyle.glassLight).opacity(scheme == .dark ? 0.09 : 0.10), .clear],
                    center: .topTrailing, startRadius: 0, endRadius: NoopGlassMetrics.specularRadius
                ))
            }
            shape.strokeBorder(
                LinearGradient(stops: [
                    .init(color: NoopVisualStyle.controlHighlight.opacity(scheme == .dark ? 0.48 : 0.95), location: 0),
                    .init(color: NoopVisualStyle.glassLight.opacity(0.12), location: 0.38),
                    .init(color: NoopVisualStyle.border.opacity(0.70), location: 0.65),
                    .init(color: NoopVisualStyle.glassLight.opacity(scheme == .dark ? 0.28 : 0.55), location: 1)
                ], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: NoopMetrics.lineWidth
            )
            shape.inset(by: NoopGlassMetrics.rimInset).strokeBorder(
                LinearGradient(colors: [NoopVisualStyle.controlHighlight.opacity(scheme == .dark ? 0.10 : 0.65),
                                        .clear, NoopVisualStyle.controlHighlight.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: NoopGlassMetrics.rimWidth
            )
        }
        .shadow(color: NoopVisualStyle.shadow.opacity(scheme == .dark ? 0.20 : 0.07),
                radius: elevated ? NoopGlassMetrics.elevatedShadowRadius : NoopGlassMetrics.shadowRadius,
                x: 0, y: NoopGlassMetrics.shadowOffset)
        .opacity(reduceTransparency ? 1 : min(1, max(0, surfaceOpacity)))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Glass Button (21st 4922, jahed): a luminous rounded face with opposing edge reflections.
/// Selection increases the cold tint without changing the control's bounds.
public struct NoopGlassControlSurface: View {
    public var cornerRadius: CGFloat
    public var isSelected: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(cornerRadius: CGFloat = NoopVisualStyle.compactRadius, isSelected: Bool = false) {
        self.cornerRadius = cornerRadius
        self.isSelected = isSelected
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if reduceTransparency {
                shape.fill(isSelected ? NoopVisualStyle.secondarySurface : NoopVisualStyle.surface)
            } else {
                shape.fill(.thinMaterial)
                shape.fill((isSelected ? NoopVisualStyle.primary : NoopVisualStyle.surface)
                    .opacity(isSelected ? 0.16 : 0.48))
                shape.fill(LinearGradient(colors: [NoopVisualStyle.controlHighlight.opacity(scheme == .dark ? 0.10 : 0.50),
                                                  .clear, NoopVisualStyle.controlHighlight.opacity(0.035)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            shape.strokeBorder(LinearGradient(
                colors: [NoopVisualStyle.controlHighlight.opacity(scheme == .dark ? 0.40 : 0.95),
                         NoopVisualStyle.border.opacity(0.45),
                         NoopVisualStyle.glassLight.opacity(isSelected ? 0.45 : 0.18)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: NoopMetrics.lineWidth)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Shared frosted chrome for sheet and split-view headers.
public struct NoopChromeSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public var body: some View {
        ZStack {
            if reduceTransparency {
                NoopVisualStyle.surface
            } else {
                Rectangle().fill(.regularMaterial)
                NoopVisualStyle.surface.opacity(0.40)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NoopVisualStyle.divider)
                .frame(height: NoopGlassMetrics.rimWidth)
        }
    }
}

public extension View {
    func noopPanel(
        tint: Color? = nil,
        cornerRadius: CGFloat = NoopVisualStyle.cardRadius,
        elevated: Bool = false,
        surfaceOpacity: Double = 1
    ) -> some View {
        background {
            NoopPanelSurface(
                tint: tint,
                cornerRadius: cornerRadius,
                elevated: elevated,
                surfaceOpacity: surfaceOpacity
            )
        }
    }
}
