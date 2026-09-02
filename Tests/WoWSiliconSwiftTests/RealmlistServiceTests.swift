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

    func testCurrentRealmValueExtractsSetRealmlistValue() throws {
        let gameURL = try makeTemporaryDirectory()
        let realmlistURL = gameURL.appendingPathComponent("realmlist.wtf")
        try """
        SET locale "enUS"
        SET realmlist "logon.example.test"
        """.write(to: realmlistURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(RealmlistService.currentRealmValue(gamePath: gameURL.path), "logon.example.test")
    }

    func testParsesActiveCommentedAndNamedServers() {
        let content = """
        set realmlist logon.alpha.example
        #set realmlist 127.0.0.1
        # WoWSilicon: Test Realm
        # SET realmlist "logon.beta.example"
        """

        let servers = RealmlistService.servers(in: content)

        XCTAssertEqual(servers.count, 3)
        XCTAssertEqual(servers[0].displayName, "Alpha")
        XCTAssertTrue(servers[0].isActive)
        XCTAssertEqual(servers[1].address, "127.0.0.1")
        XCTAssertFalse(servers[1].isActive)
        XCTAssertEqual(servers[2].name, "Test Realm")
        XCTAssertEqual(servers[2].address, "logon.beta.example")
        XCTAssertFalse(servers[2].isActive)
    }

    func testActivatingServerPreservesUnrelatedContent() {
        let content = """
        SET locale "enUS"
        set realmlist first.example.test
        # A comment that must remain
        #set realmlist second.example.test
        SET patchlist patch.example.test
        """
        let second = RealmlistService.servers(in: content)[1]

        let updated = RealmlistService.activatingServer(id: second.id, in: content)

        XCTAssertEqual(
            updated,
            """
            SET locale "enUS"
            #set realmlist first.example.test
            # A comment that must remain
            set realmlist second.example.test
            SET patchlist patch.example.test
            """
        )
    }

    func testAddEditAndRemoveServerRoundTrip() {
        let original = "set realmlist first.example.test\n"
        let added = RealmlistService.addingServer(
            name: "Second Realm",
            address: "second.example.test",
            to: original
        )
        let addedServers = RealmlistService.servers(in: added)

        XCTAssertEqual(addedServers.count, 2)
        XCTAssertFalse(addedServers[0].isActive)
        XCTAssertTrue(addedServers[1].isActive)
        XCTAssertEqual(addedServers[1].name, "Second Realm")

        let edited = RealmlistService.updatingServer(
            id: addedServers[1].id,
            name: "Renamed Realm",
            address: "new.example.test",
            in: added
        )
        let editedServer = RealmlistService.servers(in: edited)[1]
        XCTAssertEqual(editedServer.name, "Renamed Realm")
        XCTAssertEqual(editedServer.address, "new.example.test")
        XCTAssertTrue(editedServer.isActive)

        let removed = RealmlistService.removingServer(id: editedServer.id, from: edited)
        let remaining = RealmlistService.servers(in: removed)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].address, "first.example.test")
        XCTAssertTrue(remaining[0].isActive)
        XCTAssertFalse(removed.contains("WoWSilicon:"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconSwiftTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempURLs.append(url)
        return url
    }
}
