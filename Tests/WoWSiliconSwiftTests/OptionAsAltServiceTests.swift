import XCTest
@testable import WoWSiliconSwift

final class OptionAsAltServiceTests: XCTestCase {
    func testDetectsEnabledValuesInsideMacDriverSection() {
        let registry = #"""
        WINE REGISTRY Version 2

        [Control Panel\\Desktop]
        "LogPixels"=dword:00000060

        [Software\Wine\Mac Driver]
        #time=1dbd859c084de18
        "LeftOptionIsAlt"="Y"
        "RightOptionIsAlt"="Y"

        [Software\Wine\WineDbg]
        "ShowCrashDialog"=dword:00000000
        """#

        XCTAssertTrue(OptionAsAltService.isOptionAsAltEnabled(registryContent: registry))
    }

    func testIgnoresValuesOutsideMacDriverSection() {
        let registry = #"""
        WINE REGISTRY Version 2

        [Software\Other]
        "LeftOptionIsAlt"="Y"
        "RightOptionIsAlt"="Y"
        """#

        XCTAssertFalse(OptionAsAltService.isOptionAsAltEnabled(registryContent: registry))
    }
}
