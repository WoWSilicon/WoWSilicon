import XCTest
@testable import WoWSiliconSwift

final class DXVKConfigServiceTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
        try super.tearDownWithError()
    }

    func testSetCursorSizeMultiplierCreatesConfig() throws {
        let gameURL = try makeTemporaryDirectory()

        try DXVKConfigService.setCursorSizeMultiplier(gamePath: gameURL.path, multiplier: 4)

        let configURL = gameURL.appendingPathComponent("dxvk.conf")
        let content = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertEqual(content, "d3d9.enlargeHardwareCursor = 4\n")
        XCTAssertEqual(DXVKConfigService.cursorSizeMultiplier(gamePath: gameURL.path), 4)
    }

    func testSetCursorSizeMultiplierUpdatesExistingLine() throws {
        let gameURL = try makeTemporaryDirectory()
        let configURL = gameURL.appendingPathComponent("dxvk.conf")
        try """
        dxvk.enableAsync = True
          d3d9.enlargeHardwareCursor = 2
        d3d9.presentInterval = 1
        """.write(to: configURL, atomically: true, encoding: .utf8)

        try DXVKConfigService.setCursorSizeMultiplier(gamePath: gameURL.path, multiplier: 4)

        let content = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(content.contains("dxvk.enableAsync = True"))
        XCTAssertTrue(content.contains("d3d9.enlargeHardwareCursor = 4"))
        XCTAssertTrue(content.contains("d3d9.presentInterval = 1"))
        XCTAssertFalse(content.contains("d3d9.enlargeHardwareCursor = 2"))
    }

    func testSetCursorSizeMultiplierRemovesLineForDefaultSize() throws {
        let gameURL = try makeTemporaryDirectory()
        let configURL = gameURL.appendingPathComponent("dxvk.conf")
        try """
        dxvk.enableAsync = True
        d3d9.enlargeHardwareCursor = 4
        d3d9.presentInterval = 1
        """.write(to: configURL, atomically: true, encoding: .utf8)

        try DXVKConfigService.setCursorSizeMultiplier(gamePath: gameURL.path, multiplier: 1)

        let content = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertFalse(content.contains("d3d9.enlargeHardwareCursor"))
        XCTAssertTrue(content.contains("dxvk.enableAsync = True"))
        XCTAssertTrue(content.contains("d3d9.presentInterval = 1"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconSwiftTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempURLs.append(url)
        return url
    }
}
