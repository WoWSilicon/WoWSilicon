import Foundation

enum ProcessRunnerError: LocalizedError {
    case timedOut(TimeInterval)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            return "Process timed out after \(Int(seconds)) seconds."
        case .launchFailed(let reason):
            return reason
        }
    }
}

struct ProcessRunResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var combinedOutput: String {
        let combined = [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return combined
    }
}

enum ProcessRunner {
    @discardableResult
    static func run(
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        timeout: TimeInterval? = nil
    ) throws -> ProcessRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        final class DataBox: @unchecked Sendable {
            var data = Data()
        }
        let stdoutBox = DataBox()

        let stdoutThread = Thread {
            stdoutBox.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        stdoutThread.qualityOfService = .userInitiated
        stdoutThread.start()

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        if let timeout {
            let semaphore = DispatchSemaphore(value: 0)
            let originalHandler = process.terminationHandler
            process.terminationHandler = { proc in
                originalHandler?(proc)
                semaphore.signal()
            }

            let result = semaphore.wait(timeout: .now() + timeout)
            if result == .timedOut {
                process.terminate()
                usleep(500_000)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                while stdoutThread.isExecuting {
                    usleep(50_000)
                }
                throw ProcessRunnerError.timedOut(timeout)
            }
        } else {
            process.waitUntilExit()
        }

        while stdoutThread.isExecuting {
            usleep(50_000)
        }

        let stdoutString = String(data: stdoutBox.data, encoding: .utf8) ?? ""
        let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

        return ProcessRunResult(
            exitCode: process.terminationStatus,
            stdout: stdoutString,
            stderr: stderrString
        )
    }
}
