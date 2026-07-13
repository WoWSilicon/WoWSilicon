import XCTest
@testable import WoWSiliconSwift

final class GraphicsBackendTests: XCTestCase {
    func testD9VKIsDefaultForExistingSettings() throws {
        let settings = try JSONDecoder().decode(GraphicsSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.backend, .d9vk)
        XCTAssertFalse(settings.hdrEnabled)
        XCTAssertEqual(settings.backend.wineDLLOverride, "d3d9=n")
    }

    func testD9MTUsesBuiltinD3D9() {
        XCTAssertEqual(GraphicsBackend.d9mt.wineDLLOverride, "d3d9=b")
    }

    func testLaunchersKeepBuiltinD3D9AsFallback() {
        XCTAssertEqual(GraphicsBackend.d9vk.wineDLLOverrideWithBuiltinFallback, "d3d9=n,b")
        XCTAssertEqual(GraphicsBackend.d9mt.wineDLLOverrideWithBuiltinFallback, "d3d9=b")
    }

    func testTelemetryReportsSelectedRenderer() throws {
        var version = try XCTUnwrap(VersionManager.defaultVersions["wrathsilicon"])

        version.settings.graphicsSettings.backend = .d9vk
        XCTAssertEqual(TelemetryEventContext(version: version).renderer, "d9vk")

        version.settings.graphicsSettings.backend = .d9mt
        XCTAssertEqual(TelemetryEventContext(version: version).renderer, "d9mt")
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
