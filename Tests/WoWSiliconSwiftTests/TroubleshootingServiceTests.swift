import XCTest
@testable import WoWSiliconSwift

final class TroubleshootingServiceTests: XCTestCase {
    func testPermissionChecksVerifyGameDirectoryWithoutLeavingProbeFile() throws {
        let gameDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconPermissionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: gameDirectory) }
        try FileManager.default.createDirectory(at: gameDirectory, withIntermediateDirectories: true)

        let wowURL = gameDirectory.appendingPathComponent("WoW.exe")
        let divxURL = gameDirectory.appendingPathComponent("DivxDecoder.dll")
        try Data("wow".utf8).write(to: wowURL)
        try Data("divx".utf8).write(to: divxURL)

        var version = try XCTUnwrap(VersionManager.defaultVersions["vanillasilicon"])
        version.gamePath = wowURL.path
        let checks = TroubleshootingService.checkPermissions(context: TroubleshootingContext(
            gamePath: wowURL.path,
            currentVersion: version,
            isGamePatched: false
        ))

        XCTAssertEqual(checks.first(where: { $0.id == "game-folder-read" })?.state, .passed)
        XCTAssertEqual(checks.first(where: { $0.id == "game-folder-write" })?.state, .passed)
        XCTAssertEqual(checks.first(where: { $0.id == "game-executable" })?.state, .passed)
        XCTAssertEqual(checks.first(where: { $0.id == "divx-decoder" })?.state, .passed)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: gameDirectory.path)
            .contains(where: { $0.hasPrefix(".wowsilicon-access-check-") }))
    }

    func testPermissionChecksReportUnconfiguredGamePath() {
        let checks = TroubleshootingService.checkPermissions(context: TroubleshootingContext(
            gamePath: nil,
            currentVersion: nil,
            isGamePatched: false
        ))

        XCTAssertEqual(checks.first?.id, "game-folder")
        XCTAssertEqual(checks.first?.state, .unavailable)
        XCTAssertEqual(checks.first?.status, "Not configured")
    }

    func testDebugLogReportsSelectedX87Translation() throws {
        var version = try XCTUnwrap(VersionManager.defaultVersions["wrathsilicon"])
        version.settings.x87Backend = .x87Sidecar

        let result = TroubleshootingService.generateDebugLog(
            context: TroubleshootingContext(
                gamePath: nil,
                currentVersion: version,
                isGamePatched: false
            ),
            hideMacUserName: true,
            includeLatestErrorLog: false
        )

        XCTAssertTrue(result.full.contains("x87 Translation: x87sidecar (x87sidecar)"))
    }

    func testDeleteDefaultWineBottleOnlyDeletesWineDirectory() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconTroubleshootingTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let wineBottle = home.appendingPathComponent(".wine", isDirectory: true)
        let unrelated = home.appendingPathComponent("keep-me", isDirectory: true)
        try FileManager.default.createDirectory(at: wineBottle, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)

        let deletedPath = try TroubleshootingService.deleteDefaultWineBottle(homeDirectory: home)

        XCTAssertEqual(deletedPath, wineBottle.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: wineBottle.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testDeleteDefaultWineBottleReportsWhenItDoesNotExist() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconTroubleshootingTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        XCTAssertThrowsError(try TroubleshootingService.deleteDefaultWineBottle(homeDirectory: home)) { error in
            guard case TroubleshootingServiceError.nothingToDelete = error else {
                return XCTFail("Expected nothingToDelete, got \(error)")
            }
        }
    }
}
