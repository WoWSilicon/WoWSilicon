import XCTest
@testable import WoWSiliconSwift

final class BundledX87RuntimeTests: XCTestCase {
    func testRosettaOverrideRequiresExecutableAndCompanionRuntime() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundledRosettaRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("rosettax87")
        let runtime = directory.appendingPathComponent("libRuntimeRosettax87")
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let environment = [BundledX87Runtime.rosettaEnvironmentOverride: executable.path]
        XCTAssertNil(BundledX87Runtime.resolve(.rosettaX87, environment: environment))

        XCTAssertTrue(FileManager.default.createFile(atPath: runtime.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtime.path)
        let resolved = BundledX87Runtime.resolve(.rosettaX87, environment: environment)
        XCTAssertEqual(resolved?.executableURL, executable)
        XCTAssertEqual(resolved?.wineEnvironmentKey, "ROSETTA_X87_PATH")
    }

    func testSidecarOverrideOnlyRequiresExecutable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundledX87RuntimeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("x87sidecar")
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let environment = [BundledX87Runtime.sidecarEnvironmentOverride: executable.path]
        let resolved = BundledX87Runtime.resolve(.x87Sidecar, environment: environment)
        XCTAssertEqual(resolved?.executableURL, executable)
        XCTAssertEqual(resolved?.wineEnvironmentKey, "X87_SIDECAR_PATH")
    }

    func testDisabledBackendNeverResolves() {
        XCTAssertNil(BundledX87Runtime.resolve(.disabled))
    }
}
