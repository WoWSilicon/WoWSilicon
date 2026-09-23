import XCTest
@testable import WoWSiliconSwift

final class GraphicsBackendTests: XCTestCase {
    func testVulkanDriversUseSeparateD3D9Builds() {
        XCTAssertEqual(
            PatchService.d3d9ResourceSubdirectory(for: .moltenVK),
            "Patching/d9vk"
        )
        XCTAssertEqual(
            PatchService.d3d9ResourceSubdirectory(for: .kosmicKrisp),
            "Patching/dxvk-kosmickrisp"
        )
    }

    func testD9VKIsDefaultForExistingSettings() throws {
        let settings = try JSONDecoder().decode(GraphicsSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.backend, .d9vk)
        XCTAssertEqual(settings.vulkanDriver, .moltenVK)
        XCTAssertFalse(settings.hdrEnabled)
        XCTAssertEqual(settings.backend.wineDLLOverride, "d3d9=n")
    }

    func testKosmicKrispManifestName() {
        XCTAssertEqual(VulkanDriver.kosmicKrisp.manifestFileName, "KosmicKrisp_icd.json")
    }

    func testKosmicKrispRequiresMacOS26OrLater() {
        let macOS15 = OperatingSystemVersion(majorVersion: 15, minorVersion: 6, patchVersion: 0)
        let macOS26 = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)

        XCTAssertTrue(VulkanDriver.moltenVK.isSupported(onMacOS: macOS15))
        XCTAssertFalse(VulkanDriver.kosmicKrisp.isSupported(onMacOS: macOS15))
        XCTAssertTrue(VulkanDriver.kosmicKrisp.isSupported(onMacOS: macOS26))
    }

    func testVulkanDriverSelectionSurvivesSettingsRoundTrip() throws {
        for driver in VulkanDriver.allCases {
            let settings = GraphicsSettings(vulkanDriver: driver)
            let encoded = try JSONEncoder().encode(settings)
            let decoded = try JSONDecoder().decode(GraphicsSettings.self, from: encoded)
            XCTAssertEqual(decoded, settings)
        }
    }

    func testSelectedD3D9BuildIsInstalledWhenSwitchingDrivers() throws {
        let gameURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: gameURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: gameURL) }
        var version = try XCTUnwrap(VersionManager.defaultVersions["wrathsilicon"])
        version.gamePath = gameURL.path

        for driver in [VulkanDriver.moltenVK, .kosmicKrisp, .moltenVK] {
            version.settings.graphicsSettings.vulkanDriver = driver
            try PatchService.installD3D9DLL(for: version)
            let source = try XCTUnwrap(PatchService.resourceURL(
                named: "d3d9",
                extension: "dll",
                subdirectory: PatchService.d3d9ResourceSubdirectory(for: driver)
            ))
            XCTAssertEqual(
                try Data(contentsOf: gameURL.appendingPathComponent("d3d9.dll")),
                try Data(contentsOf: source)
            )
        }
    }

    func testMtld3dUsesBuiltinD3D9() {
        XCTAssertEqual(GraphicsBackend.mtld3d.wineDLLOverride, "d3d9=b")
    }

    func testLaunchersKeepBuiltinD3D9AsFallback() {
        XCTAssertEqual(GraphicsBackend.d9vk.wineDLLOverrideWithBuiltinFallback, "d3d9=n,b")
        XCTAssertEqual(GraphicsBackend.mtld3d.wineDLLOverrideWithBuiltinFallback, "d3d9=b")
    }

    func testTelemetryReportsSelectedRenderer() throws {
        var version = try XCTUnwrap(VersionManager.defaultVersions["wrathsilicon"])

        version.settings.graphicsSettings.backend = .d9vk
        XCTAssertEqual(TelemetryEventContext(version: version).renderer, "d9vk")

        version.settings.graphicsSettings.backend = .mtld3d
        XCTAssertEqual(TelemetryEventContext(version: version).renderer, "mtld3d")
    }

    func testTelemetryReportsSelectedX87Translation() throws {
        var version = try XCTUnwrap(VersionManager.defaultVersions["wrathsilicon"])

        version.settings.x87Backend = .rosettaX87
        XCTAssertEqual(TelemetryEventContext(version: version).x87Translation, "rosettax87")

        version.settings.x87Backend = .x87Sidecar
        XCTAssertEqual(TelemetryEventContext(version: version).x87Translation, "x87sidecar")

        version.settings.x87Backend = .disabled
        XCTAssertEqual(TelemetryEventContext(version: version).x87Translation, "disabled")
    }

    func testMtld3dHDRSettingReplacesCommentedDefault() {
        let content = "# Color\n# color.hdr.enable = false\n# Cursor\n"
        let updated = ConfigService.updateMtld3dSetting(
            content: content,
            key: "color.hdr.enable",
            value: "true"
        )

        XCTAssertEqual(updated, "# Color\ncolor.hdr.enable = true\n# Cursor\n")
    }
}
