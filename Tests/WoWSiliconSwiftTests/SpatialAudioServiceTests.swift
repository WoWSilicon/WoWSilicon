import XCTest
@testable import WoWSiliconSwift

final class SpatialAudioServiceTests: XCTestCase {
    func testWritesRuntimeModeAtomically() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let controlURL = directory.appendingPathComponent("mode")

        try SpatialAudioService.setEnabled(true, controlURL: controlURL)

        XCTAssertEqual(try String(contentsOf: controlURL, encoding: .utf8), "fixed\n")

        let nightModeURL = directory.appendingPathComponent("night-mode")
        try SpatialAudioService.setNightMode(true, controlURL: nightModeURL)
        XCTAssertEqual(try String(contentsOf: nightModeURL, encoding: .utf8), "on\n")
        try? FileManager.default.removeItem(at: directory)
    }
}
