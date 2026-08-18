import XCTest
@testable import WoWSiliconSwift

final class GenericD3D9ProfileTests: XCTestCase {
    func testTemplateDisablesWoWOnlyCapabilities() {
        let template = VersionManager.genericD3D9Template

        XCTAssertEqual(template.profileKind, .genericD3D9)
        XCTAssertFalse(template.supportsAddons)
        XCTAssertFalse(template.supportsRealmlist)
        XCTAssertFalse(template.supportsCustomGraphicsSettings)
        XCTAssertFalse(template.supportsVanillaTweaks)
        XCTAssertFalse(template.supportsDLLLoading)
        XCTAssertFalse(template.usesRosettaPatching)
        XCTAssertFalse(template.settings.autoDeleteWdb)
        XCTAssertNotNil(VersionManager.profileTemplates[VersionManager.genericD3D9TemplateID])
        XCTAssertNil(VersionManager.defaultVersions[VersionManager.genericD3D9TemplateID])
    }

    func testGenericProfileKindRoundTrips() throws {
        let encoded = try JSONEncoder().encode(VersionManager.genericD3D9Template)
        let decoded = try JSONDecoder().decode(GameVersion.self, from: encoded)

        XCTAssertEqual(decoded.profileKind, .genericD3D9)
        XCTAssertEqual(decoded.wowVersion, "")
    }

    func testLegacyGameVersionDefaultsToWorldOfWarcraft() throws {
        let data = Data(#"{"id":"legacy","display_name":"Legacy","wow_version":"1.12.1"}"#.utf8)
        let version = try JSONDecoder().decode(GameVersion.self, from: data)

        XCTAssertEqual(version.profileKind, .worldOfWarcraft)
        XCTAssertTrue(version.supportsAddons)
        XCTAssertTrue(version.supportsRealmlist)
        XCTAssertTrue(version.supportsCustomGraphicsSettings)
    }

    func testGenericPatchOnlyManagesD3D9DLL() throws {
        let gameDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconGenericD3D9Tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: gameDirectory) }
        try FileManager.default.createDirectory(at: gameDirectory, withIntermediateDirectories: true)

        let executable = gameDirectory.appendingPathComponent("LegacyGame.exe")
        let unrelatedLoader = gameDirectory.appendingPathComponent("libDllLdr.dll")
        let unrelatedConfig = gameDirectory.appendingPathComponent("mtld3d.conf")
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data("game".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: unrelatedLoader.path, contents: Data("keep".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: unrelatedConfig.path, contents: Data("keep".utf8)))

        var version = VersionManager.genericD3D9Template
        version.id = "generic-test"
        version.gamePath = executable.path
        version.executableName = executable.lastPathComponent

        let beforePatch = PatchingStatusChecker.evaluateGamePatch(for: version)
        XCTAssertFalse(beforePatch.applied)
        XCTAssertTrue(beforePatch.actionable)

        try PatchService.applyGamePatch(for: version)

        let d3d9 = gameDirectory.appendingPathComponent("d3d9.dll")
        XCTAssertTrue(FileManager.default.fileExists(atPath: d3d9.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: gameDirectory.appendingPathComponent("mods").path))
        XCTAssertEqual(try Data(contentsOf: unrelatedLoader), Data("keep".utf8))
        XCTAssertEqual(try Data(contentsOf: unrelatedConfig), Data("keep".utf8))
        XCTAssertTrue(PatchingStatusChecker.evaluateGamePatch(for: version).applied)

        try PatchService.removeGamePatch(for: version)

        XCTAssertFalse(FileManager.default.fileExists(atPath: d3d9.path))
        XCTAssertEqual(try Data(contentsOf: unrelatedLoader), Data("keep".utf8))
        XCTAssertEqual(try Data(contentsOf: unrelatedConfig), Data("keep".utf8))
    }

    func testTelemetryOmitsWoWOnlyDimensions() {
        var version = VersionManager.genericD3D9Template
        version.gamePath = "/Games/LegacyGame.exe"

        let context = TelemetryEventContext(version: version)

        XCTAssertNil(context.wowVersion)
        XCTAssertNil(context.realmlist)
    }
}
