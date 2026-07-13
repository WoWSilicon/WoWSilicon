import XCTest
@testable import WoWSiliconSwift

final class VersionStoreTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
        try super.tearDownWithError()
    }

    func testSaveAndLoadRoundTripsCustomProfileAndDefaults() throws {
        let supportURL = try makeTemporaryDirectory()
        let store = VersionStore(supportDirectory: supportURL)
        let custom = GameVersion(
            id: "custom",
            displayName: "Custom",
            wowVersion: "1.12.1",
            gamePath: "/Games/WoW",
            executableName: "WoW.exe",
            supportsVanillaTweaks: true,
            supportsDLLLoading: true,
            usesRosettaPatching: true,
            usesDivxDecoderPatch: false,
            settings: VersionSettings(enableMetalHud: true)
        )
        var manager = VersionManager.makeDefault()
        manager.currentVersionID = "custom"
        manager.versions["custom"] = custom

        try store.save(manager: manager)
        let result = store.loadVersionManager()

        XCTAssertFalse(result.decodeFailed)
        XCTAssertEqual(result.manager.currentVersionID, "custom")
        XCTAssertEqual(result.manager.versions["custom"]?.gamePath, "/Games/WoW")
        XCTAssertEqual(result.manager.versions["custom"]?.settings.enableMetalHud, true)
        XCTAssertNotNil(result.manager.versions["vanillasilicon"])
        XCTAssertNotNil(result.manager.versions["burningsilicon"])
        XCTAssertNotNil(result.manager.versions["wrathsilicon"])
    }

    func testLoadFallsBackToDefaultsWhenVersionsFileIsInvalid() throws {
        let supportURL = try makeTemporaryDirectory()
        let versionsURL = supportURL.appendingPathComponent("WoWSilicon/versions.json")
        try FileManager.default.createDirectory(at: versionsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ not json".write(to: versionsURL, atomically: true, encoding: .utf8)

        let result = VersionStore(supportDirectory: supportURL).loadVersionManager()

        XCTAssertTrue(result.decodeFailed)
        XCTAssertEqual(result.manager.currentVersionID, VersionManager.defaultCurrentVersionID)
        XCTAssertEqual(Set(result.manager.versions.keys), Set(VersionManager.defaultVersions.keys))
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testLoadMergesLegacyVersionManagerWhenNewStoreHasNoPaths() throws {
        let supportURL = try makeTemporaryDirectory()
        let legacyURL = supportURL.appendingPathComponent("WoWSilicon/version_manager.json")
        try FileManager.default.createDirectory(at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "current_version_id": "wrathsilicon",
          "versions": {
            "wrathsilicon": {
              "game_path": "/Games/Wrath",
              "settings": {
                "environment_variables": "FOO=BAR",
                "enable_metal_hud": true,
                "show_terminal_normally": true,
                "enable_lib_silicon_patch": true
              }
            }
          }
        }
        """.write(to: legacyURL, atomically: true, encoding: .utf8)

        let result = VersionStore(supportDirectory: supportURL).loadVersionManager()
        let wrath = try XCTUnwrap(result.manager.versions["wrathsilicon"])

        XCTAssertEqual(result.manager.currentVersionID, "wrathsilicon")
        XCTAssertEqual(wrath.gamePath, "/Games/Wrath")
        XCTAssertEqual(wrath.settings.environmentVariables, "FOO=BAR")
        XCTAssertTrue(wrath.settings.enableMetalHud)
        XCTAssertTrue(wrath.settings.showTerminalNormally)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconSwiftTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempURLs.append(url)
        return url
    }
}
