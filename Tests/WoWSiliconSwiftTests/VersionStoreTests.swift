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
                "auto_delete_wdb": false,
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
        XCTAssertFalse(wrath.settings.autoDeleteWdb)
        XCTAssertTrue(wrath.settings.enableMetalHud)
        XCTAssertTrue(wrath.settings.showTerminalNormally)
    }

    func testProfileSelectionPreservesDistinctSettingsAcrossSaveAndLoad() throws {
        let supportURL = try makeTemporaryDirectory()
        let store = VersionStore(supportDirectory: supportURL)
        let firstSettings = VersionSettings(
            enableVanillaTweaks: true,
            autoDeleteWdb: true,
            enableMetalHud: true,
            showTerminalNormally: true,
            environmentVariables: "PROFILE=FIRST",
            vanillaTweaksParameters: "--first",
            graphicsSettings: GraphicsSettings(backend: .mtld3d, resolution: "1920x1080"),
            x87Backend: .x87Sidecar
        )
        let secondSettings = VersionSettings(
            enableVanillaTweaks: false,
            autoDeleteWdb: false,
            enableMetalHud: false,
            showTerminalNormally: false,
            environmentVariables: "PROFILE=SECOND",
            vanillaTweaksParameters: "--second",
            graphicsSettings: GraphicsSettings(backend: .d9vk, resolution: "2560x1440"),
            x87Backend: .disabled
        )
        var manager = VersionManager(
            currentVersionID: "first",
            versions: [
                "first": GameVersion(
                    id: "first",
                    displayName: "First",
                    wowVersion: "1.12.1",
                    executableName: "WoW.exe",
                    supportsVanillaTweaks: true,
                    supportsDLLLoading: true,
                    usesRosettaPatching: true,
                    settings: firstSettings
                ),
                "second": GameVersion(
                    id: "second",
                    displayName: "Second",
                    wowVersion: "1.12.1",
                    executableName: "WoW.exe",
                    supportsVanillaTweaks: true,
                    supportsDLLLoading: true,
                    usesRosettaPatching: true,
                    settings: secondSettings
                )
            ]
        )

        manager.setCurrentVersion(id: "second")
        manager.setCurrentVersion(id: "first")
        manager.setCurrentVersion(id: "second")

        XCTAssertEqual(manager.versions["first"]?.settings, firstSettings)
        XCTAssertEqual(manager.versions["second"]?.settings, secondSettings)

        try store.save(manager: manager)
        let reloaded = store.loadVersionManager()

        XCTAssertFalse(reloaded.requiresLegacyPrefsMigration)
        XCTAssertEqual(reloaded.manager.currentVersionID, "second")
        XCTAssertEqual(reloaded.manager.versions["first"]?.settings, firstSettings)
        XCTAssertEqual(reloaded.manager.versions["second"]?.settings, secondSettings)
    }

    func testMissingVersionStoreRequestsLegacyPreferencesMigrationOnlyOnce() throws {
        let supportURL = try makeTemporaryDirectory()
        let store = VersionStore(supportDirectory: supportURL)

        let initial = store.loadVersionManager()
        XCTAssertTrue(initial.requiresLegacyPrefsMigration)

        try store.save(manager: initial.manager)
        let reloaded = store.loadVersionManager()
        XCTAssertFalse(reloaded.requiresLegacyPrefsMigration)
    }

    func testSavingUnchangedManagerDoesNotRewriteFile() throws {
        let supportURL = try makeTemporaryDirectory()
        let store = VersionStore(supportDirectory: supportURL)
        let manager = VersionManager.makeDefault()
        let versionsURL = supportURL.appendingPathComponent("WoWSilicon/versions.json")

        try store.save(manager: manager)
        let originalModificationDate = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: originalModificationDate],
            ofItemAtPath: versionsURL.path
        )

        try store.save(manager: manager)

        let attributes = try FileManager.default.attributesOfItem(atPath: versionsURL.path)
        XCTAssertEqual(attributes[.modificationDate] as? Date, originalModificationDate)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconSwiftTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempURLs.append(url)
        return url
    }
}
