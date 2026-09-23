import XCTest
@testable import WoWSiliconSwift

@MainActor
final class DependencyStatusViewModelTests: XCTestCase {
    func testRefreshesStatusesUsingInjectedOperations() async throws {
        let model = DependencyStatusViewModel(operations: makeOperations(
            visualCppInstalled: true,
            monoInstalled: false,
            gitInstalled: true,
            rosettaInstalled: false
        ))

        let tasks = [
            model.refreshVisualCppRuntimeStatus(),
            model.refreshWineMonoStatus(),
            model.refreshGitStatus(),
            model.refreshRosettaStatus()
        ]
        for task in tasks.compactMap({ $0 }) {
            await task.value
        }

        XCTAssertEqual(model.visualCppRuntimeStatus, .installed)
        XCTAssertEqual(model.wineMonoStatus, .missing)
        XCTAssertEqual(model.gitStatus, .installed)
        XCTAssertEqual(model.rosettaStatus, .missing)
    }

    func testVisualCppInstallUpdatesBusyStatusAndFeedback() async throws {
        let model = DependencyStatusViewModel(operations: makeOperations(
            visualCppInstalled: true
        ))
        var feedback: PatchFeedback?

        let task = try XCTUnwrap(model.installVisualCppRuntime(customVariables: "LANG=en_US") {
            feedback = $0
        })
        XCTAssertTrue(model.isVisualCppInstallInProgress)
        XCTAssertEqual(model.visualCppRuntimeStatus, .inProgress("Installing..."))
        await task.value

        XCTAssertFalse(model.isVisualCppInstallInProgress)
        XCTAssertEqual(model.visualCppRuntimeStatus, .installed)
        XCTAssertEqual(feedback?.title, "Dependencies")
        XCTAssertEqual(feedback?.isError, false)
    }

    func testRosettaInstallFailurePreservesErrorAndReportsFeedback() async throws {
        let model = DependencyStatusViewModel(operations: makeOperations(
            installRosetta: { throw TestDependencyError.failed }
        ))
        var feedback: PatchFeedback?

        let task = try XCTUnwrap(model.installRosetta { feedback = $0 })
        await task.value

        guard case .error(let message) = model.rosettaStatus else {
            return XCTFail("Expected an error status")
        }
        XCTAssertEqual(message, TestDependencyError.failed.localizedDescription)
        XCTAssertEqual(feedback?.title, "Rosetta 2 Install Failed")
        XCTAssertEqual(feedback?.isError, true)
    }

    private func makeOperations(
        visualCppInstalled: Bool = false,
        monoInstalled: Bool = false,
        gitInstalled: Bool = false,
        rosettaInstalled: Bool = false,
        installRosetta: @escaping @Sendable () throws -> Void = {}
    ) -> DependencyOperations {
        DependencyOperations(
            hasWineRuntime: { true },
            isVisualCppRuntimeInstalled: { visualCppInstalled },
            installVisualCppRuntime: { _ in },
            isWineMonoInstalled: { monoInstalled },
            installWineMono: { _ in },
            isGitInstalled: { gitInstalled },
            installGit: {},
            isRosettaInstalled: { rosettaInstalled },
            installRosetta: installRosetta
        )
    }
}

private enum TestDependencyError: LocalizedError {
    case failed

    var errorDescription: String? { "test failure" }
}
