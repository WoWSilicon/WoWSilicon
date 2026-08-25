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
