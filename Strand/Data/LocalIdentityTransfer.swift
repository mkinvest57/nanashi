import Foundation
import CoreFoundation

/// Explicit, local bootstrap for an installation handover. The caller gates this behind its DEBUG
/// launch argument and runs it before constructing models that read or publish preferences.
enum LocalIdentityTransfer {
    enum TransferError: Error {
        case missingPayload, malformedPayload, destinationMismatch, missingHealthHandover
        case unsupportedPreferenceValue, defaultsUnavailable, persistenceFailed, rollbackFailed
        case consumedPayloadConflict
    }

    struct Payload {
        let preferences: [String: Any]
        let groupPreferences: [String: Any]
    }

    /// This validation has no persistent side effects and never includes preference values in errors.
    static func validate(_ data: Data, expectedBundleIdentifier: String,
                         expectedAppGroupIdentifier: String) throws -> Payload {
        guard !expectedBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !expectedAppGroupIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              expectedBundleIdentifier != expectedAppGroupIdentifier,
              let raw = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let record = raw as? [String: Any],
              let version = record["formatVersion"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              let destination = record["destinationBundleIdentifier"] as? String,
              let group = record["destinationAppGroupIdentifier"] as? String,
              let preferences = record["preferences"] as? [String: Any],
              let groupPreferences = record["groupPreferences"] as? [String: Any] else {
            throw TransferError.malformedPayload
        }
        guard destination == expectedBundleIdentifier, group == expectedAppGroupIdentifier else {
            throw TransferError.destinationMismatch
        }
        guard isSafePropertyList(preferences), isSafePropertyList(groupPreferences) else {
            throw TransferError.unsupportedPreferenceValue
        }
        guard let marker = preferences[HealthKitIdentityMigration.defaultsKey] as? [String: Any],
              let timestamp = marker["cutoverEpochSeconds"] as? NSNumber,
              CFGetTypeID(timestamp) != CFBooleanGetTypeID() else {
            throw TransferError.missingHealthHandover
        }
        do {
            let policy = try HealthKitIdentityMigration.decode(marker, currentBundleIdentifier: destination)
            guard policy.cutover != nil, !policy.previousBundleIdentifiers.isEmpty else {
                throw TransferError.missingHealthHandover
            }
        } catch {
            throw TransferError.missingHealthHandover
        }
        return Payload(preferences: preferences, groupPreferences: groupPreferences)
    }

    /// Replaces both domains through cfprefsd, verifies their readback, and atomically renames the
    /// payload only after success. A failed operation restores both original domains. Repeated runs
    /// recognize the consumed payload and never overwrite settings changed since the handover.
    @discardableResult
    static func apply(payloadURL: URL, expectedBundleIdentifier: String,
                      expectedAppGroupIdentifier: String, defaults: UserDefaults = .standard,
                      groupDefaults: UserDefaults? = nil) throws -> Bool {
        let files = FileManager.default
        let appliedURL = payloadURL.deletingPathExtension().appendingPathExtension("applied.plist")
        if files.fileExists(atPath: appliedURL.path) {
            guard !files.fileExists(atPath: payloadURL.path) else { throw TransferError.consumedPayloadConflict }
            let applied = try validate(Data(contentsOf: appliedURL), expectedBundleIdentifier: expectedBundleIdentifier,
                                        expectedAppGroupIdentifier: expectedAppGroupIdentifier)
            let actualMarker = defaults.persistentDomain(forName: expectedBundleIdentifier)?[HealthKitIdentityMigration.defaultsKey]
                as? [String: Any]
            let expectedMarker = applied.preferences[HealthKitIdentityMigration.defaultsKey] as? [String: Any]
            guard actualMarker != nil, sameDomain(actualMarker, expectedMarker) else {
                throw TransferError.persistenceFailed
            }
            return false
        }
        guard files.fileExists(atPath: payloadURL.path) else { throw TransferError.missingPayload }
        let data = try Data(contentsOf: payloadURL)
        let payload = try validate(data, expectedBundleIdentifier: expectedBundleIdentifier,
                                   expectedAppGroupIdentifier: expectedAppGroupIdentifier)
        guard let groupDefaults = groupDefaults ?? UserDefaults(suiteName: expectedAppGroupIdentifier) else {
            throw TransferError.defaultsUnavailable
        }
        let previous = defaults.persistentDomain(forName: expectedBundleIdentifier)
        let previousGroup = groupDefaults.persistentDomain(forName: expectedAppGroupIdentifier)
        // Retain a local rollback snapshot even after success. It contains only the destination's
        // pre-transfer state; the complete source remains in the consumed payload and original backup.
        let rollbackURL = payloadURL.deletingPathExtension().appendingPathExtension("rollback.plist")
        let rollback: [String: Any] = [
            "formatVersion": 1,
            "destinationBundleIdentifier": expectedBundleIdentifier,
            "destinationAppGroupIdentifier": expectedAppGroupIdentifier,
            "hadPreferences": previous != nil,
            "hadGroupPreferences": previousGroup != nil,
            "preferences": previous ?? [:],
            "groupPreferences": previousGroup ?? [:],
        ]
        let rollbackData = try PropertyListSerialization.data(fromPropertyList: rollback, format: .binary, options: 0)
        try rollbackData.write(to: rollbackURL, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: rollbackURL.path)
        do {
            defaults.setPersistentDomain(payload.preferences, forName: expectedBundleIdentifier)
            groupDefaults.setPersistentDomain(payload.groupPreferences, forName: expectedAppGroupIdentifier)
            let stored = defaults.synchronize()
            let groupStored = groupDefaults.synchronize()
            guard stored, groupStored,
                  sameDomain(defaults.persistentDomain(forName: expectedBundleIdentifier), payload.preferences),
                  sameDomain(groupDefaults.persistentDomain(forName: expectedAppGroupIdentifier), payload.groupPreferences) else {
                throw TransferError.persistenceFailed
            }
            try files.moveItem(at: payloadURL, to: appliedURL)
            return true
        } catch {
            restore(previous, in: defaults, named: expectedBundleIdentifier)
            restore(previousGroup, in: groupDefaults, named: expectedAppGroupIdentifier)
            let restored = defaults.synchronize()
            let groupRestored = groupDefaults.synchronize()
            guard restored, groupRestored,
                  sameDomain(defaults.persistentDomain(forName: expectedBundleIdentifier), previous),
                  sameDomain(groupDefaults.persistentDomain(forName: expectedAppGroupIdentifier), previousGroup) else {
                throw TransferError.rollbackFailed
            }
            throw error
        }
    }

    private static func restore(_ domain: [String: Any]?, in defaults: UserDefaults, named name: String) {
        if let domain { defaults.setPersistentDomain(domain, forName: name) }
        else { defaults.removePersistentDomain(forName: name) }
    }

    private static func sameDomain(_ lhs: [String: Any]?, _ rhs: [String: Any]?) -> Bool {
        // cfprefsd may represent a removed domain as an empty dictionary.
        NSDictionary(dictionary: lhs ?? [:]).isEqual(to: rhs ?? [:])
    }

    private static func isSafePropertyList(_ value: Any) -> Bool {
        switch value {
        case is String, is Data: return true
        case let date as Date: return date.timeIntervalSinceReferenceDate.isFinite
        case let number as NSNumber: return number.doubleValue.isFinite
        case let array as [Any]: return array.allSatisfy(isSafePropertyList)
        case let dictionary as [String: Any]: return dictionary.values.allSatisfy(isSafePropertyList)
        default: return false
        }
    }
}
