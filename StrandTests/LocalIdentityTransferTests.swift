import XCTest
@testable import Strand

final class LocalIdentityTransferTests: XCTestCase {
    private var appName = ""
    private var groupName = ""
    private var directory: URL!
    private var app: UserDefaults!
    private var group: UserDefaults!

    override func setUpWithError() throws {
        appName = "LocalIdentityTransferTests.app.\(UUID().uuidString)"
        groupName = "LocalIdentityTransferTests.group.\(UUID().uuidString)"
        app = UserDefaults(suiteName: appName)!
        group = UserDefaults(suiteName: groupName)!
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        app.removePersistentDomain(forName: appName)
        group.removePersistentDomain(forName: groupName)
        app.synchronize()
        group.synchronize()
        try FileManager.default.removeItem(at: directory)
    }

    private var payloadURL: URL { directory.appendingPathComponent("Nanashi-identity-transfer.plist") }

    private func record() -> [String: Any] {
        ["formatVersion": 1,
         "destinationBundleIdentifier": appName,
         "destinationAppGroupIdentifier": groupName,
         "preferences": [
            "theme.appearance": "dark", "enabled": true, "counter": 7,
            "bytes": Data([0, 1, 2]), "lastSync": Date(timeIntervalSince1970: 1_700_000_001),
            "nested": ["array": ["one", "two"]],
            HealthKitIdentityMigration.defaultsKey: [
                "destinationBundleIdentifier": appName,
                "previousBundleIdentifiers": ["com.example.previous"],
                "cutoverEpochSeconds": 1_700_000_000.25,
            ],
         ],
         "groupPreferences": ["noop.widget.snapshot": Data([3, 4, 5])]]
    }

    private func data(_ record: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: record, format: .binary, options: 0)
    }

    private func apply(defaults: UserDefaults? = nil) throws -> Bool {
        try LocalIdentityTransfer.apply(payloadURL: payloadURL, expectedBundleIdentifier: appName,
                                         expectedAppGroupIdentifier: groupName, defaults: defaults ?? app,
                                         groupDefaults: group)
    }

    func testAppliesBothDomainsAndPreservesPropertyListTypes() throws {
        app.setPersistentDomain(["stale": "old"], forName: appName)
        group.setPersistentDomain(["staleGroup": true], forName: groupName)
        try data(record()).write(to: payloadURL)
        XCTAssertTrue(try apply())
        XCTAssertEqual(app.string(forKey: "theme.appearance"), "dark")
        XCTAssertTrue(app.bool(forKey: "enabled"))
        XCTAssertEqual(app.integer(forKey: "counter"), 7)
        XCTAssertEqual(app.data(forKey: "bytes"), Data([0, 1, 2]))
        XCTAssertEqual(app.object(forKey: "lastSync") as? Date, Date(timeIntervalSince1970: 1_700_000_001))
        XCTAssertNil(app.object(forKey: "stale"))
        XCTAssertEqual(group.data(forKey: "noop.widget.snapshot"), Data([3, 4, 5]))
        XCTAssertNil(group.object(forKey: "staleGroup"))
        let migration = try HealthKitIdentityMigration.load(defaults: app, currentBundleIdentifier: appName)
        XCTAssertEqual(migration.previousBundleIdentifiers, ["com.example.previous"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Nanashi-identity-transfer.applied.plist").path))
        let rollback = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: directory.appendingPathComponent("Nanashi-identity-transfer.rollback.plist")), format: nil
        ) as! [String: Any]
        XCTAssertEqual((rollback["preferences"] as? [String: String])?["stale"], "old")
        XCTAssertEqual((rollback["groupPreferences"] as? [String: Bool])?["staleGroup"], true)
    }

    func testConsumedTransferNeverReplaysOverNewSettings() throws {
        try data(record()).write(to: payloadURL)
        XCTAssertTrue(try apply())
        app.set("light", forKey: "theme.appearance")
        group.set(Data([9]), forKey: "noop.widget.snapshot")
        XCTAssertFalse(try apply())
        XCTAssertEqual(app.string(forKey: "theme.appearance"), "light")
        XCTAssertEqual(group.data(forKey: "noop.widget.snapshot"), Data([9]))
    }

    func testConsumedReceiptCannotHideLostHealthHandover() throws {
        try data(record()).write(to: payloadURL)
        XCTAssertTrue(try apply())
        app.removeObject(forKey: HealthKitIdentityMigration.defaultsKey)
        XCTAssertThrowsError(try apply())
        XCTAssertNil(app.object(forKey: HealthKitIdentityMigration.defaultsKey))
    }

    func testWrongDestinationFailsBeforeMutatingEitherDomain() throws {
        app.set("keep", forKey: "sentinel")
        group.set(42, forKey: "sentinel")
        var input = record()
        input["destinationBundleIdentifier"] = "com.example.someone-else"
        let originalData = try data(input)
        try originalData.write(to: payloadURL)
        XCTAssertThrowsError(try apply())
        XCTAssertEqual(app.string(forKey: "sentinel"), "keep")
        XCTAssertEqual(group.integer(forKey: "sentinel"), 42)
        XCTAssertEqual(try Data(contentsOf: payloadURL), originalData)
    }

    func testWrongAppGroupCannotWriteAnotherSuite() throws {
        var input = record()
        input["destinationAppGroupIdentifier"] = "group.unrelated"
        try data(input).write(to: payloadURL)
        XCTAssertThrowsError(try apply())
        XCTAssertTrue((app.persistentDomain(forName: appName) ?? [:]).isEmpty)
        XCTAssertTrue((group.persistentDomain(forName: groupName) ?? [:]).isEmpty)
    }

    func testMissingOrInvalidHealthHandoverCannotStartUnprotectedImport() throws {
        for marker in [nil, ["destinationBundleIdentifier": "wrong"],
                       ["destinationBundleIdentifier": appName, "previousBundleIdentifiers": ["old"],
                        "cutoverEpochSeconds": true]] as [[String: Any]?] {
            var input = record()
            var prefs = input["preferences"] as! [String: Any]
            prefs[HealthKitIdentityMigration.defaultsKey] = marker
            input["preferences"] = prefs
            try data(input).write(to: payloadURL)
            XCTAssertThrowsError(try apply())
            XCTAssertTrue((app.persistentDomain(forName: appName) ?? [:]).isEmpty)
            XCTAssertTrue(FileManager.default.fileExists(atPath: payloadURL.path))
        }
    }

    func testUnsafeNonfinitePreferenceAndBooleanVersionAreRejected() throws {
        var input = record()
        var prefs = input["preferences"] as! [String: Any]
        prefs["invalid"] = Double.nan
        input["preferences"] = prefs
        XCTAssertThrowsError(try LocalIdentityTransfer.validate(data(input), expectedBundleIdentifier: appName,
                                                               expectedAppGroupIdentifier: groupName))
        input = record()
        input["formatVersion"] = true
        XCTAssertThrowsError(try LocalIdentityTransfer.validate(data(input), expectedBundleIdentifier: appName,
                                                               expectedAppGroupIdentifier: groupName))
    }

    func testMissingPayloadFailsClosed() {
        XCTAssertThrowsError(try apply())
    }

    func testSynchronizationFailureRollsBackBothDomainsAndKeepsPayload() throws {
        let failing = FailingFirstSynchronizationDefaults(suiteName: appName)!
        failing.setPersistentDomain(["existing": "app"], forName: appName)
        group.setPersistentDomain(["existing": "group"], forName: groupName)
        let originalData = try data(record())
        try originalData.write(to: payloadURL)
        XCTAssertThrowsError(try apply(defaults: failing))
        XCTAssertEqual(failing.persistentDomain(forName: appName)?["existing"] as? String, "app")
        XCTAssertEqual(group.persistentDomain(forName: groupName)?["existing"] as? String, "group")
        XCTAssertEqual(try Data(contentsOf: payloadURL), originalData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Nanashi-identity-transfer.applied.plist").path))
    }
}

private final class FailingFirstSynchronizationDefaults: UserDefaults, @unchecked Sendable {
    private var firstSynchronization = true

    override func synchronize() -> Bool {
        if firstSynchronization {
            firstSynchronization = false
            return false
        }
        return super.synchronize()
    }
}
