import XCTest
@testable import WoWSiliconSwift

final class SpatialAudioServiceTests: XCTestCase {
    func testWritesRuntimeModeAtomically() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let controlURL = directory.appendingPathComponent("mode")

        try SpatialAudioService.setEnabled(true, controlURL: controlURL)

        XCTAssertEqual(try String(contentsOf: controlURL, encoding: .utf8), "fixed\n")
        try? FileManager.default.removeItem(at: directory)
    }
}
