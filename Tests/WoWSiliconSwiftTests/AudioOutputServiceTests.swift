import XCTest
@testable import WoWSiliconSwift

final class AudioOutputServiceTests: XCTestCase {
    func testParsesUnicodeDeviceList() {
        let output = "{device-one}\tMacBook Pro Speakers\n{device-two}\tДинамики\n"

        XCTAssertEqual(
            AudioOutputService.parseDeviceList(output),
            [
                WineAudioOutputDevice(id: "{device-one}", name: "MacBook Pro Speakers"),
                WineAudioOutputDevice(id: "{device-two}", name: "Динамики")
            ]
        )
    }

    func testIgnoresMalformedRowsAndUsesIDForEmptyName() {
        let output = "debug noise\n{valid}\t\n\tMissing ID\n"

        XCTAssertEqual(
            AudioOutputService.parseDeviceList(output),
            [WineAudioOutputDevice(id: "{valid}", name: "{valid}")]
        )
    }
}
