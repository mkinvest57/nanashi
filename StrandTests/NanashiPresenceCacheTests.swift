import XCTest
@testable import Strand

/// Device-local cache checks use temporary files, synthetic remarks and an explicit clock.
final class NanashiPresenceCacheTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)
    private let context = "synthetic-device|provider|model|fr|consent"

    private func batch(contextKey: String? = nil, generatedAt: Date? = nil,
                       remarks: [NanashiPresenceRemark]? = nil, version: Int = 1) -> NanashiPresenceCachedBatch {
        NanashiPresenceCachedBatch(contextKey: contextKey ?? context, generatedAt: generatedAt ?? instant,
                                   remarks: remarks ?? [.init(scene: .sleep, text: "A synthetic remark.")],
                                   version: version)
    }

    private func withCache(_ operation: (NanashiPresenceCache) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NanashiPresenceCacheTests-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try operation(NanashiPresenceCache(fileURL: root.appendingPathComponent("remarks.json")))
    }

    func testUsabilityRequiresMatchingContextAndStrictFreshnessWindow() {
        let saved = batch()
        XCTAssertTrue(saved.usable(contextKey: context, now: instant))
        XCTAssertTrue(saved.usable(contextKey: context, now: instant.addingTimeInterval(6 * 60 * 60 - 1)))
        XCTAssertFalse(saved.usable(contextKey: "other-device-or-provider", now: instant))
        XCTAssertFalse(saved.usable(contextKey: context, now: instant.addingTimeInterval(6 * 60 * 60)))
        XCTAssertFalse(saved.usable(contextKey: context, now: instant.addingTimeInterval(-1)))
        XCTAssertFalse(saved.usable(contextKey: context, now: Date(timeIntervalSince1970: .infinity)))
    }

    func testMalformedEnvelopeNeverBecomesUsable() {
        let invalid = [
            batch(contextKey: " "),
            batch(version: 2),
            batch(generatedAt: Date(timeIntervalSince1970: .infinity)),
            batch(remarks: []),
            batch(remarks: [.init(scene: .sleep, text: "First."), .init(scene: .sleep, text: "Duplicate.")]),
            batch(remarks: [.init(scene: .sleep, text: "")]),
            batch(remarks: [.init(scene: .sleep, text: " Padded.")]),
            batch(remarks: [.init(scene: .sleep, text: "Two\nlines")]),
            batch(remarks: [.init(scene: .sleep, text: String(repeating: "x", count: 321))]),
            batch(contextKey: String(repeating: "x", count: NanashiPresenceCachedBatch.maximumByteCount))
        ]
        for value in invalid {
            XCTAssertFalse(value.usable(contextKey: value.contextKey, now: instant))
        }
    }

    func testAtomicRoundTripAndReplacementRemainExcludedFromBackup() throws {
        try withCache { cache in
            let first = batch()
            XCTAssertTrue(cache.save(first))
            XCTAssertEqual(cache.load(), first)
            let second = batch(remarks: [.init(scene: .day, text: "Replacement synthetic remark.")])
            XCTAssertTrue(cache.save(second))
            XCTAssertEqual(cache.load(), second)
            XCTAssertEqual(try cache.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
            XCTAssertEqual(try cache.fileURL.deletingLastPathComponent()
                .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
            let attributes = try FileManager.default.attributesOfItem(atPath: cache.fileURL.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }

    func testCorruptOversizedAndUnknownVersionFilesAreQuietMisses() throws {
        try withCache { cache in
            XCTAssertNil(cache.load())
            try FileManager.default.createDirectory(at: cache.fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            var oversizedValidPrefix = try JSONEncoder().encode(batch())
            oversizedValidPrefix.append(Data(repeating: 0x20,
                count: NanashiPresenceCachedBatch.maximumByteCount + 1 - oversizedValidPrefix.count))
            for data in [Data("{broken".utf8), oversizedValidPrefix,
                         Data(repeating: 0x20, count: NanashiPresenceCachedBatch.maximumByteCount + 1),
                         try JSONEncoder().encode(batch(version: 99))] {
                try data.write(to: cache.fileURL)
                XCTAssertNil(cache.load())
            }
        }
    }

    func testRejectedSaveDoesNotReplaceThePreviousValidBatch() throws {
        try withCache { cache in
            let first = batch()
            XCTAssertTrue(cache.save(first))
            XCTAssertFalse(cache.save(batch(remarks: [.init(scene: .sleep, text: "Bad\u{0000}text.")])))
            XCTAssertEqual(cache.load(), first)
        }
    }

    func testClearIsIdempotentAndRemovesTheCachedRemarks() throws {
        try withCache { cache in
            XCTAssertTrue(cache.save(batch()))
            cache.clear()
            XCTAssertFalse(FileManager.default.fileExists(atPath: cache.fileURL.path))
            XCTAssertNil(cache.load())
            cache.clear()
            XCTAssertNil(cache.load())
        }
    }

    func testUnavailableDirectoryFailsWithoutThrowing() throws {
        try withCache { cache in
            let directory = cache.fileURL.deletingLastPathComponent()
            try Data("A file cannot be a cache directory.".utf8).write(to: directory)
            XCTAssertFalse(cache.save(batch()))
            XCTAssertNil(cache.load())
        }
    }
}
