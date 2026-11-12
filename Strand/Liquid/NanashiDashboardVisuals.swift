import SwiftUI
import StrandDesign

/// Orbit Sweep gradient (21st 26854), remapped to Obsidian surface roles.
/// The conic center and vignette are retained without a shader or animation clock.
struct NanashiOrbitSweep: View {
    var body: some View {
        AngularGradient(stops: [
            .init(color: StrandPalette.surfaceRaised, location: 0),
            .init(color: StrandPalette.surfaceInset, location: 0.23),
            .init(color: StrandPalette.hairline, location: 0.49),
            .init(color: StrandPalette.surfaceInset, location: 0.73),
            .init(color: StrandPalette.surfaceRaised, location: 1)
        ], center: UnitPoint(x: 0.46, y: 0.55), angle: .degrees(159))
        .overlay(RadialGradient(colors: [StrandPalette.accent.opacity(0.12), .clear],
                                center: .topTrailing, startRadius: 0, endRadius: NoopMetrics.chartHeight))
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Focus Frame Border (21st 29885): four independent rounded corner brackets.
/// Its steady native pose keeps the main health readout calm and accessible.
struct NanashiFocusFrame: View {
    var body: some View {
        Canvas { context, size in
            let length = NoopMetrics.space10
            let radius = NoopMetrics.cardRadius
            for corner in 0..<4 {
                var bracket = Path()
                bracket.move(to: CGPoint(x: length, y: 0))
                bracket.addLine(to: CGPoint(x: radius, y: 0))
                bracket.addQuadCurve(to: CGPoint(x: 0, y: radius), control: .zero)
                bracket.addLine(to: CGPoint(x: 0, y: length))
                let sx: CGFloat = corner % 2 == 0 ? 1 : -1
                let sy: CGFloat = corner < 2 ? 1 : -1
                let transform = CGAffineTransform(a: sx, b: 0, c: 0, d: sy,
                                                 tx: sx == 1 ? 0 : size.width,
                                                 ty: sy == 1 ? 0 : size.height)
                context.stroke(bracket.applying(transform), with: .color(StrandPalette.accent.opacity(0.65)),
                               style: StrokeStyle(lineWidth: NoopMetrics.spaceHalf, lineCap: .round))
            }
        }
        .padding(NoopMetrics.hairlineWidth)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Radial Chart (21st 28963), with real Charge / Effort / Rest progress only.
/// Three round-capped concentric tracks replace Recharts and its hover-only tooltip.
struct NanashiRadialScores: View {
    let charge: Double?
    let effort: Double?
    let rest: Double?
    var body: some View {
        GeometryReader { geometry in
            let edge = min(geometry.size.width, geometry.size.height)
            let band = edge / 13
            let rows: [(Double?, Color)] = [
                (charge, charge.map { StrandPalette.recoveryColor($0 * 100) } ?? StrandPalette.chargeColor),
                (effort, StrandPalette.effortColor),
                (rest, StrandPalette.restColor)
            ]
            ZStack {
                ForEach(rows.indices, id: \.self) { index in
                    let inset = band / 2 + CGFloat(index) * band * 1.5
                    Circle().stroke(StrandPalette.textPrimary.opacity(0.07), lineWidth: band)
                        .padding(inset)
                    Circle().trim(from: 0, to: min(1, max(0, rows[index].0 ?? 0)))
                        .stroke(rows[index].1, style: StrokeStyle(lineWidth: band, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(inset)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Stats Card (21st 7841): compact value, open-detail affordance and last-bar emphasis.
/// Data remains immediate; missing samples are never replaced by decorative values.
struct NanashiMetricBars: View {
    let values: [Double]
    let tint: Color
    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }
            let finite = values.filter(\.isFinite)
            let floor = min(0, finite.min() ?? 0)
            let ceiling = max(floor + 1, finite.max() ?? 1)
            let cell = size.width / CGFloat(values.count)
            let gap = min(NoopMetrics.space1, cell / 3)
            for (index, value) in values.enumerated() where value.isFinite {
                let height = size.height * max(0, min(1, (value - floor) / (ceiling - floor)))
                let rect = CGRect(x: CGFloat(index) * cell + gap / 2, y: size.height - height,
                                  width: cell - gap, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: NoopMetrics.space1),
                             with: .color(tint.opacity(index == values.count - 1 ? 1 : 0.22)))
            }
        }
        .frame(height: NoopMetrics.space8)
        .accessibilityHidden(true)
    }
}
