import XCTest
import Darwin
@testable import WoWSiliconSwift

final class LaunchServiceTests: XCTestCase {
    func testLaunchReportsPreparationFailure() async {
        var version = VersionManager.genericD3D9Template
        version.gamePath = ""
        version.settings.x87Backend = .disabled

        do {
            try await LaunchService.shared.launch(version: version)
            XCTFail("Expected gamePathMissing")
        } catch LaunchServiceError.gamePathMissing {
            // Expected.
        } catch {
            XCTFail("Expected gamePathMissing, got \(error)")
        }
    }

    func testCancelledLaunchStopsBeforePreparation() async {
        var version = VersionManager.genericD3D9Template
        version.gamePath = ""
        version.settings.x87Backend = .disabled

        let task = Task {
            try await LaunchService.shared.launch(version: version)
        }
        task.cancel()

        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected cancellation, got \(error)")
        }
    }

    func testShortcutGenerationDoesNotRewriteD3D9DLL() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconLaunchServiceTests-\(UUID().uuidString)", isDirectory: true)
        let gameDirectory = root.appendingPathComponent("Game", isDirectory: true)
        let wineRoot = root.appendingPathComponent("Wine", isDirectory: true)
        let wineExecutable = wineRoot.appendingPathComponent("bin/wine", isDirectory: false)
        try FileManager.default.createDirectory(
            at: wineExecutable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: gameDirectory, withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: wineExecutable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: wineExecutable.path
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let environmentKey = BundledWineRuntime.environmentOverride
        let previousEnvironmentValue = ProcessInfo.processInfo.environment[environmentKey]
        setenv(environmentKey, wineRoot.path, 1)
        defer {
            if let previousEnvironmentValue {
                setenv(environmentKey, previousEnvironmentValue, 1)
            } else {
                unsetenv(environmentKey)
            }
        }

        let gameExecutable = gameDirectory.appendingPathComponent("Game.exe")
        XCTAssertTrue(FileManager.default.createFile(atPath: gameExecutable.path, contents: Data()))
        var version = VersionManager.genericD3D9Template
        version.gamePath = gameExecutable.path
        version.executableName = gameExecutable.lastPathComponent
        version.settings.x87Backend = .disabled
        try PatchService.applyGamePatch(for: version)

        let installedD3D9 = gameDirectory.appendingPathComponent("d3d9.dll")
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: fixedDate],
            ofItemAtPath: installedD3D9.path
        )
        let modificationDateBefore = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: installedD3D9.path)[.modificationDate] as? Date
        )

        let script = try LaunchService.shared.shortcutShellScript(for: version)

        let modificationDateAfter = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: installedD3D9.path)[.modificationDate] as? Date
        )
        let bundledD3D9 = try XCTUnwrap(PatchService.resourceURL(
            named: "d3d9",
            extension: "dll",
            subdirectory: PatchService.d3d9ResourceSubdirectory(for: .moltenVK)
        ))
        XCTAssertEqual(modificationDateAfter, modificationDateBefore)
        XCTAssertFalse(script.contains(bundledD3D9.path))

        try Data("outdated".utf8).write(to: installedD3D9)
        XCTAssertThrowsError(try LaunchService.shared.shortcutShellScript(for: version)) { error in
            guard case LaunchServiceError.patchNotApplied = error else {
                return XCTFail("Expected patchNotApplied, got \(error)")
            }
        }
    }

    func testShellQuotePreservesMetacharactersAsOneLiteralArgument() throws {
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconShellQuote-\(UUID().uuidString)")
        let value = "path with spaces/it's/$HOME/`touch \(markerURL.path)`/$(touch \(markerURL.path))"
        defer { try? FileManager.default.removeItem(at: markerURL) }

        let quoted = LaunchService.shared.shellQuote(value)
        let result = try ProcessRunner.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "set -- \(quoted); printf '%s\\n' \"$#\" \"$1\""]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "1\n\(value)\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
    }

    func testTerminalBootstrapPrintsAndExecutesLongCommandThenRemovesFile() throws {
        let commandURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconLaunchServiceTests-\(UUID().uuidString).sh")
        let padding = String(repeating: "x", count: 2_000)
        let command = "printf 'executed'; # \(padding)"
        try (command + "\n").write(to: commandURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: commandURL) }

        let bootstrap = LaunchService.shared.terminalBootstrapCommand(scriptURL: commandURL)
        let result = try ProcessRunner.run(
            executablePath: "/usr/bin/env",
            arguments: [
                "TERM=dumb", "/bin/zsh", "-f", "-c",
                bootstrap + "; /usr/bin/printf '\\nHISTORY\\n'; fc -ln -1"
            ]
        )

        XCTAssertLessThan(bootstrap.utf8.count, 1_024)
        XCTAssertTrue(bootstrap.hasPrefix("/usr/bin/clear; "))
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, command + "\nexecuted\nHISTORY\n" + command + "\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: commandURL.path))
    }
}
