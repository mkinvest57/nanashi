import SwiftUI
import StrandDesign

private struct NanashiPresenceEnvironmentKey: EnvironmentKey {
    static let defaultValue: NanashiPresenceEngine? = nil
}

private struct NanashiPresenceSceneKey: EnvironmentKey {
    static let defaultValue: NanashiPresenceScene = .general
}

private struct NanashiPresenceActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var nanashiPresence: NanashiPresenceEngine? {
        get { self[NanashiPresenceEnvironmentKey.self] }
        set { self[NanashiPresenceEnvironmentKey.self] = newValue }
    }

    var nanashiPresenceScene: NanashiPresenceScene {
        get { self[NanashiPresenceSceneKey.self] }
        set { self[NanashiPresenceSceneKey.self] = newValue }
    }

    var nanashiPresenceIsActive: Bool {
        get { self[NanashiPresenceActiveKey.self] }
        set { self[NanashiPresenceActiveKey.self] = newValue }
    }
}

/// Inline Announcement Banner (21st 23625, cnippet.dev): icon/title, description and dismissal.
/// Native glass and a 44-point close target replace the web alert styling; no floating assistant.
struct NanashiAside: View {
    var scene: NanashiPresenceScene? = nil
    @Environment(\.nanashiPresence) private var presence
    @Environment(\.nanashiPresenceScene) private var inheritedScene
    @Environment(\.nanashiPresenceIsActive) private var active

    var body: some View {
        if let presence {
            NanashiPresenceHost(engine: presence, scene: scene ?? inheritedScene, active: active)
        }
    }
}

private struct NanashiPresenceHost: View {
    @ObservedObject var engine: NanashiPresenceEngine
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter
    let scene: NanashiPresenceScene
    let active: Bool

    var body: some View {
        Group {
            if active, let remark = engine.remark(for: scene) {
                HStack(alignment: .top, spacing: NoopMetrics.space2) {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        Label { Text(verbatim: "Nanashi") } icon: { Image(systemName: "quote.opening") }
                            .font(StrandFont.caption.weight(.semibold))
                            .foregroundStyle(StrandPalette.accentInk)
                        Text(remark.text)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                            Text(engine.isDemo ? "Local demo" : (engine.hasNewerReadings ? "Earlier analysis" : "Latest available readings"))
                            if !engine.isDemo, let date = engine.generatedAt {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        Button {
                            coach.pendingDraft = String(format: String(localized: "Explain this observation using my latest available data. Check what has changed since that analysis before advising me:\n\n%@"), remark.text)
                            router.openCoach()
                        } label: {
                            Label("Discuss with Coach", systemImage: "arrow.up.right")
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.accentInk)
                                .frame(minHeight: NoopButtonMetrics.minHitTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("nanashi.aside.discuss.\(scene.rawValue)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button { engine.dismiss(scene) } label: {
                        Image(systemName: "xmark")
                            .font(StrandFont.caption.weight(.semibold))
                            .foregroundStyle(StrandPalette.textSecondary)
                            .frame(width: NoopButtonMetrics.minHitTarget, height: NoopButtonMetrics.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss remark")
                }
                .padding(NoopMetrics.space4)
                .background(NoopPanelSurface(cornerRadius: NoopVisualStyle.compactRadius))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("nanashi.aside.\(scene.rawValue)")
            } else if active, engine.enabled, engine.isGenerating {
                HStack(spacing: NoopMetrics.space2) {
                    ProgressView().controlSize(.small)
                    Text("Reading your latest data…")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                .padding(.vertical, NoopMetrics.space2)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Mounted in the page background, independently of whether its optional remark has any content.
/// The zero-size clear view adds neither a stack slot nor a hit target to the page.
struct NanashiPresenceLifecycleProbe: View {
    var scene: NanashiPresenceScene? = nil
    @Environment(\.nanashiPresence) private var presence
    @Environment(\.nanashiPresenceScene) private var inheritedScene
    @Environment(\.nanashiPresenceIsActive) private var active

    var body: some View {
        if let presence {
            NanashiPresenceLifecycleHost(engine: presence, scene: scene ?? inheritedScene, active: active)
        }
    }
}

private struct NanashiPresenceLifecycleHost: View {
    @ObservedObject var engine: NanashiPresenceEngine
    let scene: NanashiPresenceScene
    let active: Bool
    @Environment(\.scenePhase) private var scenePhase

    private struct RefreshID: Equatable {
        let configuration: String
        let scene: NanashiPresenceScene
        let active: Bool
        let foreground: Bool
        let enabled: Bool
    }

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: RefreshID(configuration: engine.configurationKey, scene: scene,
                            active: active, foreground: scenePhase == .active,
                            enabled: engine.enabled)) {
            if scenePhase != .active {
                engine.leaveForeground()
            } else if active && (engine.enabled || engine.isDemo) {
                // Rapid tab changes should render immediately, not start optional work on the
                // navigation frame. Cancellation prevents a page that was just left from starting it.
                do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                // The engine owns opt-in, consent, demo isolation, request deduplication and budget.
                // A tab switch must not suspend another page's foreground batch.
                await engine.refreshIfNeeded()
            }
        }
    }
}

/// One visible control for foreground remarks, adapted from 21st Preferences Card (30553).
/// Core data consent remains revocable; enabling it here requires the explicit combined disclosure.
struct NanashiPresenceSettings: View {
    var compact = false
    @Environment(\.nanashiPresence) private var presence

    var body: some View {
        if let presence { NanashiPresenceSettingsContent(engine: presence, compact: compact) }
    }
}

private struct NanashiPresenceSettingsContent: View {
    @ObservedObject var engine: NanashiPresenceEngine
    @EnvironmentObject private var coach: AICoachEngine
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @State private var confirmDataAccess = false
    let compact: Bool

    private var remarksEnabled: Binding<Bool> {
        Binding(get: { engine.enabled }, set: { enabled in
            if !enabled {
                engine.enabled = false
            } else if engine.isDemo {
                engine.enabled = true
            } else if coach.isConfigured && coachEnabled {
                if coach.dataConsent { engine.enabled = true }
                else { confirmDataAccess = true }
            }
        })
    }

    var body: some View {
        NoopCard(padding: NoopMetrics.space4) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Toggle("Remarks in the app", isOn: remarksEnabled)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .toggleStyle(NoopToggleStyle())
                    // Revocation must remain reachable if the provider becomes unavailable.
                    .disabled(!engine.enabled && !engine.isDemo && (!coach.isConfigured || !coachEnabled))
                    .accessibilityIdentifier("nanashi.presence.enabled")
                if engine.isDemo {
                    Text("Local demo. Nothing is sent and this choice is not saved.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                } else if !coach.isConfigured {
                    Text("Connect your AI provider to enable remarks.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                } else if !coachEnabled {
                    Text("Turn on Coach in app settings to enable remarks.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                } else {
                    if !compact || !engine.enabled {
                        Text("Personal, sarcastic remarks across your pages.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    if engine.enabled && !coach.dataConsent {
                        Text("Paused: data access is off.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.statusWarning)
                        Button("Allow my data and resume") { confirmDataAccess = true }
                            .buttonStyle(NoopButtonStyle(.secondary))
                            .frame(minHeight: NoopMetrics.controlHeight)
                    } else {
                        Text("When on: automatic summaries to \(coach.provider.displayName), app open only. Max 4/day; API fees may apply.")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog("Enable personal remarks?", isPresented: $confirmDataAccess,
                            titleVisibility: .visible) {
            Button("Allow and enable") {
                guard coach.isConfigured, coachEnabled else { return }
                coach.dataConsent = true
                engine.enabled = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nanashi will share your charge, sleep, HRV and recent workouts (sport, duration, distance and heart rate) with \(coach.provider.displayName) for personal answers and automatic remarks. Remarks run only while the app is open, up to 4 requests a day. API fees may apply. You can turn this off at any time.")
        }
    }
}

/// Observes the optional engine so changing the opt-in immediately updates the privacy disclosure.
struct NanashiPresencePrivacyText: View {
    let fallback: Text
    let provider: String
    @Environment(\.nanashiPresence) private var presence

    var body: some View {
        if let presence {
            NanashiPresencePrivacyContent(engine: presence, fallback: fallback, provider: provider)
        } else {
            fallback
        }
    }
}

private struct NanashiPresencePrivacyContent: View {
    @ObservedObject var engine: NanashiPresenceEngine
    let fallback: Text
    let provider: String

    var body: some View {
        if !engine.isDemo, engine.enabled, engine.isAvailable {
            Text("Spontaneous remarks are on: a summary may also be sent automatically to \(provider) while the app is open. Turn this off in Coach settings.")
        } else {
            fallback
        }
    }
}
