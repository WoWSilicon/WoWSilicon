import Foundation

enum WineProcessMonitor {
    private static let wineHostExecutables: Set<String> = [
        "wine",
        "wine64",
        "wine-preloader",
        "wine64-preloader",
        "wineserver",
        "wineloader",
        "wineloader2"
    ]

    private static let wineWindowsExecutables: Set<String> = [
        "explorer.exe",
        "plugplay.exe",
        "rpcss.exe",
        "services.exe",
        "start.exe",
        "svchost.exe",
        "winedevice.exe",
        "wineboot.exe"
    ]

    static func currentProcessCount() -> Int? {
        currentProcessIDs()?.count
    }

    static func persistentProcessCount(confirmAfter delay: TimeInterval = 0.75) -> Int? {
        guard let initialCount = currentProcessCount() else { return nil }
        guard initialCount > 0 else { return 0 }

        Thread.sleep(forTimeInterval: delay)
        return currentProcessCount()
    }

    static func waitForProcessExit(timeout: TimeInterval = 3) -> Int? {
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            guard let processCount = currentProcessCount() else { return nil }
            if processCount == 0 || Date() >= deadline {
                return processCount
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    static func currentProcessIDs() -> Set<Int32>? {
        guard let result = try? ProcessRunner.run(
            executablePath: "/bin/ps",
            arguments: ["-axo", "pid=,command="],
            timeout: 5
        ), result.exitCode == 0 else {
            return nil
        }

        return processIDs(
            in: result.stdout,
            runtimeRoot: BundledWineRuntime.rootURL()?.path
        )
    }

    static func processIDs(in processList: String, runtimeRoot: String?) -> Set<Int32> {
        let normalizedRuntimeRoot = runtimeRoot?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return Set(processList.split(whereSeparator: \Character.isNewline).compactMap { line in
            let fields = line.split(maxSplits: 1, whereSeparator: \Character.isWhitespace)
            guard fields.count == 2,
                  let processID = Int32(fields[0]) else {
                return nil
            }

            let command = String(fields[1])
            return isWineProcess(command, runtimeRoot: normalizedRuntimeRoot) ? processID : nil
        })
    }

    private static func isWineProcess(_ command: String, runtimeRoot: String?) -> Bool {
        let normalizedCommand = command.lowercased()

        if let runtimeRoot, !runtimeRoot.isEmpty,
           normalizedCommand.contains(runtimeRoot) {
            return true
        }

        if normalizedCommand.contains("rosettax87")
            || normalizedCommand.contains("x87sidecar") {
            return true
        }

        let executable = command
            .split(whereSeparator: \Character.isWhitespace)
            .first
            .map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if let executable {
            let executableName = URL(fileURLWithPath: executable)
                .lastPathComponent
                .lowercased()
            if wineHostExecutables.contains(executableName) {
                return true
            }
            if wineWindowsExecutables.contains(executableName) {
                return true
            }
        }

        return looksLikeWindowsExecutable(normalizedCommand)
    }

    private static func looksLikeWindowsExecutable(_ command: String) -> Bool {
        guard command.contains(".exe") else { return false }

        let characters = Array(command)
        guard characters.count >= 4 else { return false }

        for index in 0..<(characters.count - 2) {
            if characters[index].isLetter,
               characters[index + 1] == ":",
               characters[index + 2] == "\\" {
                return true
            }
        }

        return command.contains("\\\\")
    }
}
