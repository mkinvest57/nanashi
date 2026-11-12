import Foundation

/// Stable destinations for optional inline remarks. Unknown model-supplied destinations never render.
enum NanashiPresenceScene: String, CaseIterable, Codable, Sendable {
    case day, sleep, activity, trends, explore, general
}

/// A short, complete remark. Parsing never truncates a sentence or fabricates a missing scene.
struct NanashiPresenceRemark: Identifiable, Equatable, Codable, Sendable {
    let scene: NanashiPresenceScene
    let text: String

    var id: String { scene.rawValue }

    static let maximumTextLength = 320
    static let maximumRemarks = 6

    /// Accept a complete JSON object/array, optionally enclosed in one JSON Markdown fence.
    /// Invalid entries are ignored independently; the first valid entry wins for each scene.
    static func decode(_ response: String) -> [NanashiPresenceRemark] {
        guard let json = unwrappedJSON(response), let data = json.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) else { return [] }

        let entries: [Any]
        if let object = value as? [String: Any], let remarks = object["remarks"] as? [Any] {
            entries = remarks
        } else if let array = value as? [Any] {
            entries = array
        } else {
            return []
        }

        var seen = Set<NanashiPresenceScene>()
        var result: [NanashiPresenceRemark] = []
        for entry in entries {
            guard let object = entry as? [String: Any],
                  let rawScene = object["scene"] as? String,
                  let scene = NanashiPresenceScene(rawValue: rawScene.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let rawText = object["text"] as? String else { continue }
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= maximumTextLength,
                  text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
                  seen.insert(scene).inserted else { continue }
            result.append(NanashiPresenceRemark(scene: scene, text: text))
            if result.count == maximumRemarks { break }
        }
        return result
    }

    private static func unwrappedJSON(_ response: String) -> String? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        let lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 3,
              let first = lines.first?.trimmingCharacters(in: .whitespaces),
              first == "```" || first.lowercased() == "```json",
              lines.last?.trimmingCharacters(in: .whitespaces) == "```" else { return nil }
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }
}

/// Small non-health request metadata, separate from the generated content and transport.
/// Day keys use the app's canonical, lexically ordered YYYY-MM-DD representation.
struct NanashiPresenceBudget: Codable, Equatable, Sendable {
    var dayKey: String
    var attemptCount: Int
    var lastAttempt: Date?
    var blockedUntil: Date?
    var maxAttemptsPerDay: Int
    var minInterval: TimeInterval
    var failureBackoff: TimeInterval

    init(dayKey: String = "", attemptCount: Int = 0, lastAttempt: Date? = nil,
         blockedUntil: Date? = nil, maxAttemptsPerDay: Int = 4,
         minInterval: TimeInterval = 30 * 60, failureBackoff: TimeInterval = 15 * 60) {
        self.dayKey = dayKey
        self.attemptCount = attemptCount
        self.lastAttempt = lastAttempt
        self.blockedUntil = blockedUntil
        self.maxAttemptsPerDay = maxAttemptsPerDay
        self.minInterval = minInterval
        self.failureBackoff = failureBackoff
    }

    /// A new day resets only the daily count, never the elapsed-time or failure gates.
    /// Moving the clock or canonical day backwards cannot replenish the budget.
    func canRequest(now: Date, dayKey requestedDay: String) -> Bool {
        guard now.timeIntervalSinceReferenceDate.isFinite, !requestedDay.isEmpty,
              maxAttemptsPerDay > 0, minInterval.isFinite, minInterval >= 0,
              failureBackoff.isFinite, failureBackoff >= 0,
              dayKey.isEmpty || requestedDay >= dayKey else { return false }
        if let lastAttempt {
            guard lastAttempt.timeIntervalSinceReferenceDate.isFinite,
                  now.timeIntervalSince(lastAttempt) >= minInterval else { return false }
        }
        if let blockedUntil {
            guard blockedUntil.timeIntervalSinceReferenceDate.isFinite,
                  now >= blockedUntil else { return false }
        }
        let attempts = requestedDay == dayKey ? max(0, attemptCount) : 0
        return attempts < maxAttemptsPerDay
    }

    /// Record before starting transport, so failed and cancelled attempts consume the same allowance.
    /// Calls are recorded even if a caller disregards canRequest; they cannot move the clock backwards.
    mutating func recordAttempt(now: Date, dayKey requestedDay: String) {
        guard now.timeIntervalSinceReferenceDate.isFinite, !requestedDay.isEmpty else { return }
        let clockDidNotRewind = lastAttempt.map { now >= $0 } ?? true
        if clockDidNotRewind && (dayKey.isEmpty || requestedDay > dayKey) {
            dayKey = requestedDay
            attemptCount = 0
        }
        let count = max(0, attemptCount)
        attemptCount = count == Int.max ? Int.max : count + 1
        if lastAttempt.map({ now >= $0 }) ?? true { lastAttempt = now }
    }

    /// Failure adds a backoff without counting the already-recorded attempt twice.
    mutating func recordFailure(now: Date) {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              failureBackoff.isFinite, failureBackoff >= 0 else { return }
        let anchor = max(now, lastAttempt ?? now)
        let deadline = anchor.addingTimeInterval(failureBackoff)
        guard deadline.timeIntervalSinceReferenceDate.isFinite else { return }
        blockedUntil = max(blockedUntil ?? deadline, deadline)
    }
}
