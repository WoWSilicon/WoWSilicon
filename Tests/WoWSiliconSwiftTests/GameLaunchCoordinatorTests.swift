import XCTest
@testable import WoWSiliconSwift

@MainActor
final class GameLaunchCoordinatorTests: XCTestCase {
    func testExistingWineIsDeferredUntilUserDecision() async throws {
        let version = try XCTUnwrap(VersionManager.defaultVersions[VersionManager.defaultCurrentVersionID])
        let coordinator = GameLaunchCoordinator(
            processCountProvider: { 2 },
            gameLauncher: { _ in XCTFail("Preflight must not launch while Wine is running") }
        )

        let result = await coordinator.prepareLaunch(version: version, isAudioBusy: { false })
        guard case .existingWine(let processCount) = result else {
            return XCTFail("Expected an existing Wine result")
        }
        XCTAssertEqual(processCount, 2)

        let pending = try XCTUnwrap(coordinator.resolvePendingLaunch(cleanUp: true))
        XCTAssertEqual(pending.version, version)
        XCTAssertTrue(pending.shouldCleanUpWine)
        XCTAssertNil(coordinator.resolvePendingLaunch(cleanUp: false))
    }

    func testReadyPreflightAndSuccessfulLaunch() async throws {
        let version = try XCTUnwrap(VersionManager.defaultVersions[VersionManager.defaultCurrentVersionID])
        let launches = LaunchCounter()
        let coordinator = GameLaunchCoordinator(
            processCountProvider: { 0 },
            gameLauncher: { _ in await launches.increment() }
        )

        let preflight = await coordinator.prepareLaunch(version: version, isAudioBusy: { false })
        guard case .ready(let processCount) = preflight else {
            return XCTFail("Expected launch to be ready")
        }
        XCTAssertEqual(processCount, 0)

        let outcome = await coordinator.launchPrepared(version)
        guard case .started = outcome else {
            return XCTFail("Expected a successful launch")
        }
        let launchCount = await launches.value()
        XCTAssertEqual(launchCount, 1)
    }

    func testLaunchErrorsBecomePresentationOutcomes() async throws {
        let version = try XCTUnwrap(VersionManager.defaultVersions[VersionManager.defaultCurrentVersionID])
        let coordinator = GameLaunchCoordinator(
            gameLauncher: { _ in throw LaunchServiceError.versionMismatch("base", "tweaked") }
        )

        let outcome = await coordinator.launchPrepared(version)
        guard case .versionMismatch(let base, let tweaked) = outcome else {
            return XCTFail("Expected a version mismatch outcome")
        }
        XCTAssertEqual(base, "base")
        XCTAssertEqual(tweaked, "tweaked")
    }
}

private actor LaunchCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}
