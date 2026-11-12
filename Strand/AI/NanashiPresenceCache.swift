import Foundation

/// A bounded, device-local copy of generated remarks, never credentials or raw sensor history.
/// Context identity and freshness are checked again before a caller may restore the batch.
struct NanashiPresenceCachedBatch: Codable, Equatable, Sendable {
    static let formatVersion = 1
    static let maximumAge: TimeInterval = 6 * 60 * 60
    static let maximumByteCount = 16 * 1024

    let version: Int
    let contextKey: String
    let generatedAt: Date
    let remarks: [NanashiPresenceRemark]

    init(contextKey: String, generatedAt: Date, remarks: [NanashiPresenceRemark],
         version: Int = Self.formatVersion) {
        self.version = version
        self.contextKey = contextKey
        self.generatedAt = generatedAt
        self.remarks = remarks
    }

    func usable(contextKey expectedContext: String, now: Date) -> Bool {
        guard contextKey == expectedContext, now.timeIntervalSinceReferenceDate.isFinite else { return false }
        let age = now.timeIntervalSince(generatedAt)
        return age >= 0 && age < Self.maximumAge && storageData != nil
    }

    /// Shared validation for disk reads, writes and restoration. Reject the entire envelope rather
    /// than partially restoring a malformed batch under an otherwise valid identity.
    fileprivate var storageData: Data? {
        guard version == Self.formatVersion,
              !contextKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              contextKey.utf8.count <= Self.maximumByteCount,
              generatedAt.timeIntervalSinceReferenceDate.isFinite,
              !remarks.isEmpty, remarks.count <= NanashiPresenceRemark.maximumRemarks else { return nil }
        var scenes = Set<NanashiPresenceScene>()
        for remark in remarks {
            guard !remark.text.isEmpty,
                  remark.text == remark.text.trimmingCharacters(in: .whitespacesAndNewlines),
                  remark.text.utf8.count <= Self.maximumByteCount,
                  remark.text.count <= NanashiPresenceRemark.maximumTextLength,
                  remark.text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
                  scenes.insert(remark.scene).inserted else { return nil }
        }
        guard let data = try? JSONEncoder().encode(self), data.count <= Self.maximumByteCount else { return nil }
        return data
    }
}

/// Optional small cache. All failures become a cache miss; the existing app and generation path
/// remain usable. A supplied URL isolates tests from the user's actual app container.
struct NanashiPresenceCache {
    let fileURL: URL

    static var defaultFileURL: URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("NanashiCoach", isDirectory: true)
            .appendingPathComponent("remarks.json")
    }

    init(fileURL: URL = Self.defaultFileURL) { self.fileURL = fileURL }

    func load() -> NanashiPresenceCachedBatch? {
        guard fileURL.isFileURL else { return nil }
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            // Bound the read itself rather than trusting a size check that could race a replacement.
            var data = Data()
            while data.count <= NanashiPresenceCachedBatch.maximumByteCount {
                let remaining = NanashiPresenceCachedBatch.maximumByteCount + 1 - data.count
                guard let chunk = try handle.read(upToCount: remaining), !chunk.isEmpty else { break }
                data.append(chunk)
            }
            guard !data.isEmpty, data.count <= NanashiPresenceCachedBatch.maximumByteCount,
                  let batch = try? JSONDecoder().decode(NanashiPresenceCachedBatch.self, from: data),
                  batch.storageData != nil else { return nil }
            return batch
        } catch { return nil }
    }

    @discardableResult
    func save(_ batch: NanashiPresenceCachedBatch) -> Bool {
        guard fileURL.isFileURL, let data = batch.storageData else { return false }
        let manager = FileManager.default
        var directory = fileURL.deletingLastPathComponent()
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            var excluded = URLResourceValues()
            excluded.isExcludedFromBackup = true
            try directory.setResourceValues(excluded)
            #if os(iOS)
            // Remarks are foreground-only, so locked-device access is unnecessary.
            try manager.setAttributes([.protectionKey: FileProtectionType.complete],
                                      ofItemAtPath: directory.path)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: fileURL, options: .atomic)
            #endif
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            var writtenURL = fileURL
            try writtenURL.setResourceValues(excluded)
            return true
        } catch { return false }
    }

    func clear() { try? FileManager.default.removeItem(at: fileURL) }
}
