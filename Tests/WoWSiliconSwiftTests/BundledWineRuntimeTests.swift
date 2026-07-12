import XCTest
@testable import WoWSiliconSwift

final class BundledWineRuntimeTests: XCTestCase {
    func testRootUsesBundledResourceByDefault() {
        let resources = URL(fileURLWithPath: "/Applications/WoWSilicon.app/Contents/Resources", isDirectory: true)

        let result = BundledWineRuntime.rootURL(resourceURL: resources, environment: [:])

        XCTAssertEqual(result?.path, "/Applications/WoWSilicon.app/Contents/Resources/Wine")
    }

    func testEnvironmentOverrideTakesPrecedence() {
        let resources = URL(fileURLWithPath: "/Applications/WoWSilicon.app/Contents/Resources", isDirectory: true)

        let result = BundledWineRuntime.rootURL(
            resourceURL: resources,
            environment: [BundledWineRuntime.environmentOverride: "/tmp/custom-wine"]
        )

        XCTAssertEqual(result?.path, "/tmp/custom-wine")
    }

    func testWineExecutableRequiresExecutableFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        let wine = bin.appendingPathComponent("wine", isDirectory: false)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data().write(to: wine)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertNil(BundledWineRuntime.wineExecutableURL(
            resourceURL: nil,
            environment: [BundledWineRuntime.environmentOverride: root.path]
        ))

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)

        XCTAssertEqual(
            BundledWineRuntime.wineExecutableURL(
                resourceURL: nil,
                environment: [BundledWineRuntime.environmentOverride: root.path]
            )?.path,
            wine.path
        )
    }
}
