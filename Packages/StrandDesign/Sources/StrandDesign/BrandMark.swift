import SwiftUI

// Nanashi's mark composes the concentric geometry of 21st Orbit Rotation (18010)
// with a native N letterform. Cold Glass retains one open arc and a larger readable N.
// No vendor logo or imagery is included. The icon exporter reads NanashiIdentity's constants.
public struct BrandMark: View {
    public var size: CGFloat
    public init(size: CGFloat = 120) { self.size = size }

    public var body: some View {
        ZStack {
            Circle().fill(NoopVisualStyle.invertedSurface)
                .overlay(Circle().fill(RadialGradient(
                    colors: [NoopVisualStyle.glassLight.opacity(NanashiIdentity.lightOpacity), .clear],
                    center: .topTrailing, startRadius: 0, endRadius: size * NanashiIdentity.lightRadius
                )))
            Circle().trim(from: NanashiIdentity.arcStart, to: NanashiIdentity.arcEnd)
                .stroke(LinearGradient(colors: [NoopVisualStyle.onInverted, NoopVisualStyle.glassLight.opacity(0.66)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: size * NanashiIdentity.orbitStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(size * NanashiIdentity.orbitInset)
            NanashiLetterform()
                .stroke(NoopVisualStyle.onInverted,
                        style: StrokeStyle(lineWidth: size * NanashiIdentity.letterStroke,
                                           lineCap: .round, lineJoin: .round))
                .frame(width: size * NanashiIdentity.letterWidth, height: size * NanashiIdentity.letterHeight)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ProductBrand.name))
        .accessibilityAddTraits(.isImage)
    }
}

private struct NanashiLetterform: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// Shared proportions for the native mark and its exported iOS icon.
public enum NanashiIdentity {
    public static let orbitInset: CGFloat = 0.11
    public static let arcStart: CGFloat = 0.08
    public static let arcEnd: CGFloat = 0.82
    public static let orbitStroke: CGFloat = 0.035
    public static let letterWidth: CGFloat = 0.34
    public static let letterHeight: CGFloat = 0.43
    public static let letterStroke: CGFloat = 0.075
    public static let lightOpacity: CGFloat = 0.20
    public static let lightRadius: CGFloat = 1.10
}
