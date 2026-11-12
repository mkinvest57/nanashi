#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign

private extension View {
    /// Bound metadata construction for the root's compatibility modifiers. A single uninterrupted
    /// chain overflows the Swift runtime stack on device before the first tab can render. These
    /// boundaries are unconditional, so state changes keep the same tab and navigation identities.
    func rootShellBoundary() -> AnyView { AnyView(self) }
}

/// iOS navigation shell. macOS uses a `NavigationSplitView` sidebar (`RootView`); on iPhone the
/// natural analogue is a `TabView` with the most-used screens as tabs and everything else under a
/// "More" list. Every screen is the same `StrandDesign`-built view the macOS app uses.
struct RootTabView: View {
    @EnvironmentObject private var repo: Repository
    let homeScreenQuickActionsEnabled: Bool
    let initialTab: Int

    init(homeScreenQuickActionsEnabled: Bool = true, initialTab: Int = 0) {
        self.homeScreenQuickActionsEnabled = homeScreenQuickActionsEnabled
        self.initialTab = initialTab
    }

    var body: some View {
        // The shell needs Repository only for explicit refresh actions. Passing its stable reference
        // through this boundary prevents every live sensor publication from invalidating all tabs.
        NanashiTabShell(repo: repo, homeScreenQuickActionsEnabled: homeScreenQuickActionsEnabled,
                        initialTab: initialTab)
            .equatable()
    }
}

private struct NanashiTabShell: View, Equatable {
    let repo: Repository
    let initialTab: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.repo === rhs.repo && lhs.homeScreenQuickActionsEnabled == rhs.homeScreenQuickActionsEnabled
            && lhs.initialTab == rhs.initialTab
    }
    /// #1841: shared with Android by NAME and meaning, not by storage — the two platforms keep their own
    /// stores, exactly as the Clock format setting does.
    ///
    /// Default FALSE here while Android defaults true, and the divergence is deliberate. Apple's forums
    /// report `.tabBarMinimizeBehavior(.onScrollDown)` failing to trigger in tabs built on
    /// `NavigationStack(path:)` — which is every primary tab in this file, bound deliberately so a tab
    /// root can pop and re-scroll. So this may well be inert on our structure, and defaulting ON would
    /// advertise a behaviour that never happens. Off until someone confirms it on an iOS 26 device.
    /// The Coach master switch, under the same `noop.` key Android writes. Default ON, so every install
    /// that shipped with the tab is unchanged.
    ///
    /// Not tab chrome: with this off the AI is off. The tab goes, the Today launcher card goes, and the
    /// daily brief is cancelled, because the brief calls a provider from the BACKGROUND with no UI
    /// attached and would otherwise keep posting AI notifications for a feature the wearer switched off.
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @AppStorage("noop.bottomBarAutoHide") private var bottomBarAutoHide = false

    /// The live gym session, owned at the app root — see `LiftSessionController`.
    @EnvironmentObject private var liftSession: LiftSessionController
    /// External entry points must wait until the mandatory first-run gates have completed. The root owns
    /// that state; keeping it explicit here prevents this shell's window-level sheet from covering a gate.
    let homeScreenQuickActionsEnabled: Bool

    /// Cross-screen navigation requests (e.g. Live → "Manage devices"). Devices isn't a tab — it lives
    /// behind the More list — so a request presents it as a sheet, matching the quick-action screens.
    @EnvironmentObject private var router: NavRouter
    /// The scene-local receiver for actions chosen from NOOP's Home Screen icon menu.
    @EnvironmentObject private var homeScreenQuickActions: HomeScreenQuickActionSceneDelegate

    /// Which quick-action screen the centre FAB is presenting (nil = sheet closed).
    @State private var quickAction: QuickAction?
    /// Presents the Devices manager (pair / switch bands) when a screen asks the shell to open it.
    @State private var showDevices = false
    /// A routed v5 pillar screen (Insights hub / Lab Book / fused record / Rhythm) presented as a sheet
    /// when a hub row deep-links to it via NavRouter. nil = closed.
    @State private var routedPillar: NavRouter.Destination?
    /// Native tab content switches immediately; only the persistent dock animates its selection.
    @State private var selectedTab: Int = 0
    @State private var activitySection: NanashiActivitySection = .sessions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dockIsCompact = false
    @State private var keyboardVisible = false
    @State private var dockContentHeight = NoopColdGlassMetrics.dockCellHeight
        + NoopMetrics.dockInset * 2 + NoopMetrics.space2 * 2
    @State private var dockScroll = EditorialDockScrollTracker()
    /// One `NavigationPath` per tab, indexed by tab tag. Re-tapping the already-active tab pops
    /// that tab's stack to its root (#135) by clearing its path — an animated pop that leaves the
    /// root view alive, so an at-root re-tap keeps scroll position and never re-runs `.task`
    /// (#198; the #197 resetID/`.id()` rebuild reset both). Requires the tab roots' first-hop
    /// links to push `TabRoute`/`MoreDestination` VALUES — closure-destination links bypass the path.
    @State private var tabPaths: [NavigationPath] = Array(repeating: NavigationPath(), count: 5)
    /// One scroll-to-top token per tab. Bumped when the user re-taps the active tab while it's ALREADY
    /// at its root — the other half of the iOS convention #197/#198 left unserved (an at-root re-tap was
    /// a no-op). Threaded into each tab's root via `\.scrollToTopSignal`; ScreenScaffold / LiquidTodayView
    /// scroll to their top anchor when their tab's token changes.
    @State private var scrollTop: [Int] = Array(repeating: 0, count: 5)
    /// Which More-tab groups are expanded (S2). Insights + Body stay open at rest; Data + App collapse to
    /// just their header until tapped. Persisted (#860 item 2): the user's open/closed choice must SURVIVE
    /// leaving and re-entering the More tab (and relaunch), not reset to the seed every visit. Backed by an
    /// `@AppStorage` CSV string (keyed identically to the Android `MoreSectionPrefs`), bridged to a
    /// `Set<String>` through `MoreSectionPrefs` so the section logic below is unchanged.
    @AppStorage(MoreSectionPrefs.storageKey) private var expandedMoreSectionsCSV = MoreSectionPrefs.defaultCSV

    /// V8 liquid redesign is the default Today; the Settings toggle lets a user fall back to the classic
    /// Today if they prefer it (keyed identically to the SettingsView toggle). Default ON.
    @AppStorage("noop.liquidTodayEnabled") private var liquidTodayEnabled = true

    init(repo: Repository, homeScreenQuickActionsEnabled: Bool = true, initialTab: Int = 0) {
        self.repo = repo
        self.initialTab = initialTab
        self.homeScreenQuickActionsEnabled = homeScreenQuickActionsEnabled
        _selectedTab = State(initialValue: min(4, max(0, initialTab)))
    }

    private var presenceIsUncovered: Bool {
        quickAction == nil && !showDevices && routedPillar == nil && !liftSession.isPresented
    }

    private func presenceScene(for tag: Int) -> NanashiPresenceScene {
        switch tag {
        case 0: return .day
        case 1: return .activity
        case 2: return .sleep
        case 4: return .explore
        default: return .general
        }
    }

    /// The Today tab root, honouring the liquid/classic preference.
    @ViewBuilder private var todayTabRoot: some View {
        if liquidTodayEnabled { LiquidTodayView() } else { TodayView() }
    }

    /// Keep one selection binding for the native containers and the source-derived dock.
    /// Re-selecting a tab retains the refresh / pop-to-root / scroll-to-top convention.
    private var nativeTabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { tag in
                if tag == selectedTab {
                    reselectTab(tag)
                } else {
                    selectedTab = tag
                }
            }
        )
    }

    private func reselectTab(_ tag: Int) {
        Task { await repo.refresh() }
        if !tabPaths[tag].isEmpty {
            tabPaths[tag] = NavigationPath()
        } else {
            scrollTop[tag] += 1
        }
    }

    var body: some View {
        // Keep native tab/navigation identity. A single persistent dock overlays the shell rather
        // than being removed and re-created inside each tab during selection.
        TabView(selection: nativeTabSelection) {
            tab(todayTabRoot, "Today", "square.grid.2x2", path: $tabPaths[0], scrollSignal: scrollTop[0], tag: 0).tag(0)
            tab(NanashiActivityView(selection: $activitySection), "Activity", "figure.run", path: $tabPaths[1], scrollSignal: scrollTop[1], tag: 1).tag(1)
            tab(SleepView(), "Sleep", "bed.double", path: $tabPaths[2], scrollSignal: scrollTop[2], tag: 2).tag(2)
            // K3: Coach promoted to a top-level tab (was behind the More list). The sparkles icon
            // matches the More-tab row and the macOS sidebar entry.
            // Conditional on the master switch. The tags stay LITERAL rather than being renumbered when
            // Coach is absent: `tabPaths` and `scrollTop` are indexed by tag, and More stays tag 4 in both
            // shapes, so a wearer's More tab keeps its identity, its navigation path and its scroll
            // position across a flip instead of inheriting Coach's.
            if coachEnabled {
                tab(CoachView(), "Coach", "sparkles", path: $tabPaths[3], scrollSignal: scrollTop[3], tag: 3).tag(3)
            }
            moreTab(path: $tabPaths[4], scrollSignal: scrollTop[4]).tag(4)
        }
        .overlay(alignment: .bottom) {
            if !keyboardVisible { bottomChrome }
        }
        .tint(StrandPalette.accentInk)
        .toolbar(.hidden, for: .tabBar)
        .environment(\.noopDockActiveTab, selectedTab)
        .onPreferenceChange(NoopDockScrollOffsetKey.self) { sample in
            updateDockScroll(sample)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .rootShellBoundary()
        .onChangeCompat(of: selectedTab) { _ in expandDock() }
        .onChangeCompat(of: tabPaths.map(\.count)) { _ in expandDock() }
        .onChangeCompat(of: scrollTop) { _ in expandDock() }
        .onChangeCompat(of: bottomBarAutoHide) { _ in expandDock() }
        .rootShellBoundary()
        .onChangeCompat(of: quickAction) { _ in expandDock() }
        .onChangeCompat(of: showDevices) { _ in expandDock() }
        .onChangeCompat(of: routedPillar) { _ in expandDock() }
        .onChangeCompat(of: liftSession.isPresented) { _ in expandDock() }
        .rootShellBoundary()
        // Switching Coach off while STANDING on it leaves `selectedTab` pointing at a tag no tab claims
        // any more, which renders as an empty tab rather than as an error. Send that wearer to Today, and
        // only in that case, so a flip made from anywhere else does not move them.
        .onChangeCompat(of: coachEnabled) { enabled in
            if !enabled && selectedTab == 3 { selectedTab = 0 }
        }
        .onAppear {
            if !coachEnabled && selectedTab == 3 { selectedTab = 0 }
        }
        .task {
            await repo.refresh()
            // Backup & Sync: on-launch catch-up (see RootView). Detached + utility priority so a
            // 100MB+ whole-DB ZIP never blocks startup; gated on the auto toggle (default OFF). (Must-fix #4.)
            let backupRepo = repo
            Task.detached(priority: .utility) {
                await FolderBackup.catchUpIfDue(checkpoint: { await backupRepo.checkpointForBackup() })
            }
        }
        .rootShellBoundary()
        // Quick-action sheet presents with the calm easing (~0.42s) per the README sheet spec —
        // the easing is applied where `quickAction` is set (see `presentQuickAction`), keeping the
        // animation scoped to the sheet rather than the whole shell.
        .sheet(item: $quickAction) { action in
            quickActionDestination(action)
                .environment(\.noopDockOwnsBottomInset, false)
        }
        // Live's "Manage devices" affordance (and any future cross-screen link to Devices) routes here:
        // present the Devices manager in its own nav stack, the same way the quick-action screens do.
        .sheet(isPresented: $showDevices) {
            devicesScreen
                .environment(\.noopDockOwnsBottomInset, false)
        }
        // v5 pillar deep-links (Insights hub / Lab Book / fused record / Rhythm) present as a sheet in
        // their own nav stack — the same idiom the quick-action + Devices screens use on iPhone.
        .sheet(item: $routedPillar) { dest in
            pillarScreen(dest)
                .environment(\.noopDockOwnsBottomInset, false)
        }
        .rootShellBoundary()
        // Honour a router request: Devices keeps its dedicated sheet; the v5 pillars route through the
        // shared pillar sheet. Cleared so the same tap can fire again later.
        .onChangeCompat(of: router.requestedDestination) { dest in
            switch dest {
            case .devices:
                showDevices = true
                router.requestedDestination = nil
            case .insightsHub, .labBook, .fusedRecord, .rhythm, .alarms:
                routedPillar = dest
                router.requestedDestination = nil
            case .coach:
                // K3: Coach is now a top-level tab (tag 3) — switch to it directly instead of
                // presenting it as a pillar sheet.
                //
                // Guarded on the master switch, because this route is reachable with Coach OFF. A brief
                // notification already sitting in Notification Centre still calls `openCoach()` when it is
                // tapped (StrandApp wires `onCoachBriefTapped` to it), and with no tab claiming tag 3 the
                // wearer would land on a BLANK tab. Dropping the request leaves them where they were, which
                // is the honest answer for a feature that is switched off.
                guard coachEnabled else {
                    router.requestedDestination = nil
                    break
                }
                selectedTab = 3
                router.requestedDestination = nil
            case .trends:
                // Preserve the legacy route: explicitly select Trends inside Activity.
                activitySection = .trends
                tabPaths[1] = NavigationPath()
                selectedTab = 1
                router.requestedDestination = nil
            case .activeWorkout:
                // The Today active-workout indicator opens Live through the quick-action Live sheet; once
                // it's up, LiveView consumes the one-shot `presentActiveWorkout` flag and presents the
                // in-exercise screen. Calm sheet easing, matching the other quick-action presents.
                withAnimation(Self.sheetEase) { quickAction = .live }
                router.requestedDestination = nil
            case .liveSession:
                // Live Sessions is presented from Today's own Start entry (a cover, not a routed sheet),
                // so a deep-link lands on the Today tab where that entry lives.
                selectedTab = 0
                router.requestedDestination = nil
            case .journal:
                // The #627 Today journal widget opens the journal through the quick-action Journal sheet
                // (InsightsView), matching the FAB's "Log journal" action. Calm sheet easing.
                withAnimation(Self.sheetEase) { quickAction = .journal }
                router.requestedDestination = nil
            case nil:
                break
            }
        }
        // A screen's top-bar "+" routes here: open the quick-action sheet, then clear the flag.
        .onChangeCompat(of: router.quickActionsRequested) { req in
            if req {
                withAnimation(Self.sheetEase) { quickAction = .menu }
                router.quickActionsRequested = false
            }
        }
        // A cold-launch selection is already pending when this shell appears; a warm selection arrives
        // through the change callback. Both route through the same screens as the centre FAB.
        .onAppear {
            presentPendingHomeScreenQuickActionIfPossible()
        }
        .onChangeCompat(of: homeScreenQuickActions.pendingAction) { _ in
            presentPendingHomeScreenQuickActionIfPossible()
        }
        .onChangeCompat(of: homeScreenQuickActionsEnabled) { _ in
            presentPendingHomeScreenQuickActionIfPossible()
        }
        .rootShellBoundary()
        // The running gym session, reachable from ANY tab. It sits above the tab bar rather than
        // inside the Lift Log screen, because a workout outlives whichever screen you wandered to —
        // and because swiping the sheet away must minimise the session, not end it.
        // A session left running by a previous launch is back before this view exists
        // (`LiftSessionController.resumeSaved`, from `StrandiOSApp.init`), as the BAR — not as a sheet
        // thrown in the user's face; they open it when they want it.
        .sheet(isPresented: $liftSession.isPresented) {
            LiftSessionView { }
        }
    }

    private var bottomChrome: some View {
        VStack(spacing: NoopMetrics.space2) {
            if liftSession.isActive {
                LiftSessionBar()
                    .padding(.horizontal, NoopMetrics.screenHPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            NanashiDock(selectedTab: selectedTab, coachEnabled: coachEnabled, isCompact: dockIsCompact) { tag in
                if tag == selectedTab { reselectTab(tag) }
                else { selectedTab = tag }
            }
        }
        .animation(reduceMotion ? nil : StrandMotion.interactive, value: liftSession.isActive)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: NanashiDockHeightKey.self, value: geometry.size.height)
            }
        }
        .onPreferenceChange(NanashiDockHeightKey.self) { height in
            guard height.isFinite, height > 0 else { return }
            let measuredHeight = height.rounded(.up)
            guard measuredHeight != dockContentHeight else { return }
            // Layout feedback must not inherit the dock's spring or tiny material geometry changes.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { dockContentHeight = measuredHeight }
        }
    }

    private func updateDockScroll(_ sample: NoopDockScrollSample?) {
        guard #available(iOS 26.0, *), bottomBarAutoHide, let sample else { return }
        guard let compact = dockScroll.compactState(for: sample), compact != dockIsCompact else { return }
        dockIsCompact = compact
    }

    private func expandDock() {
        dockScroll.reset()
        guard dockIsCompact else { return }
        dockIsCompact = false
    }

    /// Mandatory launch gates defer an external action. Once the shell is available, an explicit Home
    /// Screen choice supersedes any ordinary shell sheet; choosing the already-open destination simply
    /// consumes the request and leaves that screen in place.
    private func presentPendingHomeScreenQuickActionIfPossible() {
        guard homeScreenQuickActionsEnabled,
              let action = homeScreenQuickActions.pendingAction else { return }

        let destination: QuickAction = switch action {
        case .liveHeartRate: .live
        case .startWorkout: .workout
        case .logJournal: .journal
        case .breathe: .breathe
        }
        homeScreenQuickActions.consume(action)
        withAnimation(Self.sheetEase) {
            showDevices = false
            routedPillar = nil
            quickAction = destination
        }
    }

    /// A routed v5 pillar screen wrapped in its own nav stack + Done button (mirrors `quickScreen`).
    @ViewBuilder
    private func pillarScreen(_ dest: NavRouter.Destination) -> some View {
        NavigationStack {
            Group {
                switch dest {
                case .insightsHub: InsightsHubView()
                case .labBook: LabBookView()
                case .fusedRecord: FusedRecordHost()
                case .rhythm: RhythmHost(onClose: { routedPillar = nil })
                case .devices: DevicesView()
                // .trends is never presented as a pillar sheet on iPhone (it's a primary tab — the
                // requestedDestination handler switches `selectedTab` instead), but the switch must stay
                // exhaustive. Fall back to Trends inside the sheet host if it ever arrives here.
                case .trends: TrendsView()
                // .activeWorkout routes through the quick-action Live sheet (handled above); this keeps the
                // switch exhaustive and falls back to Live if it ever reaches the pillar host.
                case .activeWorkout: LiveView()
                // .liveSession routes to the Today tab (handled above — its Start entry owns the cover);
                // this keeps the switch exhaustive and falls back to Today if it ever reaches the host.
                case .liveSession: LiquidTodayView()
                // .journal opens through the quick-action Journal sheet (handled above); this keeps the
                // switch exhaustive and falls back to the journal's Insights host if it ever reaches here.
                case .journal: InsightsView()
                // .coach switches to the Coach tab (handled above — the morning-brief tap-through and the
                // #1862 launcher both arrive that way, the launcher's question riding on
                // `AICoachEngine.pendingPrompt`); this keeps the switch exhaustive and falls back to Coach if
                // it ever reaches the host.
                case .coach: CoachView()
                case .alarms: SmartAlarmView()
                }
            }
            // The Trends/Today fallbacks above emit TabRoute value pushes (#198), which need a
            // destination registered in THIS sheet's stack to resolve.
            .tabRouteDestinations()
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            // #1027: same fix as quickScreen — the pillar screens draw the full-bleed liquid sky, so a
            // transparent nav bar keeps it edge-to-edge instead of an opaque band clipping the top on scroll.
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { routedPillar = nil }
                        .foregroundStyle(StrandPalette.accentInk)
                }
            }
        }
    }

    /// Calm-easing curve (cubic-bezier(0.22,1,0.36,1)) at the README sheet-present duration.
    private static let sheetEase = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)

    // MARK: - Quick-action sheet

    /// Routes a chosen quick action to the existing screen, or shows the action menu itself.
    @ViewBuilder
    private func quickActionDestination(_ action: QuickAction) -> some View {
        switch action {
        case .menu:
            QuickActionSheet { picked in
                // Swap the menu for the chosen destination on the next runloop so the sheet
                // re-presents cleanly (avoids dismiss/re-present races). Calm easing on re-present.
                quickAction = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(Self.sheetEase) { quickAction = picked }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        case .live:
            quickScreen(LiveView())
        case .workout:
            quickScreen(WorkoutsView())
        case .journal:
            quickScreen(InsightsView())
        case .breathe:
            quickScreen(BreathingView())
        }
    }

    /// Wraps a routed quick-action screen in its own nav stack so it has a title bar + the
    /// shared surface background, matching how the More-tab links present these same views.
    private func quickScreen<V: View>(_ view: V) -> some View {
        NavigationStack {
            view
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                // #1027: these screens draw a full-bleed liquid sky (ScreenScaffold topBackground) that runs
                // edge-to-edge under a transparent bar — exactly how the tab roots present it. An OPAQUE
                // surfaceBase toolbar background sat on top of that sky and, as the content scrolled up, its
                // extended status-bar band CLIPPED the sky + the in-content header ("Live Body Console").
                // Hiding the bar background lets the sky stay continuous under the floating Done button.
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { quickAction = nil }
                            .foregroundStyle(StrandPalette.accentInk)
                    }
                }
        }
    }

    /// The Devices manager wrapped in its own nav stack + Done button (mirrors `quickScreen`, but
    /// dismisses the dedicated `showDevices` sheet rather than the quick-action item).
    private var devicesScreen: some View {
        NavigationStack {
            DevicesView()
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                // #1027: same fix as quickScreen — Devices draws the full-bleed liquid sky, so a transparent
                // nav bar keeps it edge-to-edge instead of an opaque band clipping the top on scroll.
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showDevices = false }
                            .foregroundStyle(StrandPalette.accentInk)
                    }
                }
        }
    }

    private func tab<V: View>(_ view: V, _ title: LocalizedStringKey, _ icon: String,
                              path: Binding<NavigationPath>, scrollSignal: Int, tag: Int) -> some View {
        // Each primary tab gets its OWN NavigationStack so the in-content NavigationLinks (e.g. the Today
        // dashboard card rows) both navigate AND render opaque. An ORPHANED NavigationLink (no
        // NavigationStack ancestor) renders its whole label in a disabled/translucent state — that was
        // washing the Today cards over the hero scene and dimming their text to grey (2026-06-23).
        // The root view hides the system nav bar (each screen draws its own in-content header); pushed
        // detail screens get their own nav bar + back button. The stack is bound to the tab's path so a
        // re-tap of the active tab can pop it to the root (#135/#198); the roots' first-hop links push
        // TabRoute values, registered here ONCE per stack (a double registration double-pushes, #38).
        // Snapshot DynamicProperty values before entering the factory. Reading shell State from
        // inside its body would subscribe the boundary to unrelated tab/chrome changes again.
        let revision = tabRevision(tag: tag, path: path.wrappedValue, scrollSignal: scrollSignal)
        let scene = presenceScene(for: tag)
        return PresentationValueBoundary(revision: revision) {
        NavigationStack(path: path) {
            view
                .environment(\.nanashiPresenceScene, scene)
                .environment(\.nanashiPresenceIsActive,
                             revision.isSelected && tag != 3 && revision.path.isEmpty && revision.presenceIsUncovered)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if tag == 3 && !revision.keyboardVisible {
                        Color.clear.frame(height: revision.dockContentHeight)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .tabRouteDestinations()
        }
        // UIKit tab/navigation boundaries can discard a safe-area reservation. Non-Coach pages
        // therefore scroll behind the shell overlay and reserve its measured height in their CONTENT.
        // Coach keeps its proven inner reservation beside the composer; never reserve it twice.
        // Drive this tab's root scroll-to-top on an at-root re-tap (#198 follow-up); read by ScreenScaffold
        // / LiquidTodayView inside. Only THIS tab's token changes on its reselect, so the others don't scroll.
        .environment(\.scrollToTopSignal, revision.scrollSignal)
        .environment(\.presentationIsActive, revision.isSelected)
        .environment(\.noopDockScrollTrackingTag, tag)
        .environment(\.noopDockOwnsBottomInset, tag == 3)
        .environment(\.noopDockContentClearance, tag == 3 ? nil : (revision.keyboardVisible ? 0 : revision.dockContentHeight))
        .environment(\.nanashiPresenceIsActive, revision.isSelected && tag != 3 && revision.presenceIsUncovered)
        .toolbar(.hidden, for: .tabBar)
        }
        .equatable()
        .tabItem { Label(title, systemImage: icon) }
    }

    // The command index retains route-valued links and the More tab's bound navigation path.
    private func moreTab(path: Binding<NavigationPath>, scrollSignal: Int) -> some View {
        let revision = tabRevision(tag: 4, path: path.wrappedValue, scrollSignal: scrollSignal)
        let expandedSections = $expandedMoreSectionsCSV
        let repository = repo
        return PresentationValueBoundary(revision: revision) {
        NavigationStack(path: path) {
            ScreenScaffold(title: "Explore", subtitle: "Everything else, one tap away",
                           onRefresh: { await repository.refresh() }, topBackground: liquidScaffoldSky()) {
                MoreCommandIndex(expandedSectionsCSV: expandedSections) { action in
                    withAnimation(revision.reduceMotion ? nil : Self.sheetEase) { quickAction = action }
                }
            }
            .environment(\.nanashiPresenceScene, .explore)
            .environment(\.nanashiPresenceIsActive,
                         revision.isSelected && revision.path.isEmpty && revision.presenceIsUncovered)
            // The rows push MoreDestination VALUES so a re-tap of the More tab can pop them off the
            // bound path (#135/#198). Each destination keeps the per-screen wrapper the rows used to
            // apply inline (surfaceBase background, inline title bar, hidden bar background):
            // #1027 — a pushed sky-scaffold screen (Live, Workouts, Health, …) draws a full-bleed liquid
            // sky; an opaque surfaceBase nav-bar band sat over it and clipped the top on scroll. A hidden
            // bar background keeps the sky edge-to-edge. On the flat (no-sky) screens this is visually
            // identical at rest — the destination's own surfaceBase background shows through the bar.
            .navigationDestination(for: MoreDestination.self) { route in
                route.destination
                    .environment(\.nanashiPresenceScene, .general)
                    .environment(\.nanashiPresenceIsActive, revision.isSelected && revision.presenceIsUncovered)
                    .background(StrandPalette.surfaceBase.ignoresSafeArea())
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
        }
        // Scroll the More index to the top on an at-root re-tap (#198 follow-up); read by its ScreenScaffold.
        .environment(\.scrollToTopSignal, revision.scrollSignal)
        .environment(\.presentationIsActive, revision.isSelected)
        .environment(\.noopDockScrollTrackingTag, 4)
        .environment(\.noopDockOwnsBottomInset, false)
        .environment(\.noopDockContentClearance, revision.keyboardVisible ? 0 : revision.dockContentHeight)
        .environment(\.nanashiPresenceIsActive, revision.isSelected && revision.presenceIsUncovered)
        .toolbar(.hidden, for: .tabBar)
        }
        .equatable()
        .tabItem { Label("Explore", systemImage: "square.grid.3x3") }
    }

    /// A tab only follows its own route, active state and layout. Before this boundary a dock tap
    /// rebuilt all five navigation factories, including the invisible history/chart roots.
    private func tabRevision(tag: Int, path: NavigationPath, scrollSignal: Int) -> TabRevision {
        TabRevision(path: path, scrollSignal: scrollSignal, isSelected: selectedTab == tag,
                    presenceIsUncovered: presenceIsUncovered, keyboardVisible: keyboardVisible,
                    dockContentHeight: dockContentHeight, reduceMotion: reduceMotion,
                    liquidTodayEnabled: tag == 0 && liquidTodayEnabled,
                    activitySection: tag == 1 ? activitySection : nil,
                    expandedMoreSections: tag == 4 ? expandedMoreSectionsCSV : "")
    }

    private struct TabRevision: Equatable {
        let path: NavigationPath
        let scrollSignal: Int
        let isSelected: Bool
        let presenceIsUncovered: Bool
        let keyboardVisible: Bool
        let dockContentHeight: CGFloat
        let reduceMotion: Bool
        let liquidTodayEnabled: Bool
        let activitySection: NanashiActivitySection?
        let expandedMoreSections: String
    }

}

/// One long-lived glass rail, adapted from 21st Pill Morph Tabs (7878).
/// Its namespace and spring stay local: screen layout, charts and safe areas never join the animation.
private struct NanashiDock: View {
    let selectedTab: Int
    let coachEnabled: Bool
    let isCompact: Bool
    let onSelect: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var dockSelection

    /// Pill Morph Tabs (21st 7878, ruixen.ui): translucent rail and a spring-driven
    /// glass selection. Dock Nav (19177) supplies the icon-led navigation structure.
    /// Labels stay visible on touch; the five targets never change width.
    var body: some View {
        HStack(spacing: NoopMetrics.dockGap) {
            dockItem(0, title: "Day", icon: "square.grid.2x2")
            dockItem(2, title: "Sleep", icon: "moon")
            dockItem(1, title: "Activity", icon: "figure.run")
            if coachEnabled { dockItem(3, title: "Coach", icon: "sparkles") }
            dockItem(4, title: "Explore", icon: "square.grid.3x3")
        }
        .padding(isCompact ? NoopMetrics.space1 : NoopMetrics.dockInset)
        .background(NoopPanelSurface(cornerRadius: NoopMetrics.space8, elevated: true))
        .frame(maxWidth: NoopColdGlassMetrics.dockWidth)
        .padding(.horizontal, NoopMetrics.screenHPadding)
        .padding(.vertical, NoopMetrics.space2)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, StrandPalette.surfaceBase],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: NoopMetrics.dockScrimHeight)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .animation(reduceMotion ? nil : StrandMotion.interactive, value: selectedTab)
        .animation(reduceMotion ? nil : StrandMotion.interactive, value: isCompact)
        .accessibilityElement(children: .contain)
    }

    private func dockItem(_ tag: Int, title: LocalizedStringKey, icon: String) -> some View {
        let selected = selectedTab == tag
        return Button {
            onSelect(tag)
        } label: {
            VStack(spacing: NoopMetrics.space1) {
                Image(systemName: icon)
                    .font(StrandFont.number(NoopMetrics.dockIconSize, weight: selected ? .semibold : .regular))
                    .frame(height: NoopMetrics.dockIconSize)
                Text(title).font(StrandFont.overline)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .foregroundStyle(selected ? StrandPalette.textPrimary : StrandPalette.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: isCompact ? NoopButtonMetrics.minHitTarget : NoopColdGlassMetrics.dockCellHeight)
            .contentShape(RoundedRectangle(cornerRadius: NoopMetrics.space6))
            .background {
                if selected {
                    NoopGlassControlSurface(cornerRadius: NoopMetrics.space6, isSelected: true)
                        .matchedGeometryEffect(id: "coldglass.dock.selection", in: dockSelection)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("noop.dock.\(tag)")
        .accessibilityShowsLargeContentViewer { Label(title, systemImage: icon) }
    }

}

private struct NanashiDockHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Local navigation search adapted from Command Menu with Global Search (27378).
/// Groups use the existing route index; filtering never writes the user's expansion choices.
private struct MoreCommandIndex: View {
    @Binding var expandedSectionsCSV: String
    let onQuickAction: (QuickAction) -> Void
    @State private var query = ""
    @State private var filter: MoreRouteGroup?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFiltering: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filter != nil }
    private var matches: [MoreRouteEntry] {
        MoreRouteEntry.all.filter { entry in
            (filter == nil || filter == entry.group) &&
                moreSearchMatches(query: query, title: entry.title, group: entry.group.title, sourceTitle: entry.titleKey)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            MoreQuickCommand(onPick: onQuickAction)
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                NoopLiquidGlassSearchField(text: $query, prompt: String(localized: "Search screens"))
                    .accessibilityIdentifier("noop.more.search")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NoopMetrics.space2) {
                        filterPill(nil, title: String(localized: "All"))
                        ForEach(MoreRouteGroup.allCases) { group in
                            filterPill(group, title: group.title)
                        }
                    }
                }
                .scrollBounceBasedOnSizeCompat(axes: .horizontal)
            }
            if matches.isEmpty {
                VStack(spacing: NoopMetrics.space3) {
                    Image(systemName: "magnifyingglass")
                        .font(StrandFont.title2).foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                    Text("No matching screens").font(StrandFont.headline)
                    Text("Try another word or group.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    Button("Clear filters") { query = ""; filter = nil }
                        .buttonStyle(NoopButtonStyle(.secondary))
                        .accessibilityIdentifier("noop.more.clearFilters")
                }
                .padding(NoopMetrics.space6)
                .frame(maxWidth: .infinity)
                .background(NoopPanelSurface())
                .accessibilityIdentifier("noop.more.empty")
            } else {
                ForEach(MoreRouteGroup.allCases) { group in
                    let entries = matches.filter { $0.group == group }
                    if !entries.isEmpty { routeGroup(group, entries: entries) }
                }
            }
        }
    }

    private func filterPill(_ group: MoreRouteGroup?, title: String) -> some View {
        let selected = filter == group
        return Button { filter = group } label: {
            Text(title).font(StrandFont.footnote.weight(.semibold))
                .foregroundStyle(selected ? StrandPalette.onAccent : StrandPalette.textSecondary)
                .padding(.horizontal, NoopMetrics.space3)
                .frame(minHeight: NoopButtonMetrics.minHitTarget)
                .background(selected ? StrandPalette.accent : StrandPalette.surfaceInset, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? StrandPalette.accent : StrandPalette.hairline,
                                               lineWidth: NoopMetrics.hairlineWidth))
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("noop.more.filter.\(group?.rawValue.lowercased() ?? "all")")
    }

    private func routeGroup(_ group: MoreRouteGroup, entries: [MoreRouteEntry]) -> some View {
        let persistedOpen = MoreSectionPrefs.decode(expandedSectionsCSV).contains(group.rawValue)
        let shown = isFiltering || persistedOpen
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            if isFiltering {
                Text(group.title).strandOverline()
                    .accessibilityAddTraits(.isHeader)
            } else {
                Button {
                    withAnimation(reduceMotion ? nil : StrandMotion.interactive) {
                        var expanded = MoreSectionPrefs.decode(expandedSectionsCSV)
                        if persistedOpen { expanded.remove(group.rawValue) }
                        else { expanded.insert(group.rawValue) }
                        expandedSectionsCSV = MoreSectionPrefs.encode(expanded)
                    }
                } label: {
                    HStack(spacing: NoopMetrics.space2) {
                        Text(group.title).strandOverline()
                        Spacer(minLength: NoopMetrics.space2)
                        Image(systemName: "chevron.down")
                            .font(StrandFont.footnote.weight(.semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .rotationEffect(.degrees(persistedOpen ? 0 : -90))
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: NoopButtonMetrics.minHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(group.title)
                .accessibilityValue(persistedOpen ? String(localized: "Expanded") : String(localized: "Collapsed"))
            }
            if shown {
                NoopCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            MoreRow(entry.title, entry.icon, entry.route, query: query)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                }
            }
        }
    }
}

private enum MoreRouteGroup: String, CaseIterable, Identifiable {
    case insights = "Insights", body = "Body", data = "Data", app = "App"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .insights: return String(localized: "Insights")
        case .body: return String(localized: "Activity")
        case .data: return String(localized: "Data Sources")
        case .app: return String(localized: "Settings")
        }
    }
}

private struct MoreRouteEntry: Identifiable {
    let titleKey: String
    let icon: String
    let route: MoreDestination
    let group: MoreRouteGroup
    var id: MoreDestination { route }
    var title: String { String(localized: String.LocalizationValue(titleKey)) }

    static let all: [MoreRouteEntry] = [
        .init(titleKey: "What Moves You", icon: "wand.and.sparkles", route: .insightsHub, group: .insights),
        .init(titleKey: "Intelligence", icon: "brain.head.profile", route: .intelligence, group: .insights),
        .init(titleKey: "Insights", icon: "lightbulb.fill", route: .insights, group: .insights),
        .init(titleKey: "Explore", icon: "square.grid.2x2.fill", route: .explore, group: .insights),
        .init(titleKey: "Compare", icon: "rectangle.split.2x1.fill", route: .compare, group: .insights),
        .init(titleKey: "Live", icon: "waveform.path.ecg", route: .live, group: .body),
        .init(titleKey: "Workouts", icon: "figure.run", route: .workouts, group: .body),
        .init(titleKey: "Lift Log", icon: "dumbbell.fill", route: .liftLog, group: .body),
        .init(titleKey: "Health", icon: "heart.text.square.fill", route: .health, group: .body),
        .init(titleKey: "Lab Book", icon: "books.vertical.fill", route: .labBook, group: .body),
        .init(titleKey: "Stress", icon: "bolt.heart.fill", route: .stress, group: .body),
        .init(titleKey: "Breathe", icon: "wind", route: .breathe, group: .body),
        .init(titleKey: "Intervals", icon: "timer", route: .intervals, group: .body),
        .init(titleKey: "Rhythm", icon: "waveform.path", route: .rhythm, group: .body),
        .init(titleKey: "Devices", icon: "sensor.tag.radiowaves.forward", route: .devices, group: .data),
        .init(titleKey: "Your Data, Fused", icon: "square.stack.3d.up.fill", route: .fusedRecord, group: .data),
        .init(titleKey: "Apple Health", icon: "heart.fill", route: .appleHealth, group: .data),
        .init(titleKey: "Mi Band", icon: "figure.walk.motion", route: .miBand, group: .data),
        .init(titleKey: "Data Sources", icon: "externaldrive.fill", route: .dataSources, group: .data),
        .init(titleKey: "Backup & Sync", icon: "externaldrive.fill.badge.icloud", route: .backupSync, group: .data),
        .init(titleKey: "Shortcuts Export", icon: "square.and.arrow.up.fill", route: .shortcutsExport, group: .data),
        .init(titleKey: "NOOP Limitations", icon: "list.bullet.rectangle", route: .noopLimitations, group: .data),
        .init(titleKey: "Alarms", icon: "alarm.fill", route: .alarms, group: .app),
        .init(titleKey: "Automations", icon: "wand.and.stars", route: .automations, group: .app),
        .init(titleKey: "Test Centre", icon: "stethoscope", route: .testCentre, group: .app),
        .init(titleKey: "Siri & Shortcuts", icon: "mic.fill", route: .siriShortcuts, group: .app),
        .init(titleKey: "Power saving", icon: "battery.25", route: .powerSaving, group: .app),
        .init(titleKey: "Settings", icon: "gearshape.fill", route: .settings, group: .app)
    ]
}

/// Match localized and source names so language changes do not make a route unfindable.
private func moreSearchMatches(query: String, title: String, group: String, sourceTitle: String) -> Bool {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    guard !needle.isEmpty else { return true }
    return "\(title) \(group) \(sourceTitle)"
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .contains(needle)
}

/// Tap-expanded command pill and action grid adapted from Command Menu (23173).
/// Real destinations replace the source's demo links and optional rotating status.
private struct MoreQuickCommand: View {
    let onPick: (QuickAction) -> Void
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var commandSelection
    @State private var selectedAction: QuickAction?

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? NoopMetrics.space3 : 0) {
            Button {
                withAnimation(reduceMotion ? nil : StrandMotion.interactive) { expanded.toggle() }
            } label: {
                HStack(spacing: NoopMetrics.space3) {
                    Image(systemName: "command")
                        .font(StrandFont.headline).foregroundStyle(StrandPalette.accentInk)
                    Text("Quick actions").font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    if expanded { Spacer(minLength: NoopMetrics.space2) }
                    Image(systemName: expanded ? "xmark" : "chevron.down")
                        .font(StrandFont.caption.weight(.semibold)).foregroundStyle(StrandPalette.textSecondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, NoopMetrics.space4)
                .frame(minHeight: NoopMetrics.controlHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? String(localized: "Expanded") : String(localized: "Collapsed"))
            .accessibilityIdentifier("noop.more.quickActions")
            .keyboardShortcut("k", modifiers: .command)
            if expanded {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: NoopMetrics.space2) {
                    action(.live, title: "Live HR", icon: "waveform.path.ecg")
                    action(.workout, title: "Start workout", icon: "figure.run")
                    action(.journal, title: "Log journal", icon: "square.and.pencil")
                    action(.breathe, title: "Breathe", icon: "wind")
                }
                .padding(.horizontal, NoopMetrics.space3)
                .padding(.bottom, NoopMetrics.space3)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: expanded ? .infinity : nil, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: expanded ? NoopMetrics.cardRadius : NoopMetrics.pillRadius))
        .animation(reduceMotion ? nil : StrandMotion.interactive, value: expanded)
    }

    private func action(_ action: QuickAction, title: LocalizedStringKey, icon: String) -> some View {
        Button {
            selectedAction = action
            expanded = false
            onPick(action)
        } label: {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Image(systemName: icon).font(StrandFont.headline).foregroundStyle(StrandPalette.accentInk)
                Text(title).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: NoopMetrics.controlHeight, alignment: .leading)
            .padding(NoopMetrics.space3)
            .background {
                if selectedAction == action {
                    RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius)
                        .fill(StrandPalette.accentMuted)
                        .matchedGeometryEffect(id: "more.command.selection", in: commandSelection)
                } else {
                    RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius).fill(StrandPalette.surfaceInset)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius))
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityIdentifier("noop.more.quickAction.\(action.rawValue)")
        .onHover { hovering in selectedAction = hovering ? action : nil }
    }
}


/// Every screen the More index links to, as a `Hashable` value the tab's `NavigationPath` can carry
/// (#198): a closure-destination push would bypass the path and be un-poppable on tab re-tap. The
/// per-screen chrome the old inline links applied lives at the single `navigationDestination(for:)`
/// registration in `moreTab`.
private enum MoreDestination: Hashable {
    case insightsHub, intelligence, coach, insights, explore, compare
    case live, workouts, liftLog, health, labBook, stress, breathe, intervals, rhythm
    case fusedRecord, appleHealth, miBand, dataSources, backupSync, shortcutsExport, noopLimitations, devices
    case alarms, automations, testCentre, siriShortcuts, powerSaving, settings

    @ViewBuilder var destination: some View {
        switch self {
        case .insightsHub:     InsightsHubView()
        case .intelligence:    IntelligenceView()
        case .coach:           CoachView()
        case .insights:        InsightsView()
        case .explore:         MetricExplorerView()
        case .compare:         CompareView()
        case .live:            LiveView()
        case .workouts:        WorkoutsView()
        case .liftLog:         LiftLogView()
        case .health:          HealthView()
        case .labBook:         LabBookView()
        case .stress:          StressView()
        case .breathe:         BreathingView()
        case .intervals:       IntervalTimerView()
        case .rhythm:          RhythmHost()
        case .devices:         DevicesView()
        case .fusedRecord:     FusedRecordHost()
        case .appleHealth:     AppleHealthView()
        case .miBand:          XiaomiBandView()
        case .dataSources:     DataSourcesView()
        case .noopLimitations: NoopLimitationsView()
        case .backupSync:      BackupSyncView()
        case .shortcutsExport: ShortcutExportSettingsView()
        case .alarms:          SmartAlarmView()
        case .automations:     AutomationsView()
        case .testCentre:      TestCentreView()
        case .siriShortcuts:   SiriShortcutsSettingsView()
        case .powerSaving:     PowerSavingView()
        case .settings:        SettingsView()
        }
    }
}


/// One tappable destination row in the More index. A `NavigationLink` whose label is the standard app row:
/// the SF Symbol icon tinted `StrandPalette.accent`, the title in the body text colour, a `Spacer`, and a
/// trailing `chevron.right` in `textTertiary`. ~44pt min height + the card's row insets keep the whole row a
/// comfortable tap target.
private struct MoreRow: View {
    let title: String
    let icon: String
    let route: MoreDestination

    let query: String

    init(_ title: String, _ icon: String, _ route: MoreDestination, query: String = "") {
        self.title = title; self.icon = icon; self.route = route; self.query = query
    }

    private var titleText: Text {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty,
              let match = title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(title)
        }
        return Text(String(title[..<match.lowerBound])) +
            Text(String(title[match])).foregroundColor(StrandPalette.accentInk).bold() +
            Text(String(title[match.upperBound...]))
    }

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: NoopMetrics.space3) {
                Image(systemName: icon)
                    .font(StrandFont.subhead.weight(.medium))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .frame(width: NoopMetrics.compactControlSize, height: NoopMetrics.compactControlSize)
                    .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: NoopMetrics.space2))
                    .overlay(RoundedRectangle(cornerRadius: NoopMetrics.space2)
                        .strokeBorder(StrandPalette.hairline, lineWidth: NoopMetrics.hairlineWidth))
                    .accessibilityHidden(true)
                titleText.font(StrandFont.subhead.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: NoopMetrics.space2)
                Image(systemName: "chevron.right").font(StrandFont.footnote.weight(.semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, NoopMetrics.cardPadding)
            .padding(.vertical, NoopMetrics.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(StrandPalette.hairline).frame(height: NoopMetrics.hairlineWidth)
                    .padding(.leading, NoopMetrics.cardPadding + NoopMetrics.compactControlSize + NoopMetrics.space3)
            }
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityIdentifier("noop.more.route.\(String(describing: route))")
    }
}

/// A small scroll-direction accumulator; it owns no timer and publishes only a dock state change.
private final class EditorialDockScrollTracker {
    private var screen: UUID?
    private var lastOffset: CGFloat?
    private var travel: CGFloat = 0

    func reset() {
        screen = nil
        lastOffset = nil
        travel = 0
    }

    func compactState(for sample: NoopDockScrollSample) -> Bool? {
        if screen != sample.screen {
            screen = sample.screen
            lastOffset = sample.offset
            travel = 0
            return false
        }
        let previous = lastOffset
        lastOffset = sample.offset
        if sample.offset >= -NoopMetrics.space5 {
            travel = 0
            return false
        }
        guard let previous else { return nil }
        let delta = sample.offset - previous
        guard delta != 0 else { return nil }
        if (travel < 0) != (delta < 0) { travel = delta }
        else { travel += delta }
        guard abs(travel) >= NoopMetrics.space4 else { return nil }
        let compact = travel < 0
        travel = 0
        return compact
    }
}

// MARK: - Quick actions (centre FAB)

/// The destinations the centre FAB can present. `.menu` is the action sheet itself; the rest
/// route to existing screens. `Identifiable` so it drives `.sheet(item:)`.
private enum QuickAction: Int, Identifiable {
    case menu, live, workout, journal, breathe
    var id: Int { rawValue }
}

/// The bottom sheet of quick actions presented by the centre FAB. Spec bottom sheet: surfaceOverlay
/// fill, gold hairline top edge, grab handle, three flat action rows that route to existing screens.
private struct QuickActionSheet: View {
    /// Called with the picked destination (the host swaps the menu for that screen).
    let onPick: (QuickAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space6) {
            Text("QUICK ACTIONS").font(StrandFont.overline)
                .tracking(StrandFont.overlineTracking).foregroundStyle(StrandPalette.textTertiary)
            VStack(spacing: NoopMetrics.space2) {
                row("Live HR", icon: "waveform.path.ecg", tint: StrandPalette.metricRose) { onPick(.live) }
                row("Start workout", icon: "figure.run", tint: StrandPalette.effortColor) { onPick(.workout) }
                row("Log journal", icon: "square.and.pencil", tint: StrandPalette.accent) { onPick(.journal) }
                row("Breathe", icon: "wind", tint: StrandPalette.restColor) { onPick(.breathe) }
            }
            Spacer(minLength: 0)
        }
        .padding(NoopMetrics.space6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
    }

    /// Quiet icon-tile rows retain the source Preferences Card hierarchy (30553).
    private func row(_ title: LocalizedStringKey, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: NoopMetrics.space3) {
                Image(systemName: icon).font(StrandFont.headline).foregroundStyle(tint)
                    .frame(width: NoopMetrics.controlHeight, height: NoopMetrics.controlHeight)
                    .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: NoopMetrics.space3))
                Text(title).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: NoopMetrics.space2)
                Image(systemName: "chevron.right").font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(NoopMetrics.space3)
            .background(NoopPanelSurface(cornerRadius: NoopVisualStyle.compactRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(LiquidPressStyle())
    }
}

#endif

/// #1841: apply the iOS 26 tab-bar minimise behaviour, doing nothing on older systems.
///
/// The availability branch is deliberately the ONLY branch. `RootTabView` already documents what happens
/// when a condition that flips at runtime wraps this `TabView`: #519 put two states in separate
/// `_ConditionalContent` branches, and every navigation rebuilt the whole subtree, resetting `@State`
/// inside the tab roots — scroll offsets, chart ranges, expanded sections.
///
/// So the preference must NOT select between branches. It selects the modifier's ARGUMENT, while the
/// availability check — fixed for the life of the process — is what picks a branch. Toggling the setting
/// changes a value, never the view's identity.
extension View {
    @ViewBuilder
    func noopTabBarAutoHide(_ enabled: Bool) -> some View {
        if #available(iOS 26.0, *) {
            // `.onScrollDown` minimises to a pill on downward scroll; `.never` pins it fully visible.
            self.tabBarMinimizeBehavior(enabled ? .onScrollDown : .never)
        } else {
            self
        }
    }
}
