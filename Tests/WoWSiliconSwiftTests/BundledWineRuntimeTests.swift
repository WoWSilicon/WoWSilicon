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

    func testEnvironmentIncludesBundledExternalLibrariesAndPreservesExistingPath() {
        let environment = BundledWineRuntime.makeEnvironment(
            resourceURL: nil,
            environment: [
                BundledWineRuntime.environmentOverride: "/tmp/custom-wine",
                "DYLD_LIBRARY_PATH": "/tmp/existing"
            ]
        )

        XCTAssertEqual(
            environment["DYLD_LIBRARY_PATH"],
            "/tmp/custom-wine/lib/external:/tmp/existing"
        )
    }

    func testEnvironmentRemovesX87TranslationFromHelperProcesses() {
        let environment = BundledWineRuntime.makeEnvironment(
            resourceURL: nil,
            environment: [
                "ROSETTA_X87_PATH": "/tmp/rosettax87",
                "X87_SIDECAR_PATH": "/tmp/x87sidecar",
                "PRESERVED": "value",
            ]
        )

        XCTAssertNil(environment["ROSETTA_X87_PATH"])
        XCTAssertNil(environment["X87_SIDECAR_PATH"])
        XCTAssertEqual(environment["PRESERVED"], "value")
    }

    func testEnvironmentIncludesCustomLocaleVariables() {
        let environment = BundledWineRuntime.makeEnvironment(
            customVariables: "LANG=ru_RU.UTF-8\nLC_ALL=ru_RU.UTF-8",
            resourceURL: nil,
            environment: [BundledWineRuntime.environmentOverride: "/tmp/custom-wine"]
        )

        XCTAssertEqual(environment["LANG"], "ru_RU.UTF-8")
        XCTAssertEqual(environment["LC_ALL"], "ru_RU.UTF-8")
    }

    func testCustomEnvironmentParserSupportsDocumentedAndLegacySeparators() {
        let environment = BundledWineRuntime.parseEnvironmentVariables("""
        LANG=ru_RU.UTF-8
        TOKEN=value=with=equals;LC_ALL=ru_RU.UTF-8
        # COMMENTED=value
        INVALID KEY=value
        """)

        XCTAssertEqual(environment["LANG"], "ru_RU.UTF-8")
        XCTAssertEqual(environment["LC_ALL"], "ru_RU.UTF-8")
        XCTAssertEqual(environment["TOKEN"], "value=with=equals")
        XCTAssertNil(environment["COMMENTED"])
        XCTAssertNil(environment["INVALID KEY"])
    }

    func testCustomEnvironmentCannotEnableX87ForHelperProcesses() {
        let environment = BundledWineRuntime.makeEnvironment(
            customVariables: "ROSETTA_X87_PATH=/tmp/rosettax87\nLANG=ru_RU.UTF-8",
            resourceURL: nil,
            environment: [:]
        )

        XCTAssertNil(environment["ROSETTA_X87_PATH"])
        XCTAssertEqual(environment["LANG"], "ru_RU.UTF-8")
    }

    func testShellEnvironmentAssignmentsQuoteValues() {
        let assignments = BundledWineRuntime.shellEnvironmentAssignments("""
        LANG=ru_RU.UTF-8
        MESSAGE=it's safe
        ROSETTA_X87_PATH=/tmp/rosettax87
        """)

        XCTAssertEqual(assignments, "LANG='ru_RU.UTF-8' MESSAGE='it'\\''s safe'")
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

    func testMtld3dConfigurationUsesRuntimeLibDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let lib = root.appendingPathComponent("lib", isDirectory: true)
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = lib.appendingPathComponent("mtld3d.conf")
        XCTAssertTrue(FileManager.default.createFile(atPath: configuration.path, contents: Data()))

        let environment = [BundledWineRuntime.environmentOverride: root.path]
        XCTAssertEqual(
            BundledWineRuntime.mtld3dConfigurationURL(resourceURL: nil, environment: environment),
            configuration
        )
    }
}
