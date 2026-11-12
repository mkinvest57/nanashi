import SwiftUI

/// A finite letter-settle adaptation of 21st Orbital Letters (19169).
/// Text is always readable; the native spring replaces the catalog's per-frame DOM engine.
public struct NanashiWordmark: View {
    public var size: CGFloat
    public var animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    @State private var settled = false

    public init(size: CGFloat = 36, animated: Bool = false) {
        self.size = size
        self.animated = animated
    }

    private var still: Bool { !animated || settled || motion.poseStill(reduceMotion) }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(ProductBrand.name.enumerated()), id: \.offset) { index, letter in
                Text(String(letter))
                    .font(StrandFont.display(size))
                    .offset(x: still ? 0 : cos(Double(index)) * size * 0.12,
                            y: still ? 0 : sin(Double(index)) * size * 0.12)
                    .rotationEffect(.degrees(still ? 0 : Double(index % 3 - 1) * 8))
            }
        }
        .foregroundStyle(StrandPalette.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ProductBrand.name))
        .onAppear {
            withAnimation(animated ? StrandMotion.hero : nil) { settled = true }
        }
    }
}

/// Compact concentric orbits from 21st Orbit Rotation (18010).
/// A static native pose keeps the welcome screen light and respects quiet motion.
public struct NanashiOrbitScene: View {
    public var size: CGFloat
    public init(size: CGFloat = 216) { self.size = size }

    public var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { orbit in
                Circle().stroke(StrandPalette.hairlineStrong,
                                style: StrokeStyle(lineWidth: NoopMetrics.hairlineWidth,
                                                   dash: [NoopMetrics.spaceHalf, NoopMetrics.space2]))
                    .padding(CGFloat(orbit) * NoopMetrics.space6)
            }
            BrandMark(size: size * 0.48)
            satellite("moon.stars.fill", tint: NoopVisualStyle.brandAccent)
                .offset(x: -size * 0.36, y: -size * 0.27)
            satellite("waveform.path.ecg", tint: NoopVisualStyle.brandAccent)
                .offset(x: size * 0.40, y: -size * 0.05)
            satellite("lock.shield", tint: StrandPalette.textPrimary)
                .offset(x: -size * 0.04, y: size * 0.38)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func satellite(_ icon: String, tint: Color) -> some View {
        Image(systemName: icon).font(StrandFont.headline)
            .foregroundStyle(tint)
            .frame(width: NoopMetrics.controlHeight, height: NoopMetrics.controlHeight)
            .background(StrandPalette.surfaceRaised, in: Circle())
            .overlay(Circle().strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
    }
}
