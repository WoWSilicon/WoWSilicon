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
        XCTAssertEqual(prefs.x87Backend, .rosettaX87)
        XCTAssertEqual(prefs.wineBottlePath, "")
        XCTAssertFalse(prefs.wineBottleMigrationAsked)
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
        XCTAssertEqual(settings.x87Backend, .rosettaX87)
        XCTAssertEqual(settings.audioOutputDeviceID, "")
        XCTAssertEqual(settings.audioInputDeviceID, "")
        XCTAssertFalse(settings.spatializeStereo)
        XCTAssertFalse(settings.nightMode)
    }

    func testLegacyDisabledRosettaMigratesToDisabledBackend() throws {
        let prefs = try JSONDecoder().decode(
            UserPrefs.self,
            from: Data(#"{"enable_rosetta_x87":false}"#.utf8)
        )
        let settings = try JSONDecoder().decode(
            VersionSettings.self,
            from: Data(#"{"enableRosettaX87":false}"#.utf8)
        )

        XCTAssertEqual(prefs.x87Backend, .disabled)
        XCTAssertEqual(settings.x87Backend, .disabled)
    }

    func testX87SidecarBackendRoundTrips() throws {
        let prefs = UserPrefs(x87Backend: .x87Sidecar)
        let settings = VersionSettings(x87Backend: .x87Sidecar)

        XCTAssertEqual(
            try JSONDecoder().decode(UserPrefs.self, from: JSONEncoder().encode(prefs)).x87Backend,
            .x87Sidecar
        )
        XCTAssertEqual(
            try JSONDecoder().decode(VersionSettings.self, from: JSONEncoder().encode(settings)).x87Backend,
            .x87Sidecar
        )
    }

    func testAudioOutputDeviceRoundTrips() throws {
        let settings = VersionSettings(
            audioOutputDeviceID: "{wine-endpoint-id}",
            audioInputDeviceID: "{wine-input-id}",
            spatializeStereo: true,
            nightMode: true
        )

        let decoded = try JSONDecoder().decode(
            VersionSettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertEqual(decoded.audioOutputDeviceID, "{wine-endpoint-id}")
        XCTAssertEqual(decoded.audioInputDeviceID, "{wine-input-id}")
        XCTAssertTrue(decoded.spatializeStereo)
        XCTAssertTrue(decoded.nightMode)
    }

    func testInterimSpatialAudioModeMigratesToEnabledToggle() throws {
        let settings = try JSONDecoder().decode(
            VersionSettings.self,
            from: Data(#"{"spatialAudioMode":"fixed"}"#.utf8)
        )

        XCTAssertTrue(settings.spatializeStereo)
    }

    func testWineBottlePreferencesRoundTrip() throws {
        let prefs = UserPrefs(
            wineBottlePath: "/Users/tester/Wine/Custom",
            wineBottleMigrationAsked: true
        )
        let decoded = try JSONDecoder().decode(UserPrefs.self, from: JSONEncoder().encode(prefs))

        XCTAssertEqual(decoded.wineBottlePath, "/Users/tester/Wine/Custom")
        XCTAssertTrue(decoded.wineBottleMigrationAsked)
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
