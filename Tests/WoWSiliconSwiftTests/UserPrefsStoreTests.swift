import XCTest
@testable import WoWSiliconSwift

final class UserPrefsStoreTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
        try super.tearDownWithError()
    }

    func testSaveAndLoadRoundTripsPreferences() throws {
        let supportURL = try makeTemporaryDirectory()
        let store = UserPrefsStore(supportDirectory: supportURL)
        var prefs = UserPrefs.defaults
        prefs.telemetryInstallID = "test-install"
        prefs.wineBottlePath = "/Games/TestBottle"

        store.save(prefs)

        XCTAssertEqual(store.load(), prefs)
    }

    func testSavingUnchangedPreferencesDoesNotRewriteFile() throws {
        let supportURL = try makeTemporaryDirectory()
        let store = UserPrefsStore(supportDirectory: supportURL)
        let prefs = UserPrefs.defaults
        let prefsURL = supportURL.appendingPathComponent("WoWSilicon/prefs.json")

        store.save(prefs)
        let originalModificationDate = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: originalModificationDate],
            ofItemAtPath: prefsURL.path
        )

        store.save(prefs)

        let attributes = try FileManager.default.attributesOfItem(atPath: prefsURL.path)
        XCTAssertEqual(attributes[.modificationDate] as? Date, originalModificationDate)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconSwiftTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempURLs.append(url)
        return url
    }
}
