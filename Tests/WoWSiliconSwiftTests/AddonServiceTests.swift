import XCTest
@testable import WoWSiliconSwift

final class AddonServiceTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
        try super.tearDownWithError()
    }

    func testDiscoveryFindsRootNestedAndClientSpecificTOCs() throws {
        let repository = try makeTemporaryDirectory()
        try writeTOC(in: repository, addonName: "RootAddon")
        try writeTOC(in: repository.appendingPathComponent("modules/NestedAddon", isDirectory: true), addonName: "NestedAddon")
        try writeTOC(
            in: repository.appendingPathComponent("release/deep/WrathAddon", isDirectory: true),
            addonName: "WrathAddon_Wrath"
        )
        try writeTOC(
            in: repository.appendingPathComponent("mismatched", isDirectory: true),
            addonName: "NotTheDirectoryName"
        )

        let addons = try AddonService.discoverAddonDirectories(in: repository)

        XCTAssertEqual(addons.map(\.name), ["NestedAddon", "RootAddon", "WrathAddon"])
    }

    func testManagedRepositoryInstallScanUpdateAndDeleteLifecycle() throws {
        let game = try makeGameDirectory()
        let source = try makeGitRepository(named: "AddonPack")
        try writeTOC(
            in: source.appendingPathComponent("packages/Alpha", isDirectory: true),
            addonName: "Alpha",
            notes: "Initial Alpha"
        )
        try writeTOC(
            in: source.appendingPathComponent("packages/Beta", isDirectory: true),
            addonName: "Beta-WOTLKC",
            notes: "Initial Beta"
        )
        try commitAll(in: source, message: "Initial addons")

        try AddonService.install(from: source.absoluteString, gamePath: game.path)

        let addonsURL = game.appendingPathComponent("Interface/AddOns", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: addonsURL.appendingPathComponent("Alpha").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: addonsURL.appendingPathComponent("Beta").path))

        var scanned = try AddonService.scanAddons(gamePath: game.path, checkUpdates: false, progress: nil)
        XCTAssertEqual(scanned.count, 1)
        XCTAssertTrue(scanned[0].isManagedRepository)
        XCTAssertEqual(scanned[0].installedAddonNames, ["Alpha", "Beta"])
        XCTAssertEqual(scanned[0].description, "Includes Alpha, Beta")

        try FileManager.default.removeItem(at: source.appendingPathComponent("packages/Beta", isDirectory: true))
        try writeTOC(
            in: source.appendingPathComponent("packages/Alpha", isDirectory: true),
            addonName: "Alpha",
            notes: "Updated Alpha"
        )
        try writeTOC(
            in: source.appendingPathComponent("release/Gamma", isDirectory: true),
            addonName: "Gamma_Classic",
            notes: "New Gamma"
        )
        try commitAll(in: source, message: "Change addon bundle")

        let updated = try AddonService.update(addon: scanned[0])
        XCTAssertEqual(updated.installedAddonNames, ["Alpha", "Gamma"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: addonsURL.appendingPathComponent("Beta").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: addonsURL.appendingPathComponent("Gamma").path))

        scanned = try AddonService.scanAddons(gamePath: game.path, checkUpdates: false, progress: nil)
        XCTAssertEqual(scanned.count, 1)
        XCTAssertEqual(scanned[0].installedAddonNames, ["Alpha", "Gamma"])

        try AddonService.delete(addon: scanned[0])
        XCTAssertFalse(FileManager.default.fileExists(atPath: addonsURL.appendingPathComponent("Alpha").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: addonsURL.appendingPathComponent("Gamma").path))
        XCTAssertTrue(try AddonService.scanAddons(gamePath: game.path, checkUpdates: false, progress: nil).isEmpty)
    }

    func testInstallBacksUpAnUnmanagedConflictingAddon() throws {
        let game = try makeGameDirectory()
        let addonsURL = game.appendingPathComponent("Interface/AddOns", isDirectory: true)
        let existing = addonsURL.appendingPathComponent("Alpha", isDirectory: true)
        try writeTOC(in: existing, addonName: "Alpha", notes: "User copy")

        let source = try makeGitRepository(named: "Replacement")
        try writeTOC(in: source.appendingPathComponent("Alpha", isDirectory: true), addonName: "Alpha", notes: "Managed copy")
        try commitAll(in: source, message: "Initial addon")

        try AddonService.install(from: source.absoluteString, gamePath: game.path)

        XCTAssertTrue(FileManager.default.fileExists(atPath: addonsURL.appendingPathComponent("Alpha.bak/Alpha.toc").path))
        let installedTOC = try String(contentsOf: addonsURL.appendingPathComponent("Alpha/Alpha.toc"), encoding: .utf8)
        XCTAssertTrue(installedTOC.contains("Managed copy"))
    }

    func testLegacyDirectGitAddonRemainsVisible() throws {
        let game = try makeGameDirectory()
        let legacy = game.appendingPathComponent("Interface/AddOns/LegacyAddon", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try writeTOC(in: legacy, addonName: "LegacyAddon", notes: "Legacy install")
        try runGit(["init"], at: legacy)

        let addons = try AddonService.scanAddons(gamePath: game.path, checkUpdates: false, progress: nil)

        XCTAssertEqual(addons.count, 1)
        XCTAssertEqual(addons[0].name, "LegacyAddon")
        XCTAssertTrue(addons[0].hasGitRepo)
        XCTAssertFalse(addons[0].isManagedRepository)
    }

    func testSecondManagedRepositoryCannotReplaceAnOwnedAddon() throws {
        let game = try makeGameDirectory()
        let first = try makeGitRepository(named: "FirstPack")
        try writeTOC(in: first.appendingPathComponent("Alpha", isDirectory: true), addonName: "Alpha", notes: "First copy")
        try commitAll(in: first, message: "Initial addon")
        try AddonService.install(from: first.absoluteString, gamePath: game.path)

        let second = try makeGitRepository(named: "SecondPack")
        try writeTOC(in: second.appendingPathComponent("Alpha", isDirectory: true), addonName: "Alpha", notes: "Second copy")
        try commitAll(in: second, message: "Conflicting addon")

        XCTAssertThrowsError(try AddonService.install(from: second.absoluteString, gamePath: game.path))
        let installedTOC = try String(
            contentsOf: game.appendingPathComponent("Interface/AddOns/Alpha/Alpha.toc"),
            encoding: .utf8
        )
        XCTAssertTrue(installedTOC.contains("First copy"))
        XCTAssertEqual(try AddonService.scanAddons(gamePath: game.path, checkUpdates: false, progress: nil).count, 1)
    }

    private func makeGameDirectory() throws -> URL {
        let game = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: game.appendingPathComponent("Interface/AddOns", isDirectory: true),
            withIntermediateDirectories: true
        )
        return game
    }

    private func makeGitRepository(named name: String) throws -> URL {
        let parent = try makeTemporaryDirectory()
        let repository = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", "--initial-branch=main"], at: repository)
        try runGit(["config", "user.name", "WoWSilicon Tests"], at: repository)
        try runGit(["config", "user.email", "tests@wowsilicon.local"], at: repository)
        return repository
    }

    private func writeTOC(in directory: URL, addonName: String, notes: String = "Test addon") throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let contents = "## Interface: 30300\n## Notes: \(notes)\n"
        try contents.write(
            to: directory.appendingPathComponent("\(addonName).toc"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func commitAll(in repository: URL, message: String) throws {
        try runGit(["add", "--all"], at: repository)
        try runGit(["commit", "-m", message], at: repository)
    }

    private func runGit(_ arguments: [String], at directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            XCTFail(String(data: data, encoding: .utf8) ?? "git command failed")
            throw NSError(domain: "AddonServiceTests", code: Int(process.terminationStatus))
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconAddonTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryURLs.append(url)
        return url
    }
}
