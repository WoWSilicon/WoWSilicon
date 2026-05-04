import XCTest
@testable import WoWSiliconSwift

final class ModServiceTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
        try super.tearDownWithError()
    }

    func testInstallModCopiesDLLAndEnablesIt() throws {
        let gameURL = try makeTemporaryDirectory()
        let sourceURL = try makeTemporaryDirectory().appendingPathComponent("example.dll")
        try Data([0xde, 0xad, 0xbe, 0xef]).write(to: sourceURL)
        let version = makeVersion(gameURL: gameURL)

        let mod = try ModService.installMod(from: sourceURL, version: version, supportsDLL: true)

        let installedURL = gameURL.appendingPathComponent("mods", isDirectory: true).appendingPathComponent("example.dll")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedURL.path))
        XCTAssertEqual(try Data(contentsOf: installedURL), Data([0xde, 0xad, 0xbe, 0xef]))
        XCTAssertEqual(mod.name, "example.dll")
        XCTAssertTrue(mod.enabled)

        let dlls = try String(contentsOf: gameURL.appendingPathComponent("dlls.txt"), encoding: .utf8)
        XCTAssertTrue(dlls.contains("mods/example.dll"))
        XCTAssertTrue(dlls.contains("mods/winerosetta.dll"))
    }

    func testInstallModRejectsNonDLLFile() throws {
        let gameURL = try makeTemporaryDirectory()
        let sourceURL = try makeTemporaryDirectory().appendingPathComponent("readme.txt")
        try "not a dll".write(to: sourceURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try ModService.installMod(from: sourceURL, version: makeVersion(gameURL: gameURL), supportsDLL: true))
    }

    func testInstallModDoesNotReplaceRequiredDLL() throws {
        let gameURL = try makeTemporaryDirectory()
        let sourceURL = try makeTemporaryDirectory().appendingPathComponent("winerosetta.dll")
        try Data([0x01]).write(to: sourceURL)

        XCTAssertThrowsError(try ModService.installMod(from: sourceURL, version: makeVersion(gameURL: gameURL), supportsDLL: true))
    }

    private func makeVersion(gameURL: URL) -> GameVersion {
        GameVersion(
            id: "test",
            displayName: "Test",
            wowVersion: "3.3.5a",
            gamePath: gameURL.path,
            executableName: "Wow.exe",
            supportsVanillaTweaks: false,
            supportsDLLLoading: true,
            usesRosettaPatching: true,
            usesDivxDecoderPatch: false
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconSwiftTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempURLs.append(url)
        return url
    }
}
