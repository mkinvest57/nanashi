//  LiquidPrimitives.swift
//  NOOP · Amber Editorial primitives
//
//  Native adaptations of 21st Circular Progress Card (7716), Stats Bento (25311),
//  and Weekly Fitness Card (28213). Compatibility names keep existing metric callers
//  intact. Decorative layers use no simulation, frame clock, or motion sensor.

import SwiftUI
import StrandDesign   // NoopMotionState — the shared quiet-motion gate

// MARK: - Renderers (pure GraphicsContext drawing)

enum LiquidRender {

    /// Flat circular progress geometry adapted from 21st Circular Progress Card (7716).
    static func vessel(_ base: GraphicsContext, _ size: CGSize, _ sim: LiquidSim, now: Double, tint: Color) {
        let diameter = min(size.width, size.height)
        let lineWidth = max(NoopMetrics.space1, diameter / 10)
        let rect = CGRect(x: (size.width - diameter + lineWidth) / 2,
                          y: (size.height - diameter + lineWidth) / 2,
                          width: diameter - lineWidth, height: diameter - lineWidth)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        base.stroke(Path(ellipseIn: rect), with: .color(StrandPalette.surfaceInset),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        let level = max(0, min(1, sim.level))
        guard level > 0 else { return }
        var arc = Path()
        arc.addArc(center: center, radius: (diameter - lineWidth) / 2,
                   startAngle: .degrees(-90), endAngle: .degrees(-90 + level * 360), clockwise: false)
        base.stroke(arc, with: .color(tint), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }

    /// Flat progress band; legacy parameters remain for existing callers.
    static func tube(_ base: GraphicsContext, _ size: CGSize, _ sim: LiquidSim, now: Double,
                     frac: Double, tint: Color, showsHighlight: Bool = true,
                     usesCleanFill: Bool = false) {
        let rect = CGRect(origin: .zero, size: size)
        let track = Path(roundedRect: rect, cornerRadius: size.height / 2)
        base.fill(track, with: .color(StrandPalette.surfaceInset))
        let progress = CGRect(x: 0, y: 0, width: size.width * max(0, min(1, frac)), height: size.height)
        base.fill(Path(roundedRect: progress, cornerRadius: size.height / 2), with: .color(tint))
    }

    /// The plot mapping [thread] draws with, exposed so anything pointing AT the drawn curve reads the
    /// same geometry instead of restating it.
    ///
    /// The Today scrub crosshair is the caller that made this necessary. It had its own copy of the inset,
    /// the span floor and both mappings, which agreed by inspection and nothing else: change `pad` here and
    /// the crosshair drifts off the line it claims to mark, silently, with no test able to see it and only
    /// an eye on a device to catch it. A crosshair whose whole job is to point at what was drawn cannot
    /// derive where that is from a private copy.
    struct ThreadPlot {
        /// Inset on every side, in points.
        static let pad: Double = 10
        /// Floor on the value span, so a flat trace still fills the plot rather than dividing by zero.
        static let minSpan: Double = 10

        let size: CGSize
        let count: Int
        let minValue: Double
        let span: Double

        init(size: CGSize, values: [Double]) {
            var mn = Double.greatestFiniteMagnitude, mx = -Double.greatestFiniteMagnitude
            for v in values { mn = min(mn, v); mx = max(mx, v) }
            self.size = size
            self.count = values.count
            self.minValue = mn
            self.span = max(Self.minSpan, mx - mn)
        }

        /// Sample `i`'s x, equal-distance across the inset plot. Gap-aware by construction: positions come
        /// from the index, not from time, so a broken subpath still lands its samples where they are drawn.
        func x(_ i: Int) -> Double {
            Self.pad + Double(i) * (size.width - 2 * Self.pad) / Double(max(1, count - 1))
        }

        /// Value `v`'s y, inverted for the view's downward axis.
        func y(_ v: Double) -> Double {
            size.height - Self.pad - (v - minValue) / span * (size.height - 2 * Self.pad)
        }

        /// The sample nearest a touch at `xPosition`, clamped to the series.
        func nearestIndex(toX xPosition: Double) -> Int {
            guard count >= 2 else { return 0 }
            let plotWidth = max(1, size.width - 2 * Self.pad)
            let raw = ((xPosition - Self.pad) / plotWidth * Double(count - 1)).rounded()
            return min(count - 1, max(0, Int(raw)))
        }
    }

    /// The live heart-rate curve as a glowing liquid thread with a travelling glint.
    /// - Parameter segments: per-value line identity from `hrGapSegments`, or nil for a series known to be
    ///   contiguous. Values whose ids differ are stroked as SEPARATE subpaths, so a stretch the strap never
    ///   recorded reads as a break instead of a straight climb across it (#2082). Nil produces byte-for-byte
    ///   the path this drew before, which is what keeps the live 1 Hz stream untouched.
    static func thread(_ base: GraphicsContext, _ size: CGSize, values: [Double], now: Double, tint: Color,
                       segments: [String]? = nil) {
        guard values.count >= 2 else { return }
        let plot = ThreadPlot(size: size, values: values)
        let n = values.count
        func px(_ i: Int) -> Double { plot.x(i) }
        func py(_ v: Double) -> Double { plot.y(v) }
        func appendRun(_ p: inout Path, _ lo: Int, _ hi: Int) {
            // A lone bucket between two gaps is real data, and it has to draw as something. A bare `move`
            // strokes nothing at all, and a ZERO-length line is at the mercy of whether the renderer keeps
            // a degenerate subpath alive for its round cap. Give it a hair of width instead, so the cap has
            // something to round and the reading is a dot rather than a coin flip. Losing it would be the
            // same class of lie as the joined line this change removes: data on screen that is not there.
            guard hi > lo else {
                let x = px(lo), y = py(values[lo])
                p.move(to: CGPoint(x: x - 0.6, y: y))
                p.addLine(to: CGPoint(x: x + 0.6, y: y))
                return
            }
            p.move(to: CGPoint(x: px(lo), y: py(values[lo])))
            for i in (lo + 1)..<hi {
                let xc = (px(i) + px(i + 1)) / 2, yc = (py(values[i]) + py(values[i + 1])) / 2
                p.addQuadCurve(to: CGPoint(x: xc, y: yc), control: CGPoint(x: px(i), y: py(values[i])))
            }
            p.addLine(to: CGPoint(x: px(hi), y: py(values[hi])))
        }
        // Split once so genuinely missing readings remain gaps in the trace.
        // One run when nothing says otherwise preserves the live-series geometry.
        var runs: [ClosedRange<Int>] = [0...(n - 1)]
        if let segs = segments, segs.count == n { runs = hrGapRuns(segments: segs) }
        func curve() -> Path {
            var p = Path()
            for r in runs { appendRun(&p, r.lowerBound, r.upperBound) }
            return p
        }
        var ctx = base
        // Build one path per input update; there is no decorative frame loop.
        let line = curve()
        ctx.stroke(line, with: .color(tint.opacity(0.9)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        // The final real sample anchors the static trace; no decorative clock is needed.
        let ex = px(n - 1), ey = py(values[n - 1])
        let radius = NoopMetrics.space1 / 2
        ctx.fill(Path(ellipseIn: CGRect(x: ex - radius, y: ey - radius,
                                      width: radius * 2, height: radius * 2)), with: .color(tint))
    }
}

// MARK: - Views

/// Applies the splash tap either as a normal tap (consuming it) or as a simultaneous gesture (sharing
/// it with whatever wraps the view).
///
/// A plain `onTapGesture` inside a `NavigationLink` swallows the tap, so the link never pushes. That is
/// why the hero rings could splash but not navigate. `simultaneousGesture` lets both run, which is the
/// behaviour a tappable gauge wants; standalone vessels keep the consuming tap so nothing else changes.
private struct LiquidSplashTap: ViewModifier {
    let passesThrough: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if passesThrough {
            content.simultaneousGesture(TapGesture().onEnded { action() })
        } else {
            content.onTapGesture { action() }
        }
    }
}

/// Compatibility name for the flat score ring adapted from Circular Progress Card (7716).
/// The ring fills once when its value changes; there is no liquid simulation or frame clock.
struct LiquidVessel: View {
    let value: Double?
    let tint: Color
    var animated: Bool = true
    var tapPassesThrough: Bool = false
    var trackColor: Color = StrandPalette.surfaceInset

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    @State private var shown: Double = 0

    private var progress: Double { max(0, min(1, value ?? 0)) }

    var body: some View {
        GeometryReader { geometry in
            let width = max(NoopMetrics.space1, min(geometry.size.width, geometry.size.height) / 10)
            ZStack {
                Circle().stroke(trackColor, lineWidth: width)
                Circle().trim(from: 0, to: animated && !motion.poseStill(reduceMotion) ? shown : progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(width / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Circle())
        .accessibilityHidden(true)
        .onAppear { updateProgress() }
        .onChangeCompat(of: value) { _ in updateProgress() }
        .onChangeCompat(of: animated) { _ in updateProgress() }
        .onChangeCompat(of: motion.quietMotion) { _ in updateProgress() }
        .onChangeCompat(of: reduceMotion) { _ in updateProgress() }
        .onChangeCompat(of: motion.isLowPower) { _ in updateProgress() }
    }

    private func updateProgress() {
        withAnimation(animated ? StrandMotion.drawIn(reduced: motion.poseStill(reduceMotion)) : nil) {
            shown = progress
        }
    }
}

/// Flat progress band adapted from the fitness-card source; all existing metrics are unchanged.
struct LiquidTube: View {
    let frac: Double
    let tint: Color
    var height: CGFloat = NoopMetrics.indicatorTrackHeight
    var animated: Bool = true
    var showsHighlight: Bool = true
    var usesCleanFill: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(StrandPalette.surfaceInset)
                Capsule().fill(tint).frame(width: geometry.size.width * max(0, min(1, frac)))
            }
        }
        .frame(height: height)
        .animation(animated ? StrandMotion.drawIn(reduced: reduceMotion) : nil, value: frac)
        .accessibilityHidden(true)
    }
}

/// The real heart-rate trace, redrawn only when its input samples change.
struct LiquidThread: View {
    let bpm: [Double]
    var segments: [String]? = nil
    var tint: Color = StrandPalette.liquidHeart
    var height: CGFloat = NoopMetrics.tileHeight
    var animated: Bool = true

    var body: some View {
        Canvas { context, size in
            LiquidRender.thread(context, size, values: bpm, now: 0, tint: tint, segments: segments)
        }
        .frame(height: height)
    }
}

/// Diagonal accent-panel motif adapted from 21st Stats Bento (25311).
struct EditorialScorePattern: View {
    let tint: Color
    var body: some View {
        Canvas { context, size in
            let step = NoopMetrics.diagonalPatternSpacing
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            context.stroke(path, with: .color(tint), lineWidth: NoopMetrics.hairlineWidth)
        }
        .mask(LinearGradient(colors: [.clear, tint], startPoint: .bottomLeading, endPoint: .topTrailing))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Real historical metric samples presented as fitness-card cells (21st source 28213).
/// Samples retain their order and count; missing dates are never filled with invented readings.
struct EditorialMetricHistory: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }
            let finite = values.filter(\.isFinite)
            let floor = min(0, finite.min() ?? 0)
            let ceiling = max(floor + 1, finite.max() ?? 1)
            let cellWidth = size.width / CGFloat(values.count)
            let gap = min(NoopMetrics.spaceHalf, cellWidth / 3)
            for (index, value) in values.enumerated() where value.isFinite {
                let x = CGFloat(index) * cellWidth + gap / 2
                let track = CGRect(x: x, y: 0, width: max(0, cellWidth - gap), height: size.height)
                context.fill(Path(roundedRect: track, cornerRadius: NoopMetrics.space1),
                             with: .color(StrandPalette.surfaceInset))
                let height = size.height * max(0, min(1, (value - floor) / (ceiling - floor)))
                let bar = CGRect(x: x, y: size.height - height, width: track.width, height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: NoopMetrics.space1), with: .color(tint))
            }
        }
        .frame(height: NoopMetrics.space8)
        .accessibilityHidden(true)
    }
}

// MARK: - Shared liquid components (cross-platform: used by Today AND the other liquid screens on iOS + mac)

extension View {
    /// A light selection/impact haptic, available only where `sensoryFeedback` is (iOS 17 / macOS 14);
    /// a no-op below that so the liquid primitives still compile on the macOS 13 deployment target.
    @ViewBuilder func liquidTapHaptic(trigger: some Equatable) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            self.sensoryFeedback(.impact(weight: .light), trigger: trigger)
        } else {
            self
        }
    }

    /// A selection tick (e.g. the WHOOP-style day change), guarded so it compiles on macOS 13.
    @ViewBuilder func liquidSelectionHaptic(trigger: some Equatable) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            self.sensoryFeedback(.selection, trigger: trigger)
        } else {
            self
        }
    }

    /// A firmer medium impact (e.g. the pull-to-refresh release), guarded for the macOS 13 target.
    @ViewBuilder func liquidMediumHaptic(trigger: some Equatable) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            self.sensoryFeedback(.impact(weight: .medium), trigger: trigger)
        } else {
            self
        }
    }
}

/// The "this card was pressed" response for any tappable liquid card — a small settle inward plus a
/// touch of dimming. Cheap (a transform), so it's free on static cards and makes every tap feel physical.
struct LiquidPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? NoopButtonMetrics.pressedScale : 1)
            .opacity(configuration.isPressed ? NoopButtonMetrics.pressedOpacity : 1)
            .animation(reduceMotion ? nil : StrandMotion.interactive, value: configuration.isPressed)
    }
}

/// A number that animates to its value: SwiftUI interpolates `animatableData`, so the shown integer rolls
/// smoothly frame-by-frame whenever `value` changes inside a `withAnimation` block.
struct CountUpNumber: View, Animatable {
    var value: Double
    var font: Font
    /// Decimal places to render. 0 (default) keeps the whole-number scores (Charge/Rest/100-scale Effort)
    /// byte-identical; the WHOOP 0–21 Effort scale passes 1 so the hero matches the app-wide one-decimal
    /// `effortDisplay` convention instead of rounding 12.6 → "13" (#45).
    var decimals: Int = 0
    /// Rendered ahead of the number and never animated, for a value that is bounded rather than
    /// measured: Fitness Age arrives clamped, so a reading at the edge of the scale shows "≤20" while
    /// the count-up still runs (#2173). Empty by default, which leaves every existing caller identical.
    var prefix: String = ""
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View {
        Text(prefix + (decimals > 0 ? String(format: "%.\(decimals)f", value) : "\(Int(value.rounded()))"))
            .font(font).monospacedDigit()
    }
}

// MARK: - LiquidScoreGauge — Home hero score instrument (shared)

/// Flat progress instrument with an immediate score readout adapted from Circular Progress Card (7716).
/// Callers keep their existing diameter, metric scale, optional caption, and detail route.
struct LiquidScoreGauge: View {
    /// Matches `HeroScoreCell.vesselDiameter` — the Home hero trio size.
    private static let homeHeroDiameter: CGFloat = 96

    let score: Double?
    let tint: Color
    let diameter: CGFloat
    let animated: Bool
    /// The scale `score` is expressed on (100 for Charge/Rest, 21 for WHOOP Effort, etc.).
    var maxValue: Double = 100
    var decimals: Int = 0
    /// Optional caption under the number (nil = Home hero: number only).
    var captionText: String? = nil
    var numberColor: Color = StrandPalette.textPrimary
    var captionColor: Color = StrandPalette.textTertiary
    /// Forwarded to `LiquidVessel` so a gauge inside a link still splashes AND still navigates (#1995).
    var tapPassesThrough: Bool = false

    private var frac: Double? { score.map { max(0, min(1, $0 / maxValue)) } }
    private var centerFont: Font { StrandFont.rounded(diameter * 26 / Self.homeHeroDiameter) }
    private var captionFont: Font { StrandFont.rounded(diameter * 0.085, weight: .medium) }

    var body: some View {
        ZStack {
            LiquidVessel(value: frac, tint: tint, animated: animated,
                         tapPassesThrough: tapPassesThrough)
                .frame(width: diameter, height: diameter)
            VStack(spacing: captionText == nil ? 0 : 1) {
                Group {
                    if score != nil {
                        Text(decimals > 0 ? String(format: "%.\(decimals)f", score ?? 0)
                             : "\(Int((score ?? 0).rounded()))")
                            .font(centerFont).monospacedDigit()
                    } else {
                        Text("–").font(centerFont)
                    }
                }
                if let captionText {
                    Text(captionText)
                        .font(captionFont)
                        .foregroundStyle(captionColor)
                }
            }
            .foregroundStyle(numberColor)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .allowsHitTesting(false)
        }
        .frame(width: diameter, height: diameter)
    }
}


// MARK: - Editorial dock scroll signal

/// A real visible scroll position. The identity changes when navigation replaces the screen.
struct NoopDockScrollSample: Equatable {
    let screen: UUID
    let offset: CGFloat
}

struct NoopDockScrollOffsetKey: PreferenceKey {
    static let defaultValue: NoopDockScrollSample? = nil
    static func reduce(value: inout NoopDockScrollSample?, nextValue: () -> NoopDockScrollSample?) {
        if let next = nextValue() { value = next }
    }
}

private struct NoopDockActiveTabKey: EnvironmentKey { static let defaultValue = 0 }
private struct NoopDockScrollTrackingTagKey: EnvironmentKey { static let defaultValue: Int? = nil }

extension EnvironmentValues {
    var noopDockActiveTab: Int {
        get { self[NoopDockActiveTabKey.self] }
        set { self[NoopDockActiveTabKey.self] = newValue }
    }
    var noopDockScrollTrackingTag: Int? {
        get { self[NoopDockScrollTrackingTagKey.self] }
        set { self[NoopDockScrollTrackingTagKey.self] = newValue }
    }
}

/// Place at the top of a vertical ScrollView and name that ScrollView's coordinate space.
/// Only the visible selected tab emits, and only the platforms supporting dock minimization measure.
struct NoopDockScrollOffsetProbe: View {
    static let coordinateSpaceName = "noop.editorial.dock.scroll"
    var coordinateSpace: String = Self.coordinateSpaceName
    @Environment(\.noopDockActiveTab) private var activeTab
    @Environment(\.noopDockScrollTrackingTag) private var trackingTag
    @State private var screen = UUID()
    @State private var visible = false
    @AppStorage("noop.bottomBarAutoHide") private var autoHide = false

    var body: some View {
        Group {
            #if os(iOS)
            if #available(iOS 26.0, *), autoHide, visible, trackingTag == activeTab {
                GeometryReader { geometry in
                    Color.clear.preference(key: NoopDockScrollOffsetKey.self,
                                           value: NoopDockScrollSample(screen: screen,
                                               offset: geometry.frame(in: .named(coordinateSpace)).minY))
                }
            } else {
                Color.clear
            }
            #else
            Color.clear
            #endif
        }
        .frame(height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}
