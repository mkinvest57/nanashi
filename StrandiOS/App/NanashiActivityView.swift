#if os(iOS)
import SwiftUI
import StrandDesign

enum NanashiActivitySection: String, CaseIterable {
    case sessions, trends
    var title: LocalizedStringKey { self == .sessions ? "Workouts" : "Trends" }
}

/// Pill Morph Tabs (21st 7878): floating glass rail, moving selected plate.
/// Both visited children retain their own filter, range and scroll state during a session.
struct NanashiActivityView: View {
    @Binding var selection: NanashiActivitySection
    @State private var visited: Set<NanashiActivitySection> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal
    @Environment(\.nanashiPresenceIsActive) private var presenceIsActive
    @Environment(\.presentationIsActive) private var presentationIsActive
    @State private var sessionsScrollTop = 0
    @State private var trendsScrollTop = 0
    @State private var railHeight = NoopButtonMetrics.minHitTarget + NoopMetrics.space1 * 2 + NoopMetrics.space2
    @Namespace private var indicator

    var body: some View {
        ZStack {
            if visited.contains(.sessions) || selection == .sessions {
                PresentationValueBoundary(revision: NanashiActivitySection.sessions) {
                    WorkoutsView(usesFloatingHeader: true)
                }
                    .equatable()
                    .environment(\.presentationIsActive, presentationIsActive && selection == .sessions)
                    .environment(\.nanashiPresenceScene, .activity)
                    .environment(\.nanashiPresenceIsActive, presenceIsActive && selection == .sessions)
                    .environment(\.scrollToTopSignal, sessionsScrollTop)
                    .transformPreference(NoopDockScrollOffsetKey.self) { if selection != .sessions { $0 = nil } }
                    .opacity(selection == .sessions ? 1 : 0)
                    .allowsHitTesting(selection == .sessions).accessibilityHidden(selection != .sessions)
            }
            if visited.contains(.trends) || selection == .trends {
                PresentationValueBoundary(revision: NanashiActivitySection.trends) {
                    TrendsView(usesFloatingHeader: true)
                }
                    .equatable()
                    .environment(\.presentationIsActive, presentationIsActive && selection == .trends)
                    .environment(\.nanashiPresenceScene, .trends)
                    .environment(\.nanashiPresenceIsActive, presenceIsActive && selection == .trends)
                    .environment(\.scrollToTopSignal, trendsScrollTop)
                    .transformPreference(NoopDockScrollOffsetKey.self) { if selection != .trends { $0 = nil } }
                    .opacity(selection == .trends ? 1 : 0)
                    .allowsHitTesting(selection == .trends).accessibilityHidden(selection != .trends)
            }
        }
        // Reserve space in the scrolling content, not its viewport: cards pass behind the
        // floating capsule, and the space beside the rail stays visually and interactively open.
        .environment(\.noopFloatingHeaderClearance, railHeight)
        .overlay(alignment: .top) { sectionPicker }
        .onPreferenceChange(ActivityRailHeightKey.self) { height in
            guard height.isFinite, height > 0 else { return }
            let measuredHeight = height.rounded(.up)
            if measuredHeight != railHeight { railHeight = measuredHeight }
        }
        .background(NoopGlassBackground().ignoresSafeArea())
        .onChangeCompat(of: scrollToTopSignal) { _ in
            if selection == .sessions { sessionsScrollTop += 1 }
            else { trendsScrollTop += 1 }
        }
        .onAppear { visited.insert(selection) }
        .onChangeCompat(of: selection) { visited.insert($0) }
    }

    private var sectionPicker: some View {
        HStack(spacing: NoopMetrics.space1) {
            ForEach(NanashiActivitySection.allCases, id: \.self) { section in
                Button { selection = section } label: {
                    Text(section.title).font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(selection == section ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: NoopButtonMetrics.minHitTarget)
                        .background {
                            if selection == section {
                                NoopGlassControlSurface(cornerRadius: NoopVisualStyle.pillRadius, isSelected: true)
                                    .matchedGeometryEffect(id: "activity.section", in: indicator)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
                .accessibilityIdentifier("noop.activity.section.\(section.rawValue)")
            }
        }
        .padding(NoopMetrics.space1)
        .background(NoopPanelSurface(cornerRadius: NoopVisualStyle.pillRadius, elevated: true))
        .frame(maxWidth: NoopColdGlassMetrics.dockWidth)
        .padding(.horizontal, NoopMetrics.screenHPadding)
        .padding(.top, NoopMetrics.space2)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: ActivityRailHeightKey.self, value: geometry.size.height)
            }
        }
        .animation(reduceMotion ? nil : StrandMotion.interactive, value: selection)
    }
}

private struct ActivityRailHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
#endif
