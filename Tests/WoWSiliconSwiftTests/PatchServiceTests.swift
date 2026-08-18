import Darwin
import Foundation
import XCTest
@testable import WoWSiliconSwift

final class PatchServiceTests: XCTestCase {
    func testDivxPatchingDoesNotInjectX87BackendIntoWineHelper() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PatchServiceTests-\(UUID().uuidString)", isDirectory: true)
        let runtimeRoot = temporaryRoot.appendingPathComponent("Wine", isDirectory: true)
        let runtimeBin = runtimeRoot.appendingPathComponent("bin", isDirectory: true)
        let runtimeLib = runtimeRoot.appendingPathComponent("lib", isDirectory: true)
        let gameDirectory = temporaryRoot.appendingPathComponent("Game", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeBin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtimeLib, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gameDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let wine = runtimeBin.appendingPathComponent("wine")
        let wineScript = """
        #!/bin/sh
        if [ -n "${ROSETTA_X87_PATH:-}" ] || [ -n "${X87_SIDECAR_PATH:-}" ]; then
            exit 0
        fi
        cp "$3/DivxDecoder.dll" "$3/DivxDecoder.dll.bak"
        printf x >> "$3/DivxDecoder.dll"
        """
        try wineScript.write(to: wine, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        try Data("configuration".utf8).write(to: runtimeLib.appendingPathComponent("mtld3d.conf"))

        let executable = gameDirectory.appendingPathComponent("WoW.exe")
        let decoder = gameDirectory.appendingPathComponent("DivxDecoder.dll")
        try Data("game".utf8).write(to: executable)
        let originalDecoder = Data("original decoder".utf8)
        try originalDecoder.write(to: decoder)

        let environmentOverrides = [
            BundledWineRuntime.environmentOverride: runtimeRoot.path,
            "ROSETTA_X87_PATH": "/tmp/inherited-rosetta-x87",
            "X87_SIDECAR_PATH": "/tmp/inherited-x87-sidecar",
        ]
        let previousEnvironment: [String: String?] = Dictionary(
            uniqueKeysWithValues: environmentOverrides.keys.map { key in
                (key, ProcessInfo.processInfo.environment[key])
            }
        )
        for (key, value) in environmentOverrides {
            setenv(key, value, 1)
        }
        defer {
            for (key, previousValue) in previousEnvironment {
                if let previousValue {
                    setenv(key, previousValue, 1)
                } else {
                    unsetenv(key)
                }
            }
        }

        let version = GameVersion(
            id: "patch-test",
            displayName: "Patch Test",
            wowVersion: "1.12.1",
            gamePath: executable.path,
            executableName: executable.lastPathComponent,
            supportsVanillaTweaks: false,
            supportsDLLLoading: true,
            usesRosettaPatching: true,
            usesDivxDecoderPatch: false,
            settings: VersionSettings(x87Backend: .rosettaX87)
        )

        try PatchService.applyGamePatch(for: version)

        let backup = gameDirectory.appendingPathComponent("DivxDecoder.dll.bak")
        XCTAssertEqual(try Data(contentsOf: backup), originalDecoder)
        XCTAssertNotEqual(try Data(contentsOf: decoder), originalDecoder)
        XCTAssertTrue(PatchingStatusChecker.evaluateGamePatch(for: version).applied)
    }
}
