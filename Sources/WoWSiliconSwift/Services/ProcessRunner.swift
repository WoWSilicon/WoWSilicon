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

        let fileManager = FileManager.default
        let captureDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("WoWSiliconProcess-\(UUID().uuidString)", isDirectory: true)
        let stdoutURL = captureDirectory.appendingPathComponent("stdout")
        let stderrURL = captureDirectory.appendingPathComponent("stderr")
        let stdoutHandle: FileHandle
        let stderrHandle: FileHandle

        do {
            try fileManager.createDirectory(
                at: captureDirectory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            fileManager.createFile(atPath: stdoutURL.path, contents: nil)
            fileManager.createFile(atPath: stderrURL.path, contents: nil)
            stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            stderrHandle = try FileHandle(forWritingTo: stderrURL)
        } catch {
            try? fileManager.removeItem(at: captureDirectory)
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? fileManager.removeItem(at: captureDirectory)
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        if let timeout {
            let result = semaphore.wait(timeout: .now() + timeout)
            if result == .timedOut {
                process.terminate()
                usleep(500_000)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                process.waitUntilExit()
                throw ProcessRunnerError.timedOut(timeout)
            }
        } else {
            semaphore.wait()
        }

        try? stdoutHandle.close()
        try? stderrHandle.close()

        let stdoutString = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let stderrString = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""

        return ProcessRunResult(
            exitCode: process.terminationStatus,
            stdout: stdoutString,
            stderr: stderrString
        )
    }
}
