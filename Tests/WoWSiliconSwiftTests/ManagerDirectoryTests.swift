import XCTest
@testable import WoWSiliconSwift

@MainActor
final class ManagerDirectoryTests: XCTestCase {
    func testFolderButtonsAreEnabledWhenGamePathIsAnExecutable() throws {
        let gameDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconManagerDirectoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: gameDirectory) }

        let modsDirectory = gameDirectory.appendingPathComponent("mods", isDirectory: true)
        let addonsDirectory = gameDirectory.appendingPathComponent("Interface/AddOns", isDirectory: true)
        try FileManager.default.createDirectory(at: modsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: addonsDirectory, withIntermediateDirectories: true)

        let executableURL = gameDirectory.appendingPathComponent("WoW.exe")
        try Data().write(to: executableURL)

        var version = VersionManager.defaultVersions["vanillasilicon"]!
        version.gamePath = executableURL.path

        let modManager = ModManagerViewModel(version: version, supportsDLL: true)
        let addonManager = AddonManagerViewModel(gamePath: executableURL.path)

        XCTAssertTrue(modManager.canOpenModsDirectory)
        XCTAssertTrue(addonManager.canOpenAddonsDirectory)
    }
}
