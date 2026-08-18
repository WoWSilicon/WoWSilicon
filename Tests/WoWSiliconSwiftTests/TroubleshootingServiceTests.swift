import XCTest
@testable import WoWSiliconSwift

final class TroubleshootingServiceTests: XCTestCase {
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
