import SwiftUI

// MARK: - Static cold-glass background
//
// The gradient substrate comes from the 21st Glass Card (28259) demo, recolored with Harbor Blue.
// Broad illumination gives native translucent panes something to sample without a rendering clock.
// DayCycleScene remains available for existing asset callers and its pure hour mapping.

// MARK: - Hour → scene

/// Maps a local hour (0...23) to one of the ten day-cycle illustration asset names ("scene1"..."scene10").
/// Hand-tuned so the sky's light matches the time of day:
///   0–4 deep night · 5 first light · 6 dawn · 7 early morning · 8–9 sunrise · 10–11 day ·
///   12–16 bright midday · 17–18 sunset · 19–20 dusk · 21–23 night + moon.
public enum DayCycleScene {
    /// The asset name for a given hour. Defensive modulo so any hour value is safe.
    public static func assetName(hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        switch h {
        case 0, 1, 2, 3, 4: return "scene1"   // deep night
        case 5:             return "scene2"   // first light
        case 6:             return "scene3"   // dawn
        case 7:             return "scene6"   // early morning
        case 8, 9:          return "scene7"   // sunrise
        case 10, 11:        return "scene8"   // day
        case 12, 13, 14, 15, 16: return "scene10" // bright midday
        case 17, 18:        return "scene9"   // sunset
        case 19, 20:        return "scene5"   // dusk
        default:            return "scene4"   // 21–23 night + moon
        }
    }

    /// The asset name for *now*, from the system clock.
    public static var current: String {
        assetName(hour: Calendar.current.component(.hour, from: Date()))
    }

    /// Whether the hour's scene is a bright one (midday/day) — the hero then warrants a slightly firmer
    /// bottom scrim so the white ring numbers stay legible over the brighter sky.
    public static func isBright(hour: Int) -> Bool {
        let h = ((hour % 24) + 24) % 24
        return (8...16).contains(h)
    }
}

// MARK: - Glass backdrop

/// Theme-aware glass substrate. It contains only static gradients, with no particle or frame clock.
public struct NoopGlassBackground: View {
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public var body: some View {
        NoopEditorialBackdrop(dark: scheme == .dark)
    }
}

/// Source-compatible background retaining the fixed-dark contract of detail-screen readouts.
/// Glass Card's warm demo gradient becomes directional Harbor Blue light; no image is embedded.
public struct NoopEditorialBackdrop: View {
    public var dark: Bool
    public var patterned: Bool
    public var tint: Color?

    public init(dark: Bool = true, patterned: Bool = true, tint: Color? = nil) {
        self.dark = dark
        self.patterned = patterned
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            dark ? NoopVisualStyle.brandGraphite : StrandPalette.surfaceBase
            if patterned {
                RadialGradient(
                    colors: [NoopVisualStyle.glassMidtone.opacity(dark ? 0.23 : 0.20), .clear],
                    center: .topTrailing, startRadius: 0,
                    endRadius: NoopGlassMetrics.backdropRadius
                )
                LinearGradient(stops: [
                    .init(color: NoopVisualStyle.glassLight.opacity(dark ? 0.065 : 0.24), location: 0),
                    .init(color: .clear, location: 0.44),
                    .init(color: NoopVisualStyle.glassMidtone.opacity(dark ? 0.035 : 0.08), location: 1)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            if let tint { tint.opacity(0.035) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Source-compatible hero backdrop. The hour parameter remains accepted for existing callers.
public struct SceneHeroBackground: View {
    private let hour: Int

    public init(hour: Int = Calendar.current.component(.hour, from: Date())) {
        self.hour = hour
    }

    public var body: some View {
        NoopEditorialBackdrop()
            .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
    }
}

/// Full-width glass substrate fading into the theme canvas below the hero content.
public struct SceneScreenBackground: View {
    private let hour: Int
    public var height: CGFloat

    public init(hour: Int = Calendar.current.component(.hour, from: Date()), height: CGFloat = 600) {
        self.hour = hour
        self.height = height
    }

    public var body: some View {
        NoopEditorialBackdrop()
            .overlay(LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.82),
                .init(color: StrandPalette.surfaceBase, location: 1)
            ], startPoint: .top, endPoint: .bottom))
            .frame(height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Modifier + convenience

public extension View {
    /// Place the static editorial backdrop behind the hero, preserving existing hour-based call sites.
    ///
    ///     heroSection.sceneHeroBackground()            // current hour
    ///     heroSection.sceneHeroBackground(hour: 20)    // pinned hour (previews)
    func sceneHeroBackground(hour: Int = Calendar.current.component(.hour, from: Date())) -> some View {
        background(SceneHeroBackground(hour: hour))
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Scene hero — sample hours") {
    VStack(spacing: 16) {
        ForEach([2, 6, 8, 13, 18, 22], id: \.self) { hr in
            ZStack {
                VStack(spacing: 6) {
                    Text("hour \(hr)")
                        .font(StrandFont.overline)
                        .tracking(StrandFont.overlineTracking)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Text("88")
                        .font(StrandFont.rounded(36, weight: .bold))
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
            .frame(height: 96)
            .sceneHeroBackground(hour: hr)
        }
    }
    .padding(18)
    .frame(width: 360, height: 760)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
