import SwiftUI

// MARK: - GlowRing — flat Circular Progress Card adaptation (21st 7716)
//
// A flat semantic progress stroke over a complete neutral track, with a stable tabular readout.
// Motion is a one-shot fill and respects Reduce Motion; data and scale stay caller-owned.

public struct GlowRing: View {

    /// Target fill, 0...1.
    public var fraction: Double
    /// The number shown in the centre — rolls up to this.
    public var value: Double
    /// Formats the (animated) value into the centre string.
    public var format: (Double) -> String
    /// The arc colour (solid, saturated — the domain accent).
    public var color: Color
    public var diameter: CGFloat
    public var lineWidth: CGFloat

    public init(fraction: Double, value: Double, format: @escaping (Double) -> String,
                color: Color, diameter: CGFloat, lineWidth: CGFloat) {
        self.fraction = fraction
        self.value = value
        self.format = format
        self.color = color
        self.diameter = diameter
        self.lineWidth = lineWidth
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// The centre-number font for a ring of the given diameter — the house numeral at `diameter * 0.36`,
    /// bold. Exposed so an EMPTY / carried / "No data" ring (which doesn't draw a `GlowRing`) can render
    /// its centre text in the EXACT same size + weight as a filled ring, keeping the hero trio's three
    /// centre read-outs visually consistent regardless of state.
    public static func centerFont(diameter: CGFloat) -> Font {
        StrandFont.rounded(diameter * 0.36, weight: .bold)
    }

    private var clamped: CGFloat { CGFloat(min(max(fraction, 0), 1)) }
    private var filled: CGFloat { appeared ? clamped : 0 }
    private var shown: Double { appeared ? value : 0 }
    private var drawSpring: Animation { .easeOut(duration: StrandMotion.durationSlow) }

    public var body: some View {
        ZStack {
            // Clearly-visible full-circle track, so the arc reads as a fraction of a circle (like WHOOP).
            Circle()
                .stroke(StrandPalette.hairline,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            // Design Reset: NO glow. A flat, crisp solid arc only — the clean Material-style look.
            arc.stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            // Centred rolling number.
            Text(format(shown))
                .font(Self.centerFont(diameter: diameter))
                .foregroundStyle(StrandPalette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .padding(.horizontal, lineWidth + 4)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.85), value: shown)
        }
        .frame(width: diameter, height: diameter)
        .animation(reduceMotion ? nil : drawSpring, value: filled)
        .onAppear { appeared = true }
    }

    /// The trimmed arc, drawn from 12 o'clock clockwise.
    private var arc: some Shape {
        Circle().trim(from: 0, to: max(0.0001, filled)).rotation(.degrees(-90))
    }
}
