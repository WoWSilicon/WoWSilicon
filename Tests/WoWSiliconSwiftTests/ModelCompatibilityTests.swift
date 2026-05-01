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
    }
}
