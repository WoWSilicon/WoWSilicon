import XCTest
@testable import WoWSiliconSwift

final class AudioOutputServiceTests: XCTestCase {
    func testSavedDeviceArgumentsSkipHelperWhenFollowingSystemDevices() {
        XCTAssertEqual(
            AudioOutputService.savedDeviceArguments(outputID: "", inputID: ""),
            []
        )
    }

    func testSavedDeviceArgumentsIncludeOnlyOutputOverride() {
        XCTAssertEqual(
            AudioOutputService.savedDeviceArguments(outputID: "{output}", inputID: ""),
            [["set", "{output}"]]
        )
    }

    func testSavedDeviceArgumentsIncludeOnlyInputOverride() {
        XCTAssertEqual(
            AudioOutputService.savedDeviceArguments(outputID: "", inputID: "{input}"),
            [["set-input", "{input}"]]
        )
    }

    func testSavedDeviceArgumentsIncludeBothOverrides() {
        XCTAssertEqual(
            AudioOutputService.savedDeviceArguments(outputID: "{output}", inputID: "{input}"),
            [["set", "{output}"], ["set-input", "{input}"]]
        )
    }

    func testShortcutSelectionSkipsHelpersWhenFollowingSystemDevices() throws {
        XCTAssertEqual(
            try AudioOutputService.shortcutSelectionCommands(
                outputID: "",
                inputID: "",
                customVariables: ""
            ),
            []
        )
    }

    func testParsesAudioSnapshot() {
        let output = """
        O\t{output}\tAirPods Pro
        I\t{input}\tMacBook Pro Microphone
        D\tAirPods Pro\t2\t48000\t32
        """

        XCTAssertEqual(
            AudioOutputService.parseSnapshot(output),
            WineAudioSnapshot(
                outputs: [WineAudioOutputDevice(id: "{output}", name: "AirPods Pro")],
                inputs: [WineAudioOutputDevice(id: "{input}", name: "MacBook Pro Microphone")],
                details: WineAudioDetails(
                    deviceName: "AirPods Pro",
                    channelCount: 2,
                    sampleRate: 48_000,
                    bitsPerSample: 32
                )
            )
        )
    }
}
