import XCTest
@testable import WoWSiliconSwift

@MainActor
final class MainDashboardViewModelTests: XCTestCase {
    func testWineProcessPollingUsesAdaptiveIntervals() {
        XCTAssertEqual(
            MainDashboardViewModel.wineProcessPollingIntervalSeconds(
                processCount: 0,
                isLaunchOrShutdownActive: false
            ),
            10
        )
        XCTAssertEqual(
            MainDashboardViewModel.wineProcessPollingIntervalSeconds(
                processCount: 1,
                isLaunchOrShutdownActive: false
            ),
            2
        )
        XCTAssertEqual(
            MainDashboardViewModel.wineProcessPollingIntervalSeconds(
                processCount: 0,
                isLaunchOrShutdownActive: true
            ),
            1
        )
    }
}
