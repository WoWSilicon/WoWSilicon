import XCTest
@testable import WoWSiliconSwift

final class LaunchServiceTests: XCTestCase {
    func testTerminalBootstrapPrintsAndExecutesLongCommandThenRemovesFile() throws {
        let commandURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconLaunchServiceTests-\(UUID().uuidString).sh")
        let padding = String(repeating: "x", count: 2_000)
        let command = "# \(padding)\nprintf 'executed'"
        try (command + "\n").write(to: commandURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: commandURL) }

        let bootstrap = LaunchService.shared.terminalBootstrapCommand(scriptURL: commandURL)
        let result = try ProcessRunner.run(
            executablePath: "/usr/bin/env",
            arguments: ["TERM=dumb", "/bin/sh", "-c", bootstrap]
        )

        XCTAssertLessThan(bootstrap.utf8.count, 1_024)
        XCTAssertTrue(bootstrap.hasPrefix("/usr/bin/clear; "))
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, command + "\nexecuted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: commandURL.path))
    }
}
