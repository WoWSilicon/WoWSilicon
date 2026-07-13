import XCTest
@testable import WoWSiliconSwift

final class BundledRosettaRuntimeTests: XCTestCase {
    func testEnvironmentOverrideRequiresExecutableAndCompanionRuntime() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundledRosettaRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("rosettax87")
        let runtime = directory.appendingPathComponent("libRuntimeRosettax87")
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let environment = [BundledRosettaRuntime.environmentOverride: executable.path]
        XCTAssertNil(BundledRosettaRuntime.executableURL(environment: environment))

        XCTAssertTrue(FileManager.default.createFile(atPath: runtime.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtime.path)
        XCTAssertEqual(BundledRosettaRuntime.executableURL(environment: environment), executable)
    }
}
