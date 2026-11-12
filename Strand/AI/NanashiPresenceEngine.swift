import Foundation
import Combine

/// Foreground-only, separately opted-in remarks. One bounded request supplies all page slots.
/// A protected, short-lived local cache keeps dated observations available across app launches.
@MainActor
final class NanashiPresenceEngine: ObservableObject {
    static let enabledKey = "ai.presence.enabled"
    static let budgetKey = "ai.presence.budget"
    @Published var enabled: Bool {
        didSet {
            if !isDemo && !restoringConsent { defaults.set(enabled, forKey: Self.enabledKey) }
            if !enabled { clear() }
        }
    }
    @Published private(set) var generatedAt: Date?
    @Published private(set) var isGenerating = false
    @Published private(set) var configurationKey = ""
    @Published private(set) var hasNewerReadings = false
    @Published private var remarks: [NanashiPresenceRemark] = []
    @Published private var dismissed: Set<NanashiPresenceScene> = []
    private let defaults: UserDefaults
    private let available: () -> Bool
    private let busy: () -> Bool
    private let demo: () -> Bool
    private let configuration: () -> String
    private let dataRevision: () -> UInt64
    private let dataReady: () -> Bool
    private let cacheIdentity: () -> String
    private let cache: NanashiPresenceCache?
    private let refreshAccess: () -> Void
    private let generate: () async throws -> [NanashiPresenceRemark]
    private let clock: () -> Date
    private var budget: NanashiPresenceBudget
    private var pending: Task<Void, Never>?
    private var requestID: UUID?
    private var subscriptions = Set<AnyCancellable>()
    private var demoConfigured = false
    private var restoringConsent = false
    private var synchronizationQueued = false
    private var needsAccessRefresh = true
    private var snapshotRevision: UInt64?
    private var restoredCache = false

    var isDemo: Bool { demo() }
    var isAvailable: Bool { isDemo || available() }

    init(defaults: UserDefaults = .standard, available: @escaping () -> Bool,
         busy: @escaping () -> Bool = { false }, demo: @escaping () -> Bool = { false },
         configuration: @escaping () -> String,
         dataRevision: @escaping () -> UInt64 = { 0 },
         dataReady: @escaping () -> Bool = { true },
         cacheIdentity: (() -> String)? = nil,
         cache: NanashiPresenceCache? = nil,
         refreshAccess: @escaping () -> Void = {},
         clock: @escaping () -> Date = Date.init,
         generate: @escaping () async throws -> [NanashiPresenceRemark]) {
        self.defaults = defaults
        self.available = available
        self.busy = busy
        self.demo = demo
        self.configuration = configuration
        self.dataRevision = dataRevision
        self.dataReady = dataReady
        self.cacheIdentity = cacheIdentity ?? configuration
        self.cache = cache
        self.refreshAccess = refreshAccess
        self.generate = generate
        self.clock = clock
        self.enabled = defaults.bool(forKey: Self.enabledKey)
        self.budget = defaults.data(forKey: Self.budgetKey)
            .flatMap { try? JSONDecoder().decode(NanashiPresenceBudget.self, from: $0) } ?? .init()
        configurationKey = configuration()
    }

    convenience init(coach: AICoachEngine, repo: Repository) {
        self.init(available: { coach.presenceAvailable }, busy: { coach.sending },
                  demo: { coach.isLocalDemo }, configuration: { coach.presenceConfigurationKey },
                  dataRevision: { coach.presenceDataRevision }, dataReady: { coach.presenceDataReady },
                  cacheIdentity: { coach.presenceCacheIdentity }, cache: NanashiPresenceCache(),
                  refreshAccess: { coach.refreshPresenceAccess() },
                  generate: { try await coach.generatePresenceRemarks() })
        // Published notifications precede mutations. Resolve the actual state on the next actor turn.
        coach.objectWillChange.sink { [weak self] _ in
            self?.queueSynchronization()
        }.store(in: &subscriptions)
        repo.$days.dropFirst().debounce(for: .seconds(1), scheduler: RunLoop.main).sink { [weak self] _ in
            self?.synchronizeConfiguration()
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.queueSynchronization() }
        }.store(in: &subscriptions)
    }

    private func queueSynchronization() {
        guard !synchronizationQueued else { return }
        synchronizationQueued = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.synchronizationQueued = false
            self.synchronizeConfiguration()
        }
    }

    /// Permission/source changes retire observations. Measurement updates mark their dated snapshot
    /// without blanking the page or cancelling a response already being generated from that snapshot.
    func synchronizeConfiguration() {
        if isDemo && !demoConfigured {
            demoConfigured = true
            enabled = true
        } else if !isDemo && demoConfigured {
            clear()
            demoConfigured = false
            restoringConsent = true
            enabled = defaults.bool(forKey: Self.enabledKey)
            restoringConsent = false
        }
        let current = configuration()
        if current != configurationKey {
            // Startup hydration changes the empty-source identity before the cache can be restored.
            clear(removeCache: generatedAt != nil || pending != nil)
            configurationKey = current
            restoredCache = false
        }
        if enabled && !isAvailable { clear() }
        if let snapshotRevision, snapshotRevision != dataRevision(), !hasNewerReadings {
            hasNewerReadings = true
        }
        if busy() { suspend() }
    }

    func remark(for scene: NanashiPresenceScene) -> NanashiPresenceRemark? {
        guard enabled, !dismissed.contains(scene), let generatedAt,
              isAvailable, configurationKey == configuration(),
              clock().timeIntervalSince(generatedAt) >= 0,
              clock().timeIntervalSince(generatedAt) < 6 * 60 * 60 else { return nil }
        return remarks.first { $0.scene == scene } ?? remarks.first { $0.scene == .general }
    }

    func dismiss(_ scene: NanashiPresenceScene) { dismissed.insert(scene) }

    /// Hosts call this on a visible page, never from a timer or a background scheduler.
    /// The owned task survives navigation; suspending the app or revoking consent cancels it.
    func refreshIfNeeded() async {
        guard enabled || isDemo || demoConfigured else { return }
        if needsAccessRefresh {
            refreshAccess()
            needsAccessRefresh = false
        }
        synchronizeConfiguration()
        guard enabled, isAvailable, !busy(), pending == nil, dataReady() else { return }
        if isDemo {
            if remarks.isEmpty || generatedAt.map({ clock().timeIntervalSince($0) >= 6 * 60 * 60 }) == true {
                remarks = Self.demoRemarks
                generatedAt = clock()
            }
            return
        }
        let now = clock()
        if !restoredCache {
            restoredCache = true
            if let saved = cache?.load(), saved.usable(contextKey: cacheIdentity(), now: now) {
                remarks = saved.remarks
                generatedAt = saved.generatedAt
                // A prior launch's readings cannot be compared to a process-local revision counter.
                hasNewerReadings = true
            }
        }
        if let generatedAt, now.timeIntervalSince(generatedAt) < 30 * 60 { return }
        let dayKey = Repository.localDayKey(now)
        guard budget.canRequest(now: now, dayKey: dayKey) else { return }
        budget.recordAttempt(now: now, dayKey: dayKey)
        saveBudget()
        let id = UUID(), signature = configurationKey, revision = dataRevision()
        let savedIdentity = cacheIdentity()
        requestID = id
        isGenerating = true
        pending = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.requestID == id {
                    self.pending = nil
                    self.requestID = nil
                    self.isGenerating = false
                }
            }
            do {
                let result = try await self.generate()
                guard !Task.isCancelled, self.requestID == id, self.enabled, self.isAvailable,
                      self.configuration() == signature else { return }
                guard !result.isEmpty else { throw AICoachError.decode }
                self.remarks = result
                self.generatedAt = now
                self.snapshotRevision = revision
                self.hasNewerReadings = revision != self.dataRevision()
                self.cache?.save(NanashiPresenceCachedBatch(contextKey: savedIdentity,
                                                          generatedAt: now, remarks: result))
                // A dismissed scene stays quiet for this app session, including later batches.
            } catch {
                guard self.requestID == id, !Task.isCancelled else { return }
                self.budget.recordFailure(now: self.clock())
                self.saveBudget()
                // Keep a still-current, timestamped batch on transient failure. No error spam in pages.
            }
        }
    }

    func suspend() {
        pending?.cancel()
        pending = nil
        requestID = nil
        if isGenerating { isGenerating = false }
    }

    func leaveForeground() {
        needsAccessRefresh = true
        suspend()
    }

    private func clear(removeCache: Bool = true) {
        suspend()
        if !remarks.isEmpty { remarks = [] }
        if generatedAt != nil { generatedAt = nil }
        if hasNewerReadings { hasNewerReadings = false }
        snapshotRevision = nil
        if removeCache && !isDemo { cache?.clear() }
    }

    private func saveBudget() {
        if let data = try? JSONEncoder().encode(budget) { defaults.set(data, forKey: Self.budgetKey) }
    }

    /// Clearly labelled local fixtures; never used on a physical device or sent to a provider.
    private static let demoRemarks: [NanashiPresenceRemark] = [
        .init(scene: .day, text: "Tu as récupéré. Ce n’est pas une invitation à rembourser toute ta semaine de sport en une séance. Garde un peu de talent pour demain."),
        .init(scene: .sleep, text: "Le sommeil profond ne se négocie pas avec un dernier épisode. Tes nuits régulières font mieux le travail que tes grandes intentions."),
        .init(scene: .activity, text: "La prochaine séance doit prolonger ta progression, pas servir de vengeance contre ton canapé. Choisis une intensité que tu peux répéter."),
        .init(scene: .trends, text: "Un bon jour, c’est sympathique. Une tendance, c’est plus convaincant. Regarde ta semaine avant de te décerner une médaille."),
        .init(scene: .explore, text: "Tu peux explorer tous les réglages. Aucun ne transforme cinq heures de sommeil en huit. J’ai vérifié."),
        .init(scene: .general, text: "Les chiffres ont un contexte. Je sais, c’est moins pratique qu’un score à brandir comme un diplôme. Compare plusieurs jours avant de conclure.")
    ]
}
