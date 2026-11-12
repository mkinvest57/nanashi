import Foundation

/// Explicit handover between two installations that own different HealthKit source identities.
/// The old source remains in Health; only new samples are exported by the replacement installation.
/// This is an Apple-only installation policy, not a change to analytics or the portable store schema.
struct HealthKitIdentityMigration: Equatable {
    static let defaultsKey = "hkIdentityMigration.v1"

    let previousBundleIdentifiers: Set<String>
    let cutover: Date?

    static let none = HealthKitIdentityMigration(previousBundleIdentifiers: [], cutover: nil)

    enum InvalidRecord: Error {
        case malformed
        case destinationMismatch
    }

    /// An absent record preserves normal behavior. A partial or misdirected record must not silently
    /// enable historical exports; the caller stops its sync and leaves existing data untouched.
    static func load(defaults: UserDefaults = .standard,
                     currentBundleIdentifier: String? = Bundle.main.bundleIdentifier) throws -> Self {
        guard let raw = defaults.object(forKey: defaultsKey) else { return .none }
        return try decode(raw, currentBundleIdentifier: currentBundleIdentifier)
    }

    /// Decode a handover before it has been installed into any preference domain.
    static func decode(_ raw: Any, currentBundleIdentifier: String?) throws -> Self {
        guard let record = raw as? [String: Any],
              let destination = record["destinationBundleIdentifier"] as? String,
              let previous = record["previousBundleIdentifiers"] as? [String],
              !previous.isEmpty,
              previous.allSatisfy({ !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
              !previous.contains(destination),
              let timestamp = record["cutoverEpochSeconds"] as? Double,
              timestamp.isFinite, timestamp > 0, timestamp < 253_402_300_800 else {
            throw InvalidRecord.malformed
        }
        guard !destination.isEmpty, destination == currentBundleIdentifier else {
            throw InvalidRecord.destinationMismatch
        }
        return Self(previousBundleIdentifiers: Set(previous), cutover: Date(timeIntervalSince1970: timestamp))
    }

    func excludesSource(bundleIdentifier: String) -> Bool {
        previousBundleIdentifiers.contains(bundleIdentifier)
    }

    func writeStart(from proposed: Int) -> Int {
        guard let cutover else { return proposed }
        return max(proposed, Int(ceil(cutover.timeIntervalSince1970)))
    }

    /// Whole sessions that cross the handover stay with the old source. Neither their immutable key
    /// nor an edited span may predate the handover; otherwise an edit could recreate old history.
    func allowsSession(keyStart: Int, spanStart: Int) -> Bool {
        guard let cutover else { return true }
        return Double(min(keyStart, spanStart)) >= cutover.timeIntervalSince1970
    }

    /// Daily values can already have been written at noon or wake time. The cutover day therefore
    /// stays with the old source even when a newly computed value would have a later timestamp.
    func allowsDailyWrite(dayStart: Date) -> Bool {
        guard let cutover else { return true }
        return dayStart > cutover
    }
}
