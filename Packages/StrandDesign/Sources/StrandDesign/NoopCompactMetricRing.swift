import SwiftUI

/// A single-series adaptation of 21st Radial Chart (28963): neutral track, round-capped value arc
/// and immediate tabular value. Static rendering removes the browser chart's hover dependency.
public struct NoopCompactMetricRing: View {
    private let value: Double?
    private let tint: Color

    public init(value: Double?, tint: Color) {
        self.value = value.flatMap { $0.isFinite ? $0 : nil }
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            Circle().stroke(StrandPalette.textPrimary.opacity(0.07), lineWidth: NoopColdGlassMetrics.sleepRingWidth)
            Circle().trim(from: 0, to: min(1, max(0, (value ?? 0) / 100)))
                .stroke(tint, style: StrokeStyle(lineWidth: NoopColdGlassMetrics.sleepRingWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(value.map { String(format: "%.0f", $0) } ?? "—")
                .font(StrandFont.number(NoopColdGlassMetrics.compactValueSize))
                .foregroundStyle(StrandPalette.textPrimary)
        }
        .padding(NoopColdGlassMetrics.sleepRingWidth / 2)
        .frame(width: NoopColdGlassMetrics.sleepRingDiameter, height: NoopColdGlassMetrics.sleepRingDiameter)
        .accessibilityHidden(true)
    }
}

#Preview {
    NoopCompactMetricRing(value: 89, tint: StrandPalette.restColor)
        .padding()
        .background(StrandPalette.surfaceBase)
}
