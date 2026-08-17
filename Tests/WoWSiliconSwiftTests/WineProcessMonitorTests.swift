import XCTest
@testable import WoWSiliconSwift

final class WineProcessMonitorTests: XCTestCase {
    func testRecognizesBundledWineAndWindowsChildProcesses() {
        let processList = #"""
          101 /Applications/WoWSilicon.app/Contents/Resources/Wine/bin/wine Z:\Games\WoW.exe
          102 C:\windows\system32\services.exe
          103 Z:\Games\WoW.exe
          104 /Applications/WoWSilicon.app/Contents/Resources/Patching/x87sidecar/x87sidecar /Applications/WoWSilicon.app/Contents/Resources/Wine/bin/wine Z:\Games\WoW.exe
          105 /Applications/WoWSilicon.app/Contents/Resources/Patching/rosettax87/rosettax87 /Applications/WoWSilicon.app/Contents/Resources/Wine/bin/wine
        """#

        let result = WineProcessMonitor.processIDs(
            in: processList,
            runtimeRoot: "/Applications/WoWSilicon.app/Contents/Resources/Wine"
        )

        XCTAssertEqual(result, [101, 102, 103, 104, 105])
    }

    func testRecognizesWineHostExecutablesOutsideBundledRuntime() {
        let processList = """
          201 /opt/local/bin/wineserver -p0
          202 /opt/local/bin/wine64-preloader C:\\windows\\system32\\explorer.exe
          203 /opt/local/bin/wineloader2 Z:\\Games\\WoW.exe
        """

        let result = WineProcessMonitor.processIDs(in: processList, runtimeRoot: nil)

        XCTAssertEqual(result, [201, 202, 203])
    }

    func testRecognizesWineSystemHelpersWithBasenameOnlyCommands() {
        let processList = """
          211 start.exe /exec
          212 services.exe
          213 winedevice.exe
          214 explorer.exe /desktop
        """

        let result = WineProcessMonitor.processIDs(in: processList, runtimeRoot: nil)

        XCTAssertEqual(result, [211, 212, 213, 214])
    }

    func testIgnoresUnrelatedProcessesAndExeArguments() {
        let processList = """
          301 /Applications/VeraCrypt.app/Contents/MacOS/VeraCrypt
          302 /bin/ps -axo pid=,command=
          303 /usr/bin/editor /Users/test/readme.exe
          304 /Applications/WoWSilicon.app/Contents/MacOS/WoWSilicon
        """

        let result = WineProcessMonitor.processIDs(
            in: processList,
            runtimeRoot: "/Applications/WoWSilicon.app/Contents/Resources/Wine"
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testDeduplicatesProcessIDs() {
        let processList = """
          401 /usr/local/bin/wine Z:\\Games\\WoW.exe
          401 Z:\\Games\\WoW.exe
        """

        let result = WineProcessMonitor.processIDs(in: processList, runtimeRoot: nil)

        XCTAssertEqual(result, [401])
    }
}
