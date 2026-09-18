import XCTest
@testable import WoWSiliconSwift

final class WineBottleServiceTests: XCTestCase {
    func testDefaultAndCustomBottleLocations() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        XCTAssertEqual(
            WineBottleService.defaultBottleURL(homeDirectory: home).path,
            "/Users/tester/WoWSilicon"
        )
        XCTAssertEqual(
            WineBottleService.currentBottleURL(
                prefs: UserPrefs(wineBottlePath: "/Volumes/Games/MyBottle"),
                homeDirectory: home
            ).path,
            "/Volumes/Games/MyBottle"
        )
    }

    func testLegacyMigrationIsOfferedOnlyBeforeDecisionAndDestinationCreation() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try createBottle(at: WineBottleService.legacyBottleURL(homeDirectory: home))

        XCTAssertTrue(WineBottleService.shouldOfferLegacyMigration(
            prefs: UserPrefs(),
            homeDirectory: home
        ))
        XCTAssertFalse(WineBottleService.shouldOfferLegacyMigration(
            prefs: UserPrefs(wineBottleMigrationAsked: true),
            homeDirectory: home
        ))

        try createBottle(at: WineBottleService.defaultBottleURL(homeDirectory: home))
        XCTAssertFalse(WineBottleService.shouldOfferLegacyMigration(
            prefs: UserPrefs(),
            homeDirectory: home
        ))
    }

    func testMigrationCanReplaceAnEmptyDefaultDirectory() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try createBottle(at: WineBottleService.legacyBottleURL(homeDirectory: home))
        let destination = WineBottleService.defaultBottleURL(homeDirectory: home)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        XCTAssertTrue(WineBottleService.shouldOfferLegacyMigration(
            prefs: UserPrefs(),
            homeDirectory: home
        ))
        XCTAssertTrue(WineBottleService.isWineBottle(
            at: try WineBottleService.copyLegacyBottle(homeDirectory: home)
        ))
    }

    func testMigrationCopiesBottleAndKeepsLegacyBottle() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let legacy = WineBottleService.legacyBottleURL(homeDirectory: home)
        try createBottle(at: legacy)
        try Data("content".utf8).write(to: legacy.appendingPathComponent("drive_c/example.txt"))

        let destination = try WineBottleService.copyLegacyBottle(homeDirectory: home)

        XCTAssertTrue(WineBottleService.isWineBottle(at: legacy))
        XCTAssertTrue(WineBottleService.isWineBottle(at: destination))
        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("drive_c/example.txt"), encoding: .utf8),
            "content"
        )
    }

    func testSelectionRejectsHomeAndUnrelatedNonemptyDirectory() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertThrowsError(try WineBottleService.validateSelectedBottleURL(
            home,
            homeDirectory: home
        ))

        let unrelated = home.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try Data().write(to: unrelated.appendingPathComponent("important.txt"))
        XCTAssertThrowsError(try WineBottleService.validateSelectedBottleURL(
            unrelated,
            homeDirectory: home
        ))
    }

    func testExternalUserProfileMigrationCopiesDataIntoBottleAndKeepsSource() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bottle = WineBottleService.defaultBottleURL(homeDirectory: home)
        let users = bottle.appendingPathComponent("drive_c/users", isDirectory: true)
        let externalProfile = home.appendingPathComponent("Wine", isDirectory: true)
        let bottleProfile = users.appendingPathComponent("tester", isDirectory: true)

        try FileManager.default.createDirectory(at: users, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: externalProfile.appendingPathComponent("AppData", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("settings".utf8).write(
            to: externalProfile.appendingPathComponent("AppData/settings.txt")
        )
        try FileManager.default.createSymbolicLink(
            at: bottleProfile,
            withDestinationURL: externalProfile
        )

        XCTAssertTrue(try WineBottleService.migrateExternalUserProfileIfNeeded(
            bottleURL: bottle,
            homeDirectory: home
        ))
        XCTAssertFalse(try bottleProfile.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? true)
        XCTAssertEqual(
            try String(contentsOf: bottleProfile.appendingPathComponent("AppData/settings.txt"), encoding: .utf8),
            "settings"
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: externalProfile.appendingPathComponent("AppData/settings.txt").path
        ))
        XCTAssertFalse(try WineBottleService.migrateExternalUserProfileIfNeeded(
            bottleURL: bottle,
            homeDirectory: home
        ))
    }

    func testExternalUserProfileMigrationIgnoresOtherSymlinks() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bottle = WineBottleService.defaultBottleURL(homeDirectory: home)
        let users = bottle.appendingPathComponent("drive_c/users", isDirectory: true)
        let otherProfile = home.appendingPathComponent("OtherProfile", isDirectory: true)
        let bottleProfile = users.appendingPathComponent("tester", isDirectory: true)

        try FileManager.default.createDirectory(at: users, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherProfile, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: bottleProfile, withDestinationURL: otherProfile)

        XCTAssertFalse(try WineBottleService.migrateExternalUserProfileIfNeeded(
            bottleURL: bottle,
            homeDirectory: home
        ))
        XCTAssertTrue(try bottleProfile.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink ?? false)
    }

    private func temporaryHome() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconBottleTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func createBottle(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("drive_c", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("registry".utf8).write(to: url.appendingPathComponent("system.reg"))
    }
}
