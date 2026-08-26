import XCTest
@testable import WoWSiliconSwift

final class ProcessRunnerTests: XCTestCase {
    func testReturnsWithoutWaitingForBackgroundProcessHoldingOutputFilesOpen() throws {
        let start = Date()
        let result = try ProcessRunner.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf stdout; printf stderr >&2; sleep 2 &"]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "stdout")
        XCTAssertEqual(result.stderr, "stderr")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)
    }

    func testTimeoutStillTerminatesTheDirectProcess() {
        XCTAssertThrowsError(
            try ProcessRunner.run(
                executablePath: "/bin/sleep",
                arguments: ["2"],
                timeout: 0.05
            )
        ) { error in
            guard case ProcessRunnerError.timedOut = error else {
                return XCTFail("Expected a timeout, got \(error)")
            }
        }
    }
}
