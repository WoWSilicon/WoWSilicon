import XCTest
@testable import WoWSiliconSwift

final class PatchServiceTests: XCTestCase {
    func testWoWStatusDoesNotExposeMissingPatchArtifacts() throws {
        let gameDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: gameDirectory) }
        try Data("original".utf8).write(to: gameDirectory.appendingPathComponent("DivxDecoder.dll"))

        var version = VersionManager.defaultVersions["vanillasilicon"]!
        version.gamePath = gameDirectory.path
        version.settings.enableLibSiliconPatch = false

        let status = PatchingStatusChecker.evaluateGamePatch(for: version)

        XCTAssertFalse(status.applied)
        XCTAssertEqual(status.text, "Not patched")
        XCTAssertTrue(status.actionable)
    }

    func testPatchValidationRequiresBackup() throws {
        let gameDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: gameDirectory) }
        try Data("patched".utf8).write(to: gameDirectory.appendingPathComponent("DivxDecoder.dll"))

        XCTAssertThrowsError(try PatchService.validatePatchedDLL(named: "DivxDecoder.dll", in: gameDirectory))
    }

    func testPatchValidationRejectsUnmodifiedDLL() throws {
        let gameDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: gameDirectory) }
        let contents = Data("same".utf8)
        try contents.write(to: gameDirectory.appendingPathComponent("DivxDecoder.dll"))
        try contents.write(to: gameDirectory.appendingPathComponent("DivxDecoder.dll.bak"))

        XCTAssertThrowsError(try PatchService.validatePatchedDLL(named: "DivxDecoder.dll", in: gameDirectory))
    }

    func testPatchValidationAcceptsModifiedDLLWithBackup() throws {
        let gameDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: gameDirectory) }
        try Data("patched".utf8).write(to: gameDirectory.appendingPathComponent("DivxDecoder.dll"))
        try Data("original".utf8).write(to: gameDirectory.appendingPathComponent("DivxDecoder.dll.bak"))

        XCTAssertNoThrow(try PatchService.validatePatchedDLL(named: "DivxDecoder.dll", in: gameDirectory))
    }

    func testNormalizeRootDllModsMovesOnlyReferencedMods() throws {
        let gameDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: gameDirectory) }

        try Data("nampower-new".utf8).write(to: gameDirectory.appendingPathComponent("nampower.dll"))
        try Data("helpers".utf8).write(to: gameDirectory.appendingPathComponent("VanillaHelpers.dll"))
        try Data("unrelated".utf8).write(to: gameDirectory.appendingPathComponent("unrelated.dll"))
        try "nampower.dll\n\nVanillaHelpers.dll\nmods/winerosetta.dll\n"
            .write(to: gameDirectory.appendingPathComponent("dlls.txt"), atomically: true, encoding: .utf8)

        try PatchService.normalizeRootDllMods(in: gameDirectory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: gameDirectory.appendingPathComponent("nampower.dll").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: gameDirectory.appendingPathComponent("VanillaHelpers.dll").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: gameDirectory.appendingPathComponent("unrelated.dll").path))
        XCTAssertEqual(
            try Data(contentsOf: gameDirectory.appendingPathComponent("mods/nampower.dll")),
            Data("nampower-new".utf8)
        )
        XCTAssertEqual(
            try String(contentsOf: gameDirectory.appendingPathComponent("dlls.txt"), encoding: .utf8),
            "mods/nampower.dll\n\nmods/VanillaHelpers.dll\nmods/winerosetta.dll\n"
        )
    }

    func testNormalizeRootDllModsUsesUpdatedRootCopy() throws {
        let gameDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: gameDirectory) }
        let modsDirectory = gameDirectory.appendingPathComponent("mods", isDirectory: true)
        try FileManager.default.createDirectory(at: modsDirectory, withIntermediateDirectories: true)

        try Data("new".utf8).write(to: gameDirectory.appendingPathComponent("nampower.dll"))
        try Data("old".utf8).write(to: modsDirectory.appendingPathComponent("nampower.dll"))
        try "nampower.dll\n".write(
            to: gameDirectory.appendingPathComponent("dlls.txt"),
            atomically: true,
            encoding: .utf8
        )

        try PatchService.normalizeRootDllMods(in: gameDirectory)

        XCTAssertEqual(
            try Data(contentsOf: modsDirectory.appendingPathComponent("nampower.dll")),
            Data("new".utf8)
        )
        XCTAssertEqual(
            try String(contentsOf: gameDirectory.appendingPathComponent("dlls.txt"), encoding: .utf8),
            "mods/nampower.dll\n"
        )
    }

    func testNormalizeRootDllModsLeavesRuntimeAndPathEntriesAlone() throws {
        let gameDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: gameDirectory) }

        try Data("graphics".utf8).write(to: gameDirectory.appendingPathComponent("d3d9.dll"))
        try Data("loader".utf8).write(to: gameDirectory.appendingPathComponent("libDllLdr.dll"))
        let originalDlls = "d3d9.dll\nlibDllLdr.dll\ncustom/other.dll\nmissing.dll\n"
        try originalDlls.write(
            to: gameDirectory.appendingPathComponent("dlls.txt"),
            atomically: true,
            encoding: .utf8
        )

        try PatchService.normalizeRootDllMods(in: gameDirectory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: gameDirectory.appendingPathComponent("d3d9.dll").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: gameDirectory.appendingPathComponent("libDllLdr.dll").path))
        XCTAssertEqual(
            try String(contentsOf: gameDirectory.appendingPathComponent("dlls.txt"), encoding: .utf8),
            originalDlls
        )
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconPatchTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
