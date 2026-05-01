import XCTest
@testable import WoWSiliconSwift

final class ConfigServiceTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
        try super.tearDownWithError()
    }

    func testApplyGraphicsSettingsWritesVanillaSpecificKeys() throws {
        let gameURL = try makeTemporaryDirectory()
        let settings = GraphicsSettings(
            windowMode: .fullscreen,
            resolution: "1920x1080",
            refreshRate: 120,
            vsync: true,
            multisampling: .x4,
            textureFiltering: .anisotropicX16,
            specular: false,
            projectedTextures: true,
            viewDistance: 377,
            groundEffectDensity: 1,
            weatherDensity: 2,
            particleDensity: 0.5,
            shadowQuality: .low
        )
        let version = makeVersion(wowVersion: "1.12.1", gamePath: gameURL.path, settings: settings)

        try ConfigService.applyGraphicsSettings(for: version)

        let content = try configContent(in: gameURL)
        XCTAssertTrue(content.contains(#"SET gxWindow "1""#))
        XCTAssertTrue(content.contains(#"SET gxMaximize "1""#))
        XCTAssertTrue(content.contains(#"SET gxResolution "1920x1080""#))
        XCTAssertTrue(content.contains(#"SET gxRefresh "120""#))
        XCTAssertTrue(content.contains(#"SET gxVSync "1""#))
        XCTAssertTrue(content.contains(#"SET gxMultisample "4""#))
        XCTAssertTrue(content.contains(#"SET trilinear "1""#))
        XCTAssertTrue(content.contains(#"SET anisotropic "16""#))
        XCTAssertTrue(content.contains(#"SET frillDensity "16""#))
        XCTAssertTrue(content.contains(#"SET shadowlod "1""#))
        XCTAssertFalse(content.contains("projectedTextures"))
    }

    func testApplyGraphicsSettingsWritesTBCAndWrathStyleKeys() throws {
        let gameURL = try makeTemporaryDirectory()
        let settings = GraphicsSettings(
            multisampling: .off,
            textureFiltering: .trilinear,
            projectedTextures: false,
            groundEffectDensity: 3,
            shadowQuality: .high
        )
        let version = makeVersion(wowVersion: "2.4.3", gamePath: gameURL.path, settings: settings)

        try ConfigService.applyGraphicsSettings(for: version)

        let content = try configContent(in: gameURL)
        XCTAssertFalse(content.contains("gxMultisample"))
        XCTAssertTrue(content.contains(#"SET textureFilteringMode "1""#))
        XCTAssertTrue(content.contains(#"SET projectedTextures "0""#))
        XCTAssertTrue(content.contains(#"SET groundEffectDensity "64""#))
        XCTAssertTrue(content.contains(#"SET groundEffectDist "140""#))
        XCTAssertTrue(content.contains(#"SET shadowLevel "2""#))
    }

    func testReadGraphicsSettingsReadsExistingConfig() throws {
        let gameURL = try makeTemporaryDirectory()
        let wtfURL = gameURL.appendingPathComponent("WTF", isDirectory: true)
        try FileManager.default.createDirectory(at: wtfURL, withIntermediateDirectories: true)
        try """
        SET gxMaximize "1"
        SET gxResolution "2560x1440"
        SET gxRefresh "144"
        SET gxVSync "1"
        SET gxMultisample "8"
        SET textureFilteringMode "5"
        SET specular "0"
        SET projectedTextures "1"
        SET farclip "1277"
        SET groundEffectDensity "32"
        SET weatherDensity "1"
        SET particleDensity "0.7"
        SET shadowLevel "1"
        """.write(to: wtfURL.appendingPathComponent("Config.wtf"), atomically: true, encoding: .utf8)
        let version = makeVersion(wowVersion: "3.3.5a", gamePath: gameURL.path)

        let settings = ConfigService.readGraphicsSettings(for: version)

        XCTAssertEqual(settings.windowMode, .fullscreen)
        XCTAssertEqual(settings.resolution, "2560x1440")
        XCTAssertEqual(settings.refreshRate, 144)
        XCTAssertTrue(settings.vsync)
        XCTAssertEqual(settings.multisampling, .x8)
        XCTAssertEqual(settings.textureFiltering, .anisotropicX16)
        XCTAssertFalse(settings.specular)
        XCTAssertTrue(settings.projectedTextures)
        XCTAssertEqual(settings.viewDistance, 1277)
        XCTAssertEqual(settings.groundEffectDensity, 2)
        XCTAssertEqual(settings.weatherDensity, 1)
        XCTAssertEqual(settings.particleDensity, 0.7)
        XCTAssertEqual(settings.shadowQuality, .low)
    }

    private func makeVersion(
        wowVersion: String,
        gamePath: String,
        settings: GraphicsSettings = GraphicsSettings()
    ) -> GameVersion {
        GameVersion(
            id: "test",
            displayName: "Test",
            wowVersion: wowVersion,
            gamePath: gamePath,
            executableName: "WoW.exe",
            supportsVanillaTweaks: wowVersion == "1.12.1",
            supportsDLLLoading: true,
            usesRosettaPatching: true,
            usesDivxDecoderPatch: false,
            settings: VersionSettings(graphicsSettings: settings)
        )
    }

    private func configContent(in gameURL: URL) throws -> String {
        try String(contentsOf: gameURL.appendingPathComponent("WTF/Config.wtf"), encoding: .utf8)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconSwiftTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempURLs.append(url)
        return url
    }
}
