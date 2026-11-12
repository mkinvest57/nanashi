import SwiftUI
import StrandDesign

/// Compact Coach settings: the daily remarks control stays visible, while model choice, data access,
/// optional context, custom instructions and scheduled briefs expand only when requested. The same
/// remarks control is reachable directly from the conversation.
///
/// Connection management (the provider pill, Update key, Clear conversation, Disconnect) stays on
/// `CoachView`, where both the conversation and the key editor are visible. The Kotlin twin
/// `CoachSettingsScreen` splits on the same line.
///
/// Presented as a sheet rather than pushed. CoachView appears in three places between the two
/// platforms (a macOS route, an iPhone tab root whose navigation bar is hidden, and an iPhone pillar
/// sheet), and a sheet is the one presentation that behaves the same in all three without depending on
/// an enclosing NavigationStack.
struct CoachSettingsView: View {
    @EnvironmentObject var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss

    /// Morning-brief settings, read from `CoachBriefScheduler` on init exactly as `CoachView` did
    /// before the split. This screen can now be the first to render them.
    @State private var briefEnabled: Bool = CoachBriefScheduler.isEnabled
    @State private var briefMinutes: Int = CoachBriefScheduler.timeMinutes
    @State private var briefGenerating = false
    @State private var briefStatus: String?

    /// The coach-instructions editor, collapsed until asked for.
    @State private var promptExpanded: Bool = false
    @State private var promptDraft: String = ""
    @State private var customModelDraft = ""
    @State private var modelExpanded = false
    @State private var advancedExpanded = false
    @State private var customModelExpanded = false

    var body: some View {
        // Literals, not String(localized:): `title`/`subtitle` are LocalizedStringKey, which converts
        // from a string LITERAL only, so a String value does not type-check here. The catalog keys are
        // these exact English strings.
        //
        // Done goes in the scaffold's `trailing` slot rather than a .toolbar. ScreenScaffold is a bare
        // ScrollView with no NavigationStack, so a toolbar item presented in a sheet would render
        // nowhere, and a macOS sheet has no swipe-to-dismiss: that combination would leave this screen
        // with no way out. (#2206 is the same mistake in the other direction.)
        ScreenScaffold(title: "Coach settings",
                       subtitle: "Choose how Nanashi talks to you.",
                       topBackground: liquidScaffoldSky(), showsPresence: false,
                       trailing: {
                           Button("Done") { dismiss() }
                               .buttonStyle(.plain)
                               .font(StrandFont.subhead)
                               .foregroundStyle(StrandPalette.accentInk)
                               .accessibilityLabel("Close coach settings")
                       }) {
            NanashiPresenceSettings()
            settingsRow("Model and connection", subtitle: Text("\(coach.provider.displayName) · \(coach.model)"),
                        icon: "cpu", expanded: $modelExpanded)
            if modelExpanded { modelBar }
            settingsRow("Advanced settings", subtitle: Text("Data access, tone and morning brief."),
                        icon: "slider.horizontal.3", expanded: $advancedExpanded)
            if advancedExpanded {
                consentBar
                if coach.dataConsent { onDeviceSignalsBar }
                if coach.dataConsent && coach.provider == .gemini { multimodalChartBar }
                systemPromptBar
                morningBriefBar
            }
        }
        // Opening this screen is the moment a stale catalogue is worth refreshing: a key exists here by
        // definition, and the picker above is about to be read. Rate-limited and silent on failure.
        .task { await coach.refreshModelsIfStale() }
    }

    /// Source-derived preference rows keep optional configuration out of the primary path.
    private func settingsRow(_ title: LocalizedStringKey, subtitle: Text, icon: String,
                             expanded: Binding<Bool>) -> some View {
        Button { expanded.wrappedValue.toggle() } label: {
            NoopCard(padding: NoopMetrics.space4) {
                HStack(spacing: NoopMetrics.space3) {
                    Image(systemName: icon)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.accentInk)
                        .frame(width: NoopMetrics.controlHeight, height: NoopMetrics.controlHeight)
                        .background(NoopPanelSurface(cornerRadius: NoopVisualStyle.compactRadius))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
                        Text(title).font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        subtitle.font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: NoopMetrics.space2)
                    Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: NoopMetrics.controlHeight)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(expanded.wrappedValue ? Text("Expanded") : Text("Collapsed"))
    }

    /// Which model answers, and the control that refreshes the list of them.
    ///
    /// This lives HERE rather than on the setup card because of where a key exists. `setupCard` renders
    /// only while `isConfigured` is false, which for a cloud provider means no key is stored, and the
    /// Refresh control is `.disabled((!coach.hasKey && coach.provider != .custom) || coach.refreshingModels || coach.sending)` — gated on having a key inside a screen that only
    /// appears when there is none. So for OpenAI, Anthropic and Gemini that button was permanently
    /// disabled and the live catalogue those three publish was unreachable. A key exists by definition
    /// on this screen, so the picker and the refresh both work.
    ///
    /// The PROVIDER deliberately stays on the setup card. A stored key records which provider it
    /// belongs to and is never sent anywhere else, so switching provider here would leave a key that
    /// cannot be used and a screen that cannot fix it. Kotlin twin: `CoachModelCard`.
    private var modelBar: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(coach.provider.displayName) · \(coach.model)")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    Spacer(minLength: 8)
                    Button {
                        Task { await coach.refreshModels() }
                    } label: {
                        if coach.refreshingModels {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh models", systemImage: "arrow.clockwise")
                                .font(StrandFont.footnote)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(StrandPalette.accentInk)
                    .disabled((!coach.hasKey && coach.provider != .custom) || coach.refreshingModels || coach.sending)
                    .accessibilityLabel("Refresh models from provider")
                }
                Picker("Model", selection: $coach.model) {
                    ForEach(coach.availableModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Model")
                .disabled(coach.sending)
                Button("Enter a custom model ID") { customModelExpanded.toggle() }
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.accentInk)
                    .buttonStyle(.plain)
                    .frame(minHeight: NoopMetrics.controlHeight)
                if customModelExpanded {
                    HStack(spacing: NoopMetrics.space2) {
                        TextField("Enter a model id", text: $customModelDraft)
                            .textFieldStyle(.plain)
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .padding(NoopMetrics.space3)
                            .background(StrandPalette.surfaceInset,
                                        in: RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius))
                            .disableAutocorrection(true)
                            .accessibilityLabel("Custom model id")
                        NoopButton("Use", kind: .secondary) {
                            coach.setCustomModel(customModelDraft)
                            customModelDraft = ""
                        }
                        .disabled(customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coach.sending)
                    }
                }
                Text("Refreshing the list keeps your selected model unchanged.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                if let updatedAt = coach.modelCatalogueUpdatedAt {
                    Text("Provider catalogue updated \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                } else {
                    Text("Offline suggestions. Refresh to check your provider's current catalogue.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                if coach.selectedModelIsListed == false {
                    Text("Your selected model was not in the last catalogue. It is kept until you choose another.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.statusWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("A listed model still needs access and available quota on your provider account.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = coach.errorText, !error.isEmpty {
                    Text(error)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.statusCritical)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Explicit, revocable permission for the coach to read & send the user's data. Off by default.
    /// A frosted Charge-tinted card so it reads as part of the green Coach world, not a flat panel.
    private var consentBar: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            HStack(spacing: 10) {
                Image(systemName: coach.dataConsent ? "lock.open.fill" : "lock.fill")
                    .foregroundStyle(coach.dataConsent ? StrandPalette.accent : StrandPalette.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Let the coach use my data")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    // The ON line NAMES what a session carries rather than saying "workouts" and
                    // leaving the reader to guess how much that is: the sport, how long, how far and how
                    // hard, per session. The direct remarks control also offers an explicit combined
                    // consent dialog; this toggle remains the independent revocation control.
                    Text(coach.dataConsent
                         ? "On: your charge, rest, HRV and workouts are sent to the provider, each workout with its sport, duration, distance and heart rate."
                         : "Off: the coach answers generally and sends none of your metrics.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $coach.dataConsent)
                    .labelsHidden().toggleStyle(NoopToggleStyle()).tint(StrandPalette.accent)
                    .accessibilityLabel("Let the coach use my data")
            }
        }
    }

    /// The v5 second opt-in: include a SUMMARY of the new on-device signals (strongest n-of-1 patterns +
    /// Lab Book markers). Summary-only, never raw readings, so the no-raw-egress posture holds.
    private var onDeviceSignalsBar: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            HStack(spacing: 10) {
                Image(systemName: coach.includeOnDeviceSignals ? "checklist.checked" : "checklist")
                    .foregroundStyle(coach.includeOnDeviceSignals ? StrandPalette.accent : StrandPalette.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Also share my patterns & Lab Book")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    Text(coach.includeOnDeviceSignals
                         ? "On: a short summary of your strongest patterns and logged health numbers is added. Summaries only, never raw readings."
                         : "Off: only your core metrics are shared, not your patterns or Lab Book.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $coach.includeOnDeviceSignals)
                    .labelsHidden().toggleStyle(NoopToggleStyle()).tint(StrandPalette.accent)
                    .accessibilityLabel("Also share my patterns and Lab Book with the coach")
            }
        }
    }

    /// K11: Third opt-in — send a chart image alongside the text when using Gemini's multimodal
    /// API. Only shown when the provider is Gemini. OFF by default.
    private var multimodalChartBar: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            HStack(spacing: 10) {
                Image(systemName: coach.multimodalChartEnabled ? "photo.badge.checkmark" : "photo")
                    .foregroundStyle(coach.multimodalChartEnabled ? StrandPalette.accent : StrandPalette.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Send chart image to Gemini")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    Text(coach.multimodalChartEnabled
                         ? "On: a chart snapshot of your trends is sent with each question. Gemini can analyze the visual."
                         : "Off: only text is sent. Enable to let Gemini see your charts.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $coach.multimodalChartEnabled)
                    .labelsHidden().toggleStyle(NoopToggleStyle()).tint(StrandPalette.accent)
                    .accessibilityLabel("Send chart image to Gemini")
            }
        }
    }

    /// Editable system prompt, the instructions that frame the coach. Collapsed by default; expanding
    /// reveals a TextEditor bound to the engine (edits persist to UserDefaults and take effect on the
    /// next message) plus a Reset-to-default control.
    private var systemPromptBar: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            VStack(alignment: .leading, spacing: promptExpanded ? 10 : 0) {
                Button {
                    withAnimation(StrandMotion.fade) {
                        promptExpanded.toggle()
                        if promptExpanded { promptDraft = coach.customSystemPrompt }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "text.alignleft")
                            .foregroundStyle(coach.hasCustomSystemPrompt ? StrandPalette.accent : StrandPalette.textTertiary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Coach instructions")
                                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                            Text(coach.hasCustomSystemPrompt
                                 ? "Customised. Your edited instructions frame every reply."
                                 : "Edit how the coach thinks and talks. Takes effect on your next message.")
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: promptExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(promptExpanded ? "Collapse coach instructions" : "Edit coach instructions")

                if promptExpanded {
                    TextEditor(text: $promptDraft)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140, maxHeight: 240)
                        .padding(8)
                        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                        .onChangeCompat(of: promptDraft) { newValue in
                            coach.customSystemPrompt = newValue
                        }
                        .accessibilityLabel("Coach instructions editor")

                    HStack {
                        Spacer()
                        Button {
                            coach.resetSystemPrompt()
                            promptDraft = coach.customSystemPrompt
                        } label: {
                            Label("Reset to default", systemImage: "arrow.uturn.backward")
                                .font(StrandFont.footnote)
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(StrandPalette.accentInk)
                        .disabled(!coach.hasCustomSystemPrompt)
                        .accessibilityLabel("Reset coach instructions to default")
                    }
                }
            }
        }
    }

    /// K5: the scheduled morning-brief notification settings — enable toggle, time-of-day picker, and an
    /// explicit "Generate now" button. Mirrors the `ScheduledDebugExport` settings row shape (TestCentreView).
    private var morningBriefBar: some View {
        NoopCard(padding: 14, tint: StrandPalette.chargeColor) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: briefEnabled ? "sunrise.fill" : "sunrise")
                        .foregroundStyle(briefEnabled ? StrandPalette.accent : StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Morning brief").font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                        Text(briefEnabled
                             ? "A notification with today's brief from your selected AI provider."
                             : "Off: nothing is generated or sent on a schedule.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: $briefEnabled)
                        .labelsHidden().toggleStyle(NoopToggleStyle()).tint(StrandPalette.accent)
                        .accessibilityLabel("Morning brief")
                }
                .onChangeCompat(of: briefEnabled) { on in
                    CoachBriefScheduler.setEnabled(on, generateBrief: { await coach.generateBrief() }) { outcome in
                        if outcome == .denied {
                            briefEnabled = false
                            briefStatus = "Notifications are off for NOOP — enable them in Settings first."
                        }
                    }
                }

                if briefEnabled {
                    Divider().overlay(StrandPalette.hairline)
                    HStack {
                        Text("Time").font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                        Spacer()
                        DatePicker("", selection: briefTimeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .accessibilityLabel("Morning brief time")
                    }
                    Text("At \(Platform.deviceNounPhrase == "Mac" ? "this time" : "or soon after"), NOOP will use your key to generate today's brief. Best-effort: \(Platform.deviceNounPhrase) decides exactly when a backgrounded app wakes.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    NoopButton(briefGenerating ? "Generating…" : "Generate now", systemImage: "sparkles", kind: .secondary) {
                        generateBriefNow()
                    }
                    .disabled(briefGenerating)
                    if let briefStatus {
                        Text(briefStatus).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
    }

    private var briefTimeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.hour = briefMinutes / 60
                c.minute = briefMinutes % 60
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                let m = (c.hour ?? 7) * 60 + (c.minute ?? 0)
                briefMinutes = m
                CoachBriefScheduler.setTimeMinutes(m, generateBrief: { await coach.generateBrief() })
            }
        )
    }

    private func generateBriefNow() {
        Task {
            briefGenerating = true
            briefStatus = nil
            defer { briefGenerating = false }
            let text = await CoachBriefScheduler.generateNow { await coach.generateBrief() }
            if let text {
                coach.appendGeneratedBrief(text)
            } else {
                briefStatus = "Couldn't generate a brief right now — check your key and data access."
            }
        }
    }
}
