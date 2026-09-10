import XCTest
@testable import WoWSiliconSwift

final class DependencyServiceTests: XCTestCase {
    func testRosettaProbeTreatsSuccessfulX86ExecutionAsInstalled() {
        XCTAssertTrue(DependencyService.rosettaProbeIndicatesInstalled(exitCode: 0))
    }

    func testRosettaProbeTreatsFailedX86ExecutionAsMissing() {
        XCTAssertFalse(DependencyService.rosettaProbeIndicatesInstalled(exitCode: 1))
    }

    func testRosettaInstallerUsesAppleSoftwareUpdateCommand() {
        XCTAssertEqual(
            DependencyService.rosettaInstallCommand,
            "/usr/sbin/softwareupdate --install-rosetta"
        )
    }
}
