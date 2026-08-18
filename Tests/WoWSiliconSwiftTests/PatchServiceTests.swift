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

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconPatchTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
