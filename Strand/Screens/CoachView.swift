import SwiftUI
import MarkdownUI
import StrandDesign

/// Coach, the one feature in NOOP that talks to the network.
///
/// It is strictly opt-in and bring-your-own-key: the user pastes their own OpenAI
/// or Anthropic API key (stored in the macOS Keychain by `AICoachEngine`), and only
/// a compact text summary of their metrics plus their question ever leaves the Mac.
/// Questions use the saved key. Optional briefs and foreground remarks have separate opt-ins.
///
/// This screen compiles against `AICoachEngine`'s public API (the macos-core agent's
/// contract): `hasKey`, `provider` / `provider.modelOptions`, `model`, `messages`,
/// `sending`, `errorText`, `setKey(_:)`, `clearKey()`, and `send(_:)`.
struct CoachView: View {
    @EnvironmentObject var coach: AICoachEngine
    /// K8: used by "Save to Journal" — saves the coach advice as a journal entry with the text
    /// in the notes field, so it appears alongside other journal entries in Insights.
    @EnvironmentObject var repo: Repository
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollFollow = CoachScrollFollowState()
    @State private var pendingFollow: Task<Void, Never>?
    @State private var composerOverlayHeight = NoopMetrics.controlHeight + NoopMetrics.space2 * 4
    @State private var lastTranscriptFrame = CGRect.zero

    /// Draft text in the composer (the question being typed).
    /// K15: the composer draft is persisted to UserDefaults so it survives an app relaunch.
    /// Restored on first appear, saved on every change. Keyed identically to the Android twin.
    private static let draftKey = "coach.composerDraft"
    @State private var draft: String = UserDefaults.standard.string(forKey: "coach.composerDraft") ?? ""
    /// Pending key text in the setup card (never persisted here, handed to `setKey`).
    @State private var keyDraft: String = ""
    /// The replacement key, typed into the editor a rejection or Update key opens. Separate from
    /// `keyDraft` so the
    /// setup card's own field is untouched, and cleared on save so a secret does not sit in view state
    /// after it has been stored. Twin of the Kotlin `keyFix`.
    @State private var keyFix: String = ""
    @State private var showKeyEditor = false
    /// Whether the model selector is in free-text "Custom…" mode.
    @State private var customModel: Bool = false
    /// The id typed in the "Custom…" field.
    @State private var customModelDraft: String = ""
    @FocusState private var composerFocused: Bool

    /// K2: confirmation gate for the destructive "Clear conversation" toolbar action.
    @State private var showClearConfirm = false
    /// #2243: the coach settings, presented as a sheet. See `CoachSettingsView` for why a sheet
    /// rather than a push.
    @State private var showSettings = false
    @State private var setupModelExpanded = false

    // K4: on-device voice input for the composer (iOS only). macOS gets a no-op stub via
    // `#if os(iOS)` guards — the shared file keeps compiling for both targets.
    #if os(iOS)
    @StateObject private var voiceInput = CoachVoiceInput()
    @State private var composerOwnsKeyboard = false
    @State private var keyboardLayoutRevision = 0
    #endif

    /// Sentinel tag for the "Custom…" entry in the model Picker.
    private let customModelTag = "__custom__"

    /// Contextual suggestion chips, derived from today's bands by `AICoachEngine.suggestions`
    /// (→ `CoachSuggestions`). Falls back to a stable generic set when there is no data. Recomputed
    /// on each body evaluation so a fresh sync immediately updates the chips.
    private var suggestions: [String] {
        coach.suggestions.map { NSLocalizedString($0, comment: "Coach suggested question") }
    }

    var body: some View {
        Group {
            if coach.isConfigured {
                conversation
            } else {
                ScreenScaffold(title: "Coach",
                               subtitle: "Ask about your charge, effort, rest and workouts, grounded in your own numbers.",
                               topBackground: liquidScaffoldSky(), showsPresence: false) {
                    setupCard
                }
            }
        }
        // macOS only. On iOS these actions live in `connectionMenu` instead, because this bar is hidden for
        // a primary tab root and VISIBLE in the pillar sheet, so leaving them here would render nothing
        // on the Coach tab and a duplicate of the menu in the sheet. One control per platform, reachable
        // in both of iOS's presentations. The `#if` sits on the CHAIN rather than inside the builder:
        // `ToolbarContentBuilder` is not relied on to accept an empty body, and the one other
        // conditional toolbar here (CoupledView) always yields an item on both platforms. (#2206)
        #if os(macOS)
        .toolbar {
            if coach.isConfigured {
                ToolbarItem {
                    Button {
                        toggleKeyEditor()
                    } label: {
                        Label("Update key", systemImage: "key.fill")
                    }
                }
                // K2: wipe the persisted + in-memory conversation. Confirmed, since it's destructive.
                ToolbarItem {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Clear conversation", systemImage: "trash")
                    }
                    .help("Clear the saved conversation")
                    .accessibilityLabel("Clear conversation")
                    .disabled(coach.messages.isEmpty)
                }
                ToolbarItem {
                    Button(role: .destructive) {
                        coach.disconnect()
                        keyDraft = ""
                    } label: {
                        Label("Disconnect", systemImage: "gearshape")
                    }
                    .help("Forget the saved key and disconnect")
                    .accessibilityLabel("Disconnect provider")
                }
            }
        }
        #endif
        // #2243: coach settings. `repo` rides along because the scaffold's environment is not
        // inherited by a sheet's own view tree.
        .sheet(isPresented: $showSettings) {
            CoachSettingsView()
                .environmentObject(coach)
                .environmentObject(repo)
        }
        .confirmationDialog(
            "Clear conversation?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { coach.clearConversation() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the saved conversation from this device. Coach history is your own notes, not medical advice.")
        }
        // K2 + K5 ordering matters and every step gates on an EMPTY transcript, so this is ONE `.task`
        // running sequentially (separate `.task`s can interleave at their await points on the same
        // actor): restore whatever the prior launch persisted, THEN surface a brief the scheduled
        // notification already generated (if any), THEN the interactive first-open brief — so
        // `startBriefIfNeeded` only ever runs over the network when BOTH of the above left the
        // transcript genuinely empty.
        .task {
            guard !coach.isLocalDemo else { return }
            await coach.loadPersistedMessagesIfNeeded()
            coach.retireStaleConversationIfNeeded()
            // Gated on the transcript BEFORE consuming. `consumeStoredBrief()` clears the unconsumed
            // flag, and `surfaceScheduledBrief` then drops the text if a transcript exists, so a brief
            // that arrived on a day with a conversation already open was consumed and thrown away, gone
            // for good. Android checked first and so only ever failed to SHOW it (#2087).
            if coach.messages.isEmpty, let stored = CoachBriefScheduler.consumeStoredBrief() {
                coach.surfaceScheduledBrief(stored)
            }
            // Preparing a contextual question is not permission to send an unrelated first-open brief.
            if coach.pendingDraft == nil && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                CoachBriefScheduler.activateIfEnabled { await coach.generateBrief() }
                await coach.startBriefIfNeeded()
            }
        }
        // #1862: a question handed over by the Today launcher sheet. Cleared BEFORE sending so a view
        // rebuild mid-flight cannot send it twice, and gated on `isConfigured` so an unconfigured handoff
        // (which the launcher does not produce, but a future caller might) degrades to showing setup
        // rather than a failed request.
        .task(id: coach.pendingPrompt) {
            guard let prompt = coach.pendingPrompt, !prompt.isEmpty else { return }
            coach.pendingPrompt = nil
            guard coach.isConfigured else { return }
            await coach.send(prompt)
        }
        // Contextual page remarks prepare a question without sending it. Consume the handoff before
        // changing the composer, and preserve any text the wearer has already started writing.
        .task(id: coach.pendingDraft) {
            guard let pending = coach.pendingDraft else { return }
            coach.pendingDraft = nil
            guard !pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft = pending
            } else {
                draft += "\n\n" + pending
            }
            if coach.isConfigured { composerFocused = true }
        }
        // K15: persist the composer draft so it survives an app relaunch.
        .onChangeCompat(of: draft) { newValue in
            guard !coach.isLocalDemo else { return }
            UserDefaults.standard.set(newValue, forKey: Self.draftKey)
        }
        // K14: haptic feedback when a reply arrives (sending goes true → false).
        .onChangeCompat(of: coach.sending) { isSending in
            if !isSending && coach.errorText == nil && coach.messages.last?.role == .assistant {
                triggerReplyHaptic()
            }
        }
        // A consent toggle AFTER the initial load re-checks the brief (the original `.task(id:)`
        // behaviour); the guard inside `startBriefIfNeeded` (messages.isEmpty) keeps this a no-op once
        // a conversation exists.
        .onChangeCompat(of: coach.dataConsent) { _ in
            Task {
                guard coach.pendingDraft == nil,
                      draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                await coach.startBriefIfNeeded()
            }
        }
    }

    // MARK: - Setup (no key yet)

    private var setupCard: some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(StrandPalette.accentInk)
                        .accessibilityHidden(true)
                    Text("Connect a provider")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                }

                Text("Choose your provider and add its API key. A model is already selected; your key stays in the secure Keychain.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Provider
                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider").strandOverline()
                    Picker("Provider", selection: $coach.provider) {
                        ForEach(AIProvider.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(NoopMetrics.space3)
                    .background(NoopPanelSurface(cornerRadius: NoopVisualStyle.compactRadius))
                    .accessibilityLabel("Provider")
                }

                // Server URL (Custom / local LLM only)
                if coach.provider == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Server URL").strandOverline()
                        TextField("http://localhost:11434/v1", text: $coach.customBaseURL)
                            .textFieldStyle(.plain)
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                            .disableAutocorrection(true)
                            .accessibilityLabel("Server URL")
                        Text("Any OpenAI-compatible server: Ollama, LM Studio, llama.cpp, or your own gateway. Stays on your network; nothing leaves \(Platform.deviceNounPhrase).")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Key header").strandOverline()
                        Picker("Key header", selection: $coach.customAuthHeader) {
                            ForEach(CustomAIAuthHeader.allCases) { header in
                                Text(header.displayName).tag(header)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Key header")
                        Text("Use Bearer for most local servers; use x-api-key for gateways that require the key in that header.")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // The default model is ready; custom servers may require a specific installed model.
                if coach.provider == .custom {
                    modelSelector
                } else {
                    Button {
                        setupModelExpanded.toggle()
                    } label: {
                        HStack(spacing: NoopMetrics.space2) {
                            Text("Choose a different model")
                            Spacer()
                            Image(systemName: setupModelExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .frame(minHeight: NoopMetrics.controlHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if setupModelExpanded { modelSelector }
                }

                // Key
                VStack(alignment: .leading, spacing: 6) {
                    Text(coach.provider == .custom ? "API key (optional)" : "API key").strandOverline()
                    SecureField(coach.provider == .custom
                                ? "Only if your server requires one"
                                : "Paste your \(coach.provider.displayName) API key", text: $keyDraft)
                        .textFieldStyle(.plain)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                        .onSubmit { coach.provider == .custom ? connectCustom() : saveKey() }
                        .accessibilityLabel("API key")
                }

                HStack {
                    if coach.provider == .custom {
                        NoopButton("Connect", systemImage: "link", kind: .primary, action: connectCustom)
                            .disabled(coach.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        NoopButton("Save key", systemImage: "key.fill", kind: .primary, action: saveKey)
                            .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Spacer()
                }

                // Whatever the last attempt from THIS card ran into. The setup card had no error line
                // at all, so every way it can fail before a key is committed failed silently: a Refresh
                // the provider turned away, a Connect to a server that wants auth. The wearer saw a
                // button do nothing. No repair affordance beside it, unlike the chat: the key field is
                // already on screen, which is the whole point of the card.
                if let error = coach.errorText, !error.isEmpty {
                    errorBanner(error)
                }

                Divider().overlay(StrandPalette.hairline)
                privacyFootnote
            }
        }
    }

    /// Model selector: a Picker over `coach.availableModels` with a free-text "Custom…" path and a
    /// "Refresh models" button that fetches the provider's live list.
    private var modelSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Model").strandOverline()
                Spacer()
                Button {
                    Task { await coach.refreshModels() }
                } label: {
                    Label("Refresh models", systemImage: "arrow.clockwise")
                        .font(StrandFont.footnote)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(StrandPalette.accentInk)
                .disabled((!coach.hasKey && coach.provider != .custom) || coach.refreshingModels)
                .help("Fetch the available models from \(coach.provider.displayName) using your saved key")
                .accessibilityLabel("Refresh models from provider")
            }

            Picker("Model", selection: modelPickerSelection) {
                ForEach(coach.availableModels, id: \.self) { m in
                    Text(m).tag(m)
                }
                Divider()
                Text("Custom…").tag(customModelTag)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityLabel("Model")

            if customModel {
                HStack(spacing: 8) {
                    TextField("Enter a model id", text: $customModelDraft)
                        .textFieldStyle(.plain)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                        .onSubmit(applyCustomModel)
                        .accessibilityLabel("Custom model id")

                    Button("Use", action: applyCustomModel)
                        .buttonStyle(NoopButtonStyle(.secondary))
                        .disabled(customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Use custom model")
                }
            }
        }
    }

    /// Bridges the model Picker to `coach.model`, with a "Custom…" sentinel that opens the free-text
    /// field instead of selecting a real id.
    private var modelPickerSelection: Binding<String> {
        Binding(
            get: { customModel ? customModelTag : coach.model },
            set: { newValue in
                if newValue == customModelTag {
                    customModel = true
                    if customModelDraft.isEmpty { customModelDraft = coach.model }
                } else {
                    customModel = false
                    coach.model = newValue
                }
            }
        )
    }

    private func applyCustomModel() {
        let trimmed = customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coach.setCustomModel(trimmed)
        customModel = false
    }

    // MARK: - Connected state

    private var connectedHeader: some View {
        HStack(spacing: NoopMetrics.space2) {
            VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
                Text(coach.isLocalDemo ? String(localized: "Local demo") : coach.provider.displayName)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(coach.isLocalDemo ? String(localized: "Synthetic conversation. No API request is sent.")
                     : coach.dataConsent ? String(localized: "Personal answers") : String(localized: "General answers"))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            // #2243: the way through to what used to be stacked under this header.
            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .frame(width: NoopMetrics.controlHeight, height: NoopMetrics.controlHeight)
                    .background(NoopPanelSurface(cornerRadius: NoopVisualStyle.pillRadius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Coach settings"))
            #if os(iOS)
            if !coach.isLocalDemo { connectionMenu.disabled(coach.sending) }
            #endif
        }
    }

    #if os(iOS)
    /// #2206: the same connection actions the toolbar above carries, drawn where iPhone can reach them.
    ///
    /// `RootTabView.tab(...)` wraps every primary tab root in a NavigationStack and applies
    /// `.toolbar(.hidden, for: .navigationBar)`, because each screen draws its own in-content header.
    /// So Clear conversation and Disconnect were being placed into a bar this platform never shows, and
    /// rendered nowhere. At the time, Disconnect was the only route back to the setup card: `isConfigured`
    /// gates that card away the moment a key is saved. The
    /// result was a key that could be set once and then never changed, with reinstalling the app the
    /// only way out, which on an offline-first app costs the wearer their entire history.
    ///
    /// macOS keeps the toolbar and does not get this, so its behaviour is untouched. On iOS the toolbar
    /// route is withdrawn rather than kept alongside: CoachView is presented twice on this platform, as
    /// a primary tab whose bar is hidden and as a pillar sheet whose bar is NOT (it draws a Done button
    /// and only hides the bar's background). Keeping both would render nothing on the tab and two of
    /// everything in the sheet. One control, reachable in both presentations.
    ///
    /// A menu rather than a bare button because it needs two taps to reach a destructive action,
    /// matching the protection the toolbar's separation gives, and because both actions belong to the
    /// same connection.
    ///
    /// Worth knowing before changing `disconnect()`: neither `hasKey` nor `isConfigured` is published,
    /// since `hasKey` reads the Keychain on each evaluation. The setup card reappears because
    /// `disconnect()` ALSO assigns the published `messages`, which is what re-evaluates the body. A
    /// future disconnect that stopped clearing the transcript would clear the key and leave this screen
    /// showing a chat for a connection that no longer exists. macOS has depended on the same coupling
    /// since its toolbar button existed, so this is a latent edge being written down, not a new one.
    private var connectionMenu: some View {
        Menu {
            Button {
                toggleKeyEditor()
            } label: {
                Label("Update key", systemImage: "key.fill")
            }
            Button {
                showClearConfirm = true
            } label: {
                Label("Clear conversation", systemImage: "trash")
            }
            .disabled(coach.messages.isEmpty)
            Button(role: .destructive) {
                coach.disconnect()
                keyDraft = ""
            } label: {
                Label("Disconnect", systemImage: "gearshape")
            }
        } label: {
            // Same affordance DevicesView uses for its per-device menu, headline size included. The
            // size is not decoration here: the report this came from was that the option could not be
            // FOUND, so a control that matches the one the wearer has already learned, at a size worth
            // aiming at, is doing part of the work.
            Image(systemName: "ellipsis.circle")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(width: NoopMetrics.controlHeight, height: NoopMetrics.controlHeight)
        }
        .accessibilityLabel("Connection")
    }
    #endif

    /// Assistant Composer (#38323) supplies a growing field and one Send/Stop action. The native
    /// compact adaptation floats over the transcript, reserving its measured height in scroll content.
    private var conversation: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: NoopMetrics.space5) {
                        Text("Coach")
                            .font(StrandFont.title1)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .id("coach.top")
                            .background(NoopDockScrollOffsetProbe())
                        connectedHeader
                        NanashiPresenceSettings(compact: true)
                        if !coach.isLocalDemo {
                            Text(coach.dataConsent
                                 ? "Your latest available data is read again for each question."
                                 : "Data access is off. Coach can only give general guidance.")
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if coach.messages.isEmpty && !coach.sending {
                            emptyTranscript
                        }
                        ForEach(coach.messages) { message in
                            if !message.text.isEmpty { bubble(message).id(message.id) }
                        }
                        if coach.sending && (coach.messages.last?.text.isEmpty != false) {
                            typingIndicator
                        }
                        if let error = coach.errorText, !error.isEmpty { errorBanner(error) }
                        if coach.keyRejected || showKeyEditor { keyRepairPanel }
                        if coach.canRetryLastQuestion {
                            NoopButton("Retry question", systemImage: "arrow.clockwise", kind: .secondary) {
                                Task { await coach.retryLastQuestion() }
                            }
                        }
                        if !coach.sending {
                            if showFollowUpChips { followUpChips } else { suggestionChips }
                        }
                        privacyFootnote
                        // The anchor includes the overlay reservation, so scrolling to its bottom
                        // leaves the final text above the floating composer rather than behind it.
                        Color.clear.frame(height: composerOverlayHeight).id("coach.end")
                    }
                    .padding(.horizontal, NoopMetrics.screenHPadding)
                    .padding(.vertical, NoopMetrics.space5)
                    .frame(maxWidth: NoopMetrics.pageMaxWidth)
                    .frame(maxWidth: .infinity)
                    .background {
                        GeometryReader { content in
                            Color.clear.preference(key: CoachTranscriptFrameKey.self,
                                value: content.frame(in: .named(NoopDockScrollOffsetProbe.coordinateSpaceName)))
                        }
                    }
                }
                .coordinateSpace(name: NoopDockScrollOffsetProbe.coordinateSpaceName)
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBasedOnSizeCompat(axes: .horizontal)
                #endif
                .onPreferenceChange(CoachTranscriptFrameKey.self) { frame in
                    if lastTranscriptFrame != frame { lastTranscriptFrame = frame }
                    let follow = scrollFollow.observe(
                        distanceFromBottom: Double(frame.maxY - viewport.size.height),
                        contentHeight: Double(frame.height), viewportHeight: Double(viewport.size.height),
                        nearBottomThreshold: Double(NoopMetrics.controlHeight + NoopMetrics.space4))
                    if follow { scheduleFollow(proxy) }
                }
                .onChangeCompat(of: viewport.size.height) { height in
                    // A keyboard can resize the viewport without changing the transcript's frame.
                    // Observe that boundary explicitly, and only move readers who already followed.
                    guard lastTranscriptFrame.height > 0 else { return }
                    let wasFollowing = scrollFollow.shouldFollow
                    let follow = scrollFollow.observe(
                        distanceFromBottom: Double(lastTranscriptFrame.maxY - height),
                        contentHeight: Double(lastTranscriptFrame.height), viewportHeight: Double(height),
                        nearBottomThreshold: Double(NoopMetrics.controlHeight + NoopMetrics.space4))
                    if wasFollowing && follow { scheduleFollow(proxy) }
                }
                .simultaneousGesture(DragGesture(minimumDistance: NoopMetrics.space2)
                    .onChanged { gesture in
                        guard abs(gesture.translation.height) > abs(gesture.translation.width) else { return }
                        scrollFollow.beginInteraction(towardHistory: gesture.translation.height > 0)
                        pendingFollow?.cancel()
                        pendingFollow = nil
                    }
                    .onEnded { _ in
                        scrollFollow.endInteraction()
                        if scrollFollow.shouldFollow { scheduleFollow(proxy) }
                    })
                .overlay(alignment: .bottom) {
                    if !coach.messages.isEmpty &&
                        (!scrollFollow.followsLatest || (!coach.sending && !scrollFollow.isNearBottom)) {
                        Button {
                            scrollFollow.showLatest()
                            withAnimation(reduceMotion ? nil : NoopMotion.card) {
                                scrollToEnd(proxy)
                            }
                        } label: {
                            Label("Latest response", systemImage: "arrow.down")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textPrimary)
                                .padding(.horizontal, NoopMetrics.space4)
                                .frame(minHeight: NoopMetrics.controlHeight)
                                .background(NoopPanelSurface(cornerRadius: NoopVisualStyle.pillRadius, elevated: true))
                        }
                        .buttonStyle(LiquidPressStyle())
                        .padding(.bottom, composerOverlayHeight + NoopMetrics.space2)
                        .accessibilityIdentifier("coach.latest-response")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                floatingComposer
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: CoachComposerHeightKey.self,
                                                   value: geometry.size.height)
                        }
                    }
            }
            .onPreferenceChange(CoachComposerHeightKey.self) { height in
                guard height.isFinite, height > 0,
                      abs(composerOverlayHeight - height) > NoopMetrics.hairlineWidth else { return }
                composerOverlayHeight = height
            }
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    StrandPalette.surfaceBase
                    liquidScaffoldSky()
                }.ignoresSafeArea()
            }
            #if os(iOS)
            .onChangeCompat(of: composerFocused) { focused in
                if focused && !showSettings {
                    // Focus arrives before the keyboard can move the scroll view. Do not derive
                    // follow intent from intermediate keyboard-avoidance geometry.
                    composerOwnsKeyboard = true
                    scrollFollow.beginViewportTransition()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
                guard !showSettings, composerFocused || composerOwnsKeyboard else { return }
                scrollFollow.beginViewportTransition()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { _ in
                guard scrollFollow.isViewportTransitionPending else { return }
                keyboardLayoutRevision &+= 1
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                composerOwnsKeyboard = false
            }
            .task(id: keyboardLayoutRevision) {
                guard keyboardLayoutRevision > 0 else { return }
                // The system's did-change event bounds this correction to a settled keyboard.
                // Yield for SwiftUI's matching layout commit, without a timing-based retry loop.
                await Task.yield()
                guard !Task.isCancelled, scrollFollow.completeViewportTransition() else { return }
                pendingFollow?.cancel()
                pendingFollow = nil
                scrollToEnd(proxy)
            }
            #endif
            .onChangeCompat(of: scrollToTopSignal) { _ in
                scrollFollow.pause()
                pendingFollow?.cancel()
                pendingFollow = nil
                proxy.scrollTo("coach.top", anchor: .top)
            }
            .task(id: coach.messages.first?.id) {
                guard !coach.messages.isEmpty else { return }
                // A first preference may precede ScrollViewReader registering the restored rows.
                // Retry that initial placement after layout settles, but never after user navigation.
                for attempt in 0..<3 {
                    do { try await Task.sleep(nanoseconds: 150_000_000) }
                    catch { return }
                    guard scrollFollow.canPositionInitialTranscript else { return }
                    if attempt > 0, scrollFollow.isNearBottom { return }
                    scrollToEnd(proxy)
                }
            }
            .onDisappear {
                pendingFollow?.cancel()
                pendingFollow = nil
                scrollFollow.cancelViewportTransition()
                #if os(iOS)
                composerOwnsKeyboard = false
                #endif
            }
        }
    }

    private var emptyTranscript: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text("Ask your first question")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
            Text("Coach reads a summary of your last two weeks plus 30-day averages and recent workouts, then answers in plain language. Try a suggestion below.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(NoopMetrics.cardPadding)
        .background(NoopPanelSurface())
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: NoopMetrics.space8)
                Text(message.text)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .padding(NoopMetrics.space4)
                    .background(NoopPanelSurface(tint: StrandPalette.accent,
                                                cornerRadius: NoopVisualStyle.compactRadius))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You said: \(message.text)")
        case .assistant:
            // Render assistant Markdown with the shared theme; user text stays verbatim so typed
            // formatting characters do not turn into unexpected markup.
            // K8: context menu (long-press / right-click) with Copy, Share, and Save actions.
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Label("Coach", systemImage: "sparkles")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.accentInk)
                Markdown(message.text)
                    .markdownTheme(.strand)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // K8: Copy / Share / Save context menu on assistant replies.
                    .contextMenu {
                        Button {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                            #else
                            UIPasteboard.general.string = message.text
                            #endif
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        ShareLink(item: message.text) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            saveAdvice(message.text)
                        } label: {
                            Label("Save to Journal", systemImage: "square.and.pencil")
                        }
                    }
            }
            .padding(NoopMetrics.space4)
            .background(NoopPanelSurface())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Coach said: \(message.text)")
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: NoopMetrics.space2) {
            ProgressView().controlSize(.small).tint(StrandPalette.accent)
            Text("Coach is thinking…")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(NoopMetrics.space4)
        .background(NoopPanelSurface(cornerRadius: NoopVisualStyle.compactRadius))
        .accessibilityLabel("Coach is thinking")
    }

    private func errorBanner(_ message: String) -> some View {
        StrandCard(padding: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(StrandPalette.statusCritical)
                    .accessibilityHidden(true)
                Text(message)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    /// The inline replacement-key editor, shown after a rejection or an Update key action.
    ///
    /// Saving goes through `setKey`, which replaces the stored key and leaves the transcript alone. The
    /// existing route was the Disconnect button, which also wipes the conversation and un-commits a
    /// custom provider: far more than correcting a typo asks for, and named for an outcome the wearer
    /// is trying to avoid. Twin of the Kotlin editor in `CoachChat`.
    private var keyRepairPanel: some View {
        StrandCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                if coach.keyRejected {
                    Text("Paste the corrected key. Your conversation is kept.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SecureField("Paste your \(coach.provider.displayName) API key", text: $keyFix)
                    .textFieldStyle(.plain)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(StrandPalette.hairline, lineWidth: 1))
                    .onSubmit(saveRepairedKey)
                    .accessibilityLabel(coach.keyRejected ? Text("Corrected API key") : Text("API key"))
                HStack {
                    NoopButton("Update key", systemImage: "key.fill", kind: .primary, action: saveRepairedKey)
                        .disabled(keyFix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    if showKeyEditor && !coach.keyRejected {
                        Button("Cancel") { toggleKeyEditor() }
                    }
                }
            }
        }
    }

    /// Store the corrected key and drop it from view state. `setKey` clears the error and the rejection
    /// flag, which is what closes this panel.
    private func saveRepairedKey() {
        let trimmed = keyFix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coach.setKey(trimmed)
        guard coach.errorText == nil else { return }
        keyFix = ""
        showKeyEditor = false
    }

    private func toggleKeyEditor() {
        showKeyEditor.toggle()
        if !showKeyEditor { keyFix = "" }
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { prompt in
                    Button {
                        send(prompt)
                    } label: {
                        Text(prompt)
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .padding(.horizontal, NoopMetrics.space3)
                            .padding(.vertical, NoopMetrics.space2)
                            .frame(minHeight: NoopMetrics.controlHeight)
                            .background(StrandPalette.surfaceInset, in: Capsule(style: .continuous))
                            .overlay(Capsule(style: .continuous).strokeBorder(StrandPalette.hairline, lineWidth: 1))
                    }
                    // Liquid tap response: the physical settle-inward every tappable liquid
                    // affordance gets, replacing the flat `.plain` press.
                    .buttonStyle(LiquidPressStyle())
                    .disabled(coach.sending)
                    .accessibilityLabel("Suggested prompt: \(prompt)")
                }
            }
            .padding(.vertical, 1)
        }
    }

    /// K7: True when follow-up chips should show instead of the initial contextual chips —
    /// i.e. the transcript is non-empty, the last message is from the assistant, and a reply
    /// is not currently in flight.
    private var showFollowUpChips: Bool {
        guard let last = coach.messages.last, !coach.sending else { return false }
        return last.role == .assistant
    }

    /// K7: Follow-up suggestion chips shown after each assistant reply, so the user can dig
    /// deeper without typing. Uses the static `AICoachEngine.followUpSuggestions` list.
    private var followUpChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AICoachEngine.followUpSuggestions, id: \.self) { promptKey in
                    let prompt = NSLocalizedString(promptKey, comment: "Coach follow-up question")
                    Button {
                        send(prompt)
                    } label: {
                        Text(prompt)
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .padding(.horizontal, NoopMetrics.space3)
                            .padding(.vertical, NoopMetrics.space2)
                            .frame(minHeight: NoopMetrics.controlHeight)
                            .background(StrandPalette.surfaceInset, in: Capsule(style: .continuous))
                            .overlay(Capsule(style: .continuous).strokeBorder(StrandPalette.hairline, lineWidth: 1))
                    }
                    .buttonStyle(LiquidPressStyle())
                    .disabled(coach.sending)
                    .accessibilityLabel("Follow-up prompt: \(prompt)")
                }
            }
            .padding(.vertical, 1)
        }
    }

    /// K12: A subtle token estimate shown below the composer when the draft is non-empty.
    /// Uses the ~4 chars/token heuristic — an estimate only, not an exact tokenizer count.
    private func tokenEstimateBar(_ tokens: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "speedometer")
                .font(.system(size: 10))
                .foregroundStyle(StrandPalette.textTertiary)
            Text("~\(tokens) tokens")
                .font(StrandFont.captionNumber)
                .foregroundStyle(StrandPalette.textTertiary)
            if tokens > 8000 {
                Text("· may exceed small context windows")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(.top, 2)
    }

    /// The glass control floats by itself: no full-width opaque footer behind it. Native keyboard
    /// safe-area changes move the overlay; the shell separately reserves the dock when it is visible.
    private var floatingComposer: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            composer
            // Ordinary drafts need no technical counter. Keep the meaningful large-context warning.
            if composerFocused, let tokens = coach.estimatedTokens(forDraft: draft), tokens > 8000 {
                tokenEstimateBar(tokens)
                    .padding(.horizontal, NoopMetrics.space3)
            }
        }
        .padding(.horizontal, NoopMetrics.screenHPadding)
        .padding(.vertical, NoopMetrics.space2)
        .frame(maxWidth: NoopMetrics.pageMaxWidth)
        .frame(maxWidth: .infinity)
    }

    /// Compact mobile adaptation of Assistant Composer: input and actions share one row at rest.
    /// A multiline draft grows upward; 44-point controls remain reachable beside the last input line.
    private var composer: some View {
        HStack(alignment: .bottom, spacing: NoopMetrics.space2) {
            TextField("Message", text: $draft,
                      prompt: Text("Message").foregroundColor(StrandPalette.textSecondary),
                      axis: .vertical)
                .textFieldStyle(.plain)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1...4)
                .focused($composerFocused)
                .frame(minHeight: NoopMetrics.controlHeight, alignment: .center)
                .padding(.leading, NoopMetrics.space2)
                .onSubmit { send(draft) }
                .accessibilityLabel("Question")
            #if os(iOS)
            micButton
            #endif
            Button {
                if coach.sending { coach.stopResponse() } else { send(draft) }
            } label: {
                Image(systemName: coach.sending ? "stop.fill" : "arrow.up")
                    .font(StrandFont.headline)
                    .frame(width: NoopMetrics.controlHeight, height: NoopMetrics.controlHeight)
                    .foregroundStyle(StrandPalette.onAccent)
                    .background(StrandPalette.accent, in: Circle())
            }
            .buttonStyle(LiquidPressStyle())
            .disabled(!coach.sending && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(coach.sending ? Text("Stop response") : Text("Send"))
        }
        .padding(NoopMetrics.space2)
        .background(NoopPanelSurface(cornerRadius: NoopVisualStyle.cardRadius, elevated: true))
        .overlay(RoundedRectangle(cornerRadius: NoopVisualStyle.cardRadius, style: .continuous)
            .strokeBorder(composerFocused ? StrandPalette.focusRing : StrandPalette.hairline,
                          lineWidth: NoopMetrics.hairlineWidth))
        .accessibilityIdentifier("coach.floating-composer")
    }

    // MARK: - K4: Voice input (iOS only)

    #if os(iOS)
    /// Mic button: starts/stops on-device speech recognition. Disabled when the locale lacks
    /// on-device support or permission is denied; tapping when permission is not yet determined
    /// triggers the system prompt.
    private var micButton: some View {
        Button {
            toggleVoice()
        } label: {
            Group {
                if voiceInput.isRecording {
                    Image(systemName: "stop.circle.fill")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.statusCritical)
                } else {
                    Image(systemName: "mic.fill")
                        .font(StrandFont.subhead)
                        .foregroundStyle(micButtonEnabled ? StrandPalette.textSecondary : StrandPalette.textTertiary)
                }
            }
            .frame(width: NoopMetrics.controlHeight, height: NoopMetrics.controlHeight)
            .background(StrandPalette.surfaceInset,
                        in: Circle())
            .overlay(Circle()
                .strokeBorder(StrandPalette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!micButtonEnabled)
        .help(voiceInput.statusMessage ?? "Ask out loud")
        .accessibilityLabel(voiceInput.isRecording ? "Stop voice input" : "Voice input")
        .accessibilityHint(voiceInput.statusMessage ?? "Transcribes your question on-device")
    }

    /// Whether the mic button is tappable: not while sending, and only if voice is either
    /// already usable or permission hasn't been asked yet (first tap triggers the prompt).
    private var canUseVoice: Bool { voiceInput.canUseVoice }
    private var micButtonEnabled: Bool {
        !coach.sending && (canUseVoice || voiceInput.authorization == .notDetermined)
    }

    private func toggleVoice() {
        if voiceInput.isRecording {
            voiceInput.stopTranscribing { finalText in
                let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    // Append to the draft (not replace) so a user can speak into existing text.
                    draft = draft.isEmpty ? trimmed : "\(draft) \(trimmed)"
                }
            }
        } else {
            // First tap with undetermined permission triggers the system prompt; if granted,
            // start transcribing immediately on the next tap. If already authorized, start now.
            if voiceInput.authorization == .notDetermined {
                voiceInput.requestAuthorization { state in
                    if state == .authorized {
                        voiceInput.startTranscribing { partial in
                            draft = partial
                        }
                    }
                }
            } else {
                voiceInput.startTranscribing { partial in
                    draft = partial
                }
            }
        }
    }
    #endif

    private var privacyFootnote: some View {
        Label {
            NanashiPresencePrivacyText(fallback: Text(coach.isLocalDemo ? "Synthetic conversation. No API request is sent." : coach.provider == .custom
                 ? "Coach talks only to the server URL you set. Point it at a local model (Ollama, LM Studio, llama.cpp) to keep everything on your own machine. Nothing is sent until you ask."
                 : "This is the only feature that leaves \(Platform.deviceNounPhrase). It sends a summary of your metrics to \(coach.provider.displayName) using your own key. Nothing is sent until you ask."),
                 provider: coach.provider.displayName)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield")
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func saveKey() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coach.setKey(trimmed)
        if coach.errorText == nil { keyDraft = "" }
    }

    /// Commit the Custom (local) provider: save an optional key, then connect on the entered URL.
    private func connectCustom() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            coach.setKey(trimmed)
            keyDraft = ""
        }
        coach.connectCustom()
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !coach.sending else { return }
        draft = ""
        composerFocused = false
        scrollFollow.showLatest()
        Task { await coach.send(trimmed) }
    }

    /// K14: Trigger a subtle haptic when the Coach reply arrives. On iOS, a light impact feedback.
    /// macOS doesn't have an equivalent simple API, so it's a no-op there.
    private func triggerReplyHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    /// K8: Save a coach reply to the journal as a note, so it appears alongside other journal
    /// entries in Insights and can be reviewed later. Uses the existing journal API with a
    /// fixed question ("Coach advice") and the reply text in the notes field.
    private func saveAdvice(_ text: String) {
        guard !coach.isLocalDemo else { return }
        let day = Repository.localDayKey(Date())
        Task {
            await repo.saveJournalAnswer(
                day: day,
                question: "Coach advice",
                answeredYes: true,
                notes: text
            )
        }
    }

    /// Coalesce layout changes while streaming. No animation or per-token scroll; cancel promptly
    /// when the reader takes control or leaves the screen.
    private func scheduleFollow(_ proxy: ScrollViewProxy) {
        guard scrollFollow.shouldFollow, pendingFollow == nil else { return }
        pendingFollow = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 100_000_000) }
            catch { return }
            pendingFollow = nil
            guard scrollFollow.shouldFollow else { return }
            scrollToEnd(proxy)
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        proxy.scrollTo("coach.end", anchor: .bottom)
    }
}

private struct CoachTranscriptFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

/// Measures only composer height, never scroll position or a per-frame transformed rectangle.
private struct CoachComposerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
