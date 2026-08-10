import XCTest
@testable import WoWSiliconSwift

final class ModelCompatibilityTests: XCTestCase {
    func testUserPrefsDecodesFilesContainingRemovedKeys() throws {
        let json = """
        {
          "suppressed_update_version": "2.4.0",
          "show_terminal_normally": true,
          "enable_metal_hud": true,
          "enable_vanilla_tweaks": false,
          "auto_delete_wdb": false,
          "environment_variables": "A=B",
          "vanilla_tweaks_parameters": "--flag",
          "has_seen_wrath_warning": true
        }
        """

        let prefs = try JSONDecoder().decode(UserPrefs.self, from: Data(json.utf8))

        XCTAssertTrue(prefs.showTerminalNormally)
        XCTAssertTrue(prefs.enableMetalHud)
        XCTAssertFalse(prefs.enableVanillaTweaks)
        XCTAssertFalse(prefs.autoDeleteWdb)
        XCTAssertEqual(prefs.environmentVariables, "A=B")
        XCTAssertEqual(prefs.vanillaTweaksParameters, "--flag")
        XCTAssertTrue(prefs.enableRosettaX87)
    }

    func testVersionSettingsDecodesFilesContainingRemovedSaveSudoPasswordKey() throws {
        let json = """
        {
          "enableMetalHud": true,
          "saveSudoPassword": true,
          "showTerminalNormally": true,
          "cursorSizeMultiplier": 4,
          "enableLibSiliconPatch": true
        }
        """

        let settings = try JSONDecoder().decode(VersionSettings.self, from: Data(json.utf8))

        XCTAssertTrue(settings.enableMetalHud)
        XCTAssertTrue(settings.showTerminalNormally)
        XCTAssertEqual(settings.cursorSizeMultiplier, 4)
        XCTAssertTrue(settings.enableLibSiliconPatch)
        XCTAssertTrue(settings.enableRosettaX87)
    }

    func testGameVersionExecutableAndDirectoryPathResolution() {
        var version = GameVersion(
            id: "test",
            displayName: "Test",
            wowVersion: "1.12.1",
            gamePath: "/Games/WorldOfWarcraft/WoW.exe",
            executableName: "WoW.exe",
            supportsVanillaTweaks: true,
            supportsDLLLoading: true,
            usesRosettaPatching: true,
            usesDivxDecoderPatch: false
        )

        XCTAssertEqual(version.gameDirectoryPath, "/Games/WorldOfWarcraft")
        XCTAssertEqual(version.gameExecutablePath, "/Games/WorldOfWarcraft/WoW.exe")
        XCTAssertEqual(version.effectiveExecutableName, "WoW.exe")

        version.gamePath = "/Games/CustomWoW/Ascension.exe"
        XCTAssertEqual(version.gameDirectoryPath, "/Games/CustomWoW")
        XCTAssertEqual(version.gameExecutablePath, "/Games/CustomWoW/Ascension.exe")
        XCTAssertEqual(version.effectiveExecutableName, "Ascension.exe")

        version.gamePath = "/Games/LegacyFolder"
        XCTAssertEqual(version.gameDirectoryPath, "/Games/LegacyFolder")
        XCTAssertEqual(version.effectiveExecutableName, "WoW.exe")
    }
}
