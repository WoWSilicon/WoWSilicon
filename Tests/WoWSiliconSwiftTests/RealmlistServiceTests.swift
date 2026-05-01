import XCTest
@testable import WoWSiliconSwift

final class RealmlistServiceTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
        try super.tearDownWithError()
    }

    func testFindReturnsNoneForEmptyPath() {
        if case .none = RealmlistService.find(gamePath: "   ") {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected no realmlist for an empty game path")
        }
    }

    func testFindReturnsSingleRealmlistWithContent() throws {
        let gameURL = try makeTemporaryDirectory()
        let realmlistURL = gameURL
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("enUS", isDirectory: true)
            .appendingPathComponent("realmlist.wtf")
        try FileManager.default.createDirectory(at: realmlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "set realmlist logon.example.test\n".write(to: realmlistURL, atomically: true, encoding: .utf8)

        switch RealmlistService.find(gamePath: gameURL.path) {
        case .single(let url, let content):
            XCTAssertEqual(url.standardizedFileURL.path, realmlistURL.standardizedFileURL.path)
            XCTAssertEqual(content, "set realmlist logon.example.test\n")
        default:
            XCTFail("Expected one realmlist")
        }
    }

    func testFindIgnoresExtractedDirectoriesAndReportsMultipleRealmlists() throws {
        let gameURL = try makeTemporaryDirectory()
        let first = gameURL.appendingPathComponent("realmlist.wtf")
        let second = gameURL
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("enUS", isDirectory: true)
            .appendingPathComponent("realmlist.wtf")
        let ignored = gameURL
            .appendingPathComponent("Extracted", isDirectory: true)
            .appendingPathComponent("realmlist.wtf")

        try FileManager.default.createDirectory(at: second.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ignored.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "".write(to: first, atomically: true, encoding: .utf8)
        try "".write(to: second, atomically: true, encoding: .utf8)
        try "".write(to: ignored, atomically: true, encoding: .utf8)

        switch RealmlistService.find(gamePath: gameURL.path) {
        case .multiple(let urls):
            let paths = Set(urls.map { $0.standardizedFileURL.path })
            XCTAssertEqual(paths, Set([first.standardizedFileURL.path, second.standardizedFileURL.path]))
        default:
            XCTFail("Expected multiple realmlists")
        }
    }

    func testWriteUpdatesRealmlistContent() throws {
        let gameURL = try makeTemporaryDirectory()
        let realmlistURL = gameURL.appendingPathComponent("realmlist.wtf")

        try RealmlistService.write(content: "set realmlist localhost\n", to: realmlistURL)

        XCTAssertEqual(try String(contentsOf: realmlistURL, encoding: .utf8), "set realmlist localhost\n")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconSwiftTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempURLs.append(url)
        return url
    }
}
