import XCTest
@testable import Strand

final class HealthKitIdentityMigrationTests: XCTestCase {
    private let original = "com.example.nanashi"
    private let destination = "com.example.nanashi.TEAM"
    private let cutover = 1_700_000_000.25

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "HealthKitIdentityMigrationTests.\(UUID().uuidString)")!
    }

    private func record(timestamp: Double? = nil) -> [String: Any] {
        ["destinationBundleIdentifier": destination,
         "previousBundleIdentifiers": [original],
         "cutoverEpochSeconds": timestamp ?? cutover]
    }

    func testAbsentRecordPreservesExistingExportBehavior() throws {
        let policy = try HealthKitIdentityMigration.load(defaults: defaults(), currentBundleIdentifier: original)
        XCTAssertEqual(policy, .none)
        XCTAssertEqual(policy.writeStart(from: 12), 12)
        XCTAssertTrue(policy.allowsSession(keyStart: 1, spanStart: 2))
        XCTAssertTrue(policy.allowsDailyWrite(dayStart: Date(timeIntervalSince1970: 1)))
    }

    func testOnlyExactPreviousSourceIdentitiesAreExcluded() throws {
        let defaults = defaults()
        defaults.set(record(), forKey: HealthKitIdentityMigration.defaultsKey)
        let migrated = try HealthKitIdentityMigration.load(defaults: defaults, currentBundleIdentifier: destination)
        XCTAssertTrue(migrated.excludesSource(bundleIdentifier: original))
        XCTAssertFalse(migrated.excludesSource(bundleIdentifier: original + ".other"))
        XCTAssertFalse(migrated.excludesSource(bundleIdentifier: destination))
        XCTAssertFalse(migrated.excludesSource(bundleIdentifier: "Nanashi"))
    }

    func testWrongDestinationStopsMigrationInsteadOfExportingHistory() {
        let defaults = defaults()
        defaults.set(record(), forKey: HealthKitIdentityMigration.defaultsKey)
        XCTAssertThrowsError(try HealthKitIdentityMigration.load(defaults: defaults, currentBundleIdentifier: original))
        XCTAssertThrowsError(try HealthKitIdentityMigration.load(defaults: defaults, currentBundleIdentifier: nil))
    }

    func testMalformedRecordsCannotFallBackToUnrestrictedExport() {
        let defaults = defaults()
        let malformed: [Any] = ["wrong", [:] as [String: Any],
                               ["destinationBundleIdentifier": destination],
                               ["destinationBundleIdentifier": destination,
                                "previousBundleIdentifiers": [destination], "cutoverEpochSeconds": cutover],
                               ["destinationBundleIdentifier": destination,
                                "previousBundleIdentifiers": [], "cutoverEpochSeconds": cutover]]
        for value in malformed {
            defaults.set(value, forKey: HealthKitIdentityMigration.defaultsKey)
            XCTAssertThrowsError(try HealthKitIdentityMigration.load(defaults: defaults, currentBundleIdentifier: destination))
        }
    }

    func testInvalidCutoversCannotCrashIntegerWindowConversion() {
        let defaults = defaults()
        for timestamp in [0, -1, Double.infinity, Double.nan, Double.greatestFiniteMagnitude] {
            defaults.set(record(timestamp: timestamp), forKey: HealthKitIdentityMigration.defaultsKey)
            XCTAssertThrowsError(try HealthKitIdentityMigration.load(defaults: defaults, currentBundleIdentifier: destination))
        }
    }

    func testSubsecondHandoverRoundsUpWithoutReopeningEarlierWindow() throws {
        let defaults = defaults()
        defaults.set(record(), forKey: HealthKitIdentityMigration.defaultsKey)
        let policy = try HealthKitIdentityMigration.load(defaults: defaults, currentBundleIdentifier: destination)
        XCTAssertEqual(policy.writeStart(from: 1_699_000_000), 1_700_000_001)
        XCTAssertEqual(policy.writeStart(from: 1_700_000_060), 1_700_000_060)
    }

    func testEditedAndCrossingSessionsCannotRecreatePriorHistory() throws {
        let defaults = defaults()
        defaults.set(record(), forKey: HealthKitIdentityMigration.defaultsKey)
        let policy = try HealthKitIdentityMigration.load(defaults: defaults, currentBundleIdentifier: destination)
        XCTAssertFalse(policy.allowsSession(keyStart: 1_699_999_000, spanStart: 1_700_000_100))
        XCTAssertFalse(policy.allowsSession(keyStart: 1_700_000_100, spanStart: 1_699_999_000))
        XCTAssertFalse(policy.allowsSession(keyStart: 1_700_000_000, spanStart: 1_700_000_000))
        XCTAssertTrue(policy.allowsSession(keyStart: 1_700_000_001, spanStart: 1_700_000_100))
    }

    func testCutoverDayVitalsStayWithOldSourceEvenWhenWakeTimeChanges() throws {
        let defaults = defaults()
        defaults.set(record(), forKey: HealthKitIdentityMigration.defaultsKey)
        let policy = try HealthKitIdentityMigration.load(defaults: defaults, currentBundleIdentifier: destination)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: cutover))
        XCTAssertFalse(policy.allowsDailyWrite(dayStart: day))
        XCTAssertFalse(policy.allowsDailyWrite(dayStart: day.addingTimeInterval(-86_400)))
        XCTAssertTrue(policy.allowsDailyWrite(dayStart: day.addingTimeInterval(86_400)))
    }

    func testMidnightCutoverStillSkipsThatDay() throws {
        let defaults = defaults()
        defaults.set(record(timestamp: 1_699_920_000), forKey: HealthKitIdentityMigration.defaultsKey)
        let policy = try HealthKitIdentityMigration.load(defaults: defaults, currentBundleIdentifier: destination)
        XCTAssertFalse(policy.allowsDailyWrite(dayStart: Date(timeIntervalSince1970: 1_699_920_000)))
        XCTAssertTrue(policy.allowsDailyWrite(dayStart: Date(timeIntervalSince1970: 1_700_006_400)))
    }
}
