import Foundation
import AppKit

enum LaunchServiceError: LocalizedError {
    case alreadyRunning
    case gamePathMissing
    case rosettaMissing(String)
    case wineMissing(String)
    case executableMissing(String)
    case vanillaTweaksMissing
    case patchNotApplied
    case processLaunchFailed(String)
    case appleScriptFailed(String)
    case versionMismatch(String, String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "The game is already running."
        case .gamePathMissing:
            return "Game path is not set. Please configure it before launching."
        case .rosettaMissing(let path):
            return "rosettax87 executable not found at \(path). Re-apply the game patch and try again."
        case .wineMissing(let path):
            return "Bundled Wine executable not found at \(path). Reinstall WoWSilicon and try again."
        case .executableMissing(let path):
            return "WoW executable not found at \(path). Please verify your game installation."
        case .vanillaTweaksMissing:
            return "Vanilla Tweaks is enabled but WoW-tweaked.exe was not found. Disable the option or run the tweaks patch first."
        case .patchNotApplied:
            return "Patches no longer appear to be applied. Re-run the patching steps before launching."
        case .processLaunchFailed(let reason):
            return reason
        case .appleScriptFailed(let reason):
            return "Failed to launch in Terminal: \(reason)"
        case .versionMismatch(let base, let tweaked):
            return "Build mismatch detected.\n\nWoW.exe: \(base)\nWoW_tweaked.exe: \(tweaked)\n\nWoWSilicon can re-generate the tweaked executable for you."
        }
    }
}

final class LaunchService: @unchecked Sendable {
    static let shared = LaunchService()

    var processDidTerminate: (() -> Void)?

    private var runningProcesses: [Process] = []
    private let processQueue = DispatchQueue(label: "com.turtlesilicon.launchservice.processes")
    private let fileManager = FileManager.default
    private var focusTimer: DispatchSourceTimer?

    private init() {}

    func launch(version: GameVersion, completion: @escaping @Sendable (Result<Void, LaunchServiceError>) -> Void) {
        do {
            let result = try prepareLaunchArtifacts(for: version)

            if !patchesAppearValid(for: version) {
                throw LaunchServiceError.patchNotApplied
            }

            if version.settings.showTerminalNormally {
                try launchViaTerminal(configuration: result)
                DispatchQueue.main.async { completion(.success(())) }
                DispatchQueue.main.async { self.processDidTerminate?() }
            } else {
                try launchIntegrated(configuration: result, completion: completion)
            }
        } catch let error as LaunchServiceError {
            DispatchQueue.main.async { completion(.failure(error)) }
        } catch {
            DispatchQueue.main.async { completion(.failure(.processLaunchFailed(error.localizedDescription))) }
        }
    }

    // MARK: - Preparation

    private struct LaunchConfiguration {
        let version: GameVersion
        let gameURL: URL
        let wowExecutableURL: URL
        let rosettaURL: URL
        let shellCommand: String
        let wineExecutablePath: String
    }

    private func prepareLaunchArtifacts(for version: GameVersion) throws -> LaunchConfiguration {
        let trimmedGame = version.gamePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGame.isEmpty else { throw LaunchServiceError.gamePathMissing }

        let gameURL = URL(fileURLWithPath: trimmedGame, isDirectory: true)
        let rosettaURL = gameURL
            .appendingPathComponent("rosettax87", isDirectory: true)
            .appendingPathComponent("rosettax87", isDirectory: false)
        guard fileManager.isExecutableFile(atPath: rosettaURL.path) else {
            throw LaunchServiceError.rosettaMissing(rosettaURL.path)
        }

        guard let wineExecutableURL = BundledWineRuntime.wineExecutableURL() else {
            let expectedPath = BundledWineRuntime.rootURL()?
                .appendingPathComponent("bin/wine", isDirectory: false).path ?? "Contents/Resources/Wine/bin/wine"
            throw LaunchServiceError.wineMissing(expectedPath)
        }

        let wowExecutableURL: URL
        if version.settings.enableVanillaTweaks {
            let tweakedURL = gameURL.appendingPathComponent("WoW_tweaked.exe")
            if fileManager.fileExists(atPath: tweakedURL.path) {
                wowExecutableURL = tweakedURL
            } else {
                throw LaunchServiceError.vanillaTweaksMissing
            }
        } else {
            let wowExe = gameURL.appendingPathComponent("WoW.exe")
            let ascensionExe = gameURL.appendingPathComponent("Ascension.exe")
            if fileManager.fileExists(atPath: wowExe.path) {
                wowExecutableURL = wowExe
            } else if fileManager.fileExists(atPath: ascensionExe.path) {
                wowExecutableURL = ascensionExe
            } else {
                wowExecutableURL = wowExe
            }
        }

        guard fileManager.fileExists(atPath: wowExecutableURL.path) else {
            throw LaunchServiceError.executableMissing(wowExecutableURL.path)
        }

        if version.settings.autoDeleteWdb {
            deleteWDBDirectories(at: gameURL)
        }

        let shellCommand = makeShellCommand(
            gameURL: gameURL,
            rosettaURL: rosettaURL,
            wowURL: wowExecutableURL,
            wineExecutablePath: wineExecutableURL.path,
            settings: version.settings
        )

        return LaunchConfiguration(
            version: version,
            gameURL: gameURL,
            wowExecutableURL: wowExecutableURL,
            rosettaURL: rosettaURL,
            shellCommand: shellCommand,
            wineExecutablePath: wineExecutableURL.path
        )
    }

    // MARK: - Launch paths

    private func launchIntegrated(configuration: LaunchConfiguration, completion: @escaping @Sendable (Result<Void, LaunchServiceError>) -> Void) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", configuration.shellCommand]
        process.environment = ProcessInfo.processInfo.environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                print("[GAME]", text)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                print("[GAME:ERR]", text)
            }
        }

        process.terminationHandler = { [weak self] _ in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.focusTimer?.cancel()
                self.focusTimer = nil
                self.untrackProcess(process)
                self.processDidTerminate?()
            }
        }

        do {
            try process.run()
            trackProcess(process)
            startFocusTimer()
            DispatchQueue.main.async { completion(.success(())) }
        } catch {
            throw LaunchServiceError.processLaunchFailed(error.localizedDescription)
        }
    }

    private func launchViaTerminal(configuration: LaunchConfiguration) throws {
        let escaped = configuration.shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application \"Terminal\"
            do script \"\(escaped)\"
            activate
        end tell
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                throw LaunchServiceError.appleScriptFailed("osascript exited with code \(task.terminationStatus)")
            }
            startFocusTimer()
        } catch let error as LaunchServiceError {
            throw error
        } catch {
            throw LaunchServiceError.appleScriptFailed(error.localizedDescription)
        }
    }

    private func makeShellCommand(gameURL: URL, rosettaURL: URL, wowURL: URL, wineExecutablePath: String, settings: VersionSettings) -> String {
        let game = doubleQuote(gameURL.path)
        let rosettaBinary = doubleQuote(rosettaURL.path)
        let wow = doubleQuote(wowURL.path)
        let wine = doubleQuote(wineExecutablePath)

        let mtlValue = settings.enableMetalHud ? "1" : "0"
        let baseEnv = "WINE_LARGE_ADDRESS_AWARE=1 WINEDLLOVERRIDES=\"d3d9=b\" MTL_HUD_ENABLED=\(mtlValue) MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=1 DXVK_ASYNC=1"
        let custom = settings.environmentVariables
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ";", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let envPart = custom.isEmpty ? baseEnv : "\(custom) \(baseEnv)"

        return "cd \(game) && ROSETTA_X87_PATH=\(rosettaBinary) \(envPart) \(wine) \(wow)"
    }

    private func doubleQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    func launchInstaller(installerURL: URL, version: GameVersion, completion: @escaping @Sendable (Result<Void, LaunchServiceError>) -> Void) {
        guard let wineExecutableURL = BundledWineRuntime.wineExecutableURL() else {
            let expectedPath = BundledWineRuntime.rootURL()?
                .appendingPathComponent("bin/wine", isDirectory: false).path ?? "Contents/Resources/Wine/bin/wine"
            DispatchQueue.main.async { completion(.failure(.wineMissing(expectedPath))) }
            return
        }

        let installer = doubleQuote(installerURL.path)
        let wine = doubleQuote(wineExecutableURL.path)
        let shellCommand = "WINEDLLOVERRIDES=\"d3d9=b\" \(wine) \(installer)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", shellCommand]
        process.environment = ProcessInfo.processInfo.environment

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.untrackProcess(process)
                self.processDidTerminate?()
                completion(.success(()))
            }
        }

        do {
            try process.run()
            trackProcess(process)
        } catch {
            DispatchQueue.main.async { completion(.failure(.processLaunchFailed(error.localizedDescription))) }
        }
    }

    func launchThirdPartyLauncher(version: GameVersion, completion: @escaping @Sendable (Result<Void, LaunchServiceError>) -> Void) {
        let exePath = version.launcherExePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !exePath.isEmpty else {
            DispatchQueue.main.async { completion(.failure(.executableMissing("No launcher configured"))) }
            return
        }

        guard let wineExecutableURL = BundledWineRuntime.wineExecutableURL() else {
            let expectedPath = BundledWineRuntime.rootURL()?
                .appendingPathComponent("bin/wine", isDirectory: false).path ?? "Contents/Resources/Wine/bin/wine"
            DispatchQueue.main.async { completion(.failure(.wineMissing(expectedPath))) }
            return
        }

        let exeURL = URL(fileURLWithPath: exePath)
        let launcherDir = doubleQuote(exeURL.deletingLastPathComponent().path)
        let exeName = doubleQuote(exeURL.lastPathComponent)
        let wine = doubleQuote(wineExecutableURL.path)

        let mtlValue = version.settings.enableMetalHud ? "1" : "0"
        let baseEnv = "WINE_LARGE_ADDRESS_AWARE=1 WINEDLLOVERRIDES=\"d3d9=b\" MTL_HUD_ENABLED=\(mtlValue) MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=1 DXVK_ASYNC=1"
        let custom = version.settings.environmentVariables
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ";", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let envPart = custom.isEmpty ? baseEnv : "\(custom) \(baseEnv)"

        let gamePatched = PatchingStatusChecker.evaluateGamePatch(for: version).applied

        let shellCommand: String
        if gamePatched {
            let rosettaURL = URL(fileURLWithPath: version.gamePath)
                .appendingPathComponent("rosettax87")
                .appendingPathComponent("rosettax87")
            let rosettaBinary = doubleQuote(rosettaURL.path)
            shellCommand = "cd \(launcherDir) && ROSETTA_X87_PATH=\(rosettaBinary) \(envPart) \(wine) \(exeName) --disable-gpu --in-process-gpu"
        } else {
            shellCommand = "cd \(launcherDir) && \(envPart) \(wine) \(exeName) --disable-gpu --in-process-gpu"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", shellCommand]
        process.environment = ProcessInfo.processInfo.environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.untrackProcess(process)
                self.processDidTerminate?()
            }
        }

        do {
            try process.run()
            trackProcess(process)
            startFocusTimer()
            DispatchQueue.main.async { completion(.success(())) }
        } catch {
            DispatchQueue.main.async { completion(.failure(.processLaunchFailed(error.localizedDescription))) }
        }
    }

    func checkVersionMismatch(for version: GameVersion) -> (base: String, tweaked: String)? {
        let trimmedGame = version.gamePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGame.isEmpty else { return nil }
        
        let gameURL = URL(fileURLWithPath: trimmedGame, isDirectory: true)
        let wowURL = gameURL.appendingPathComponent("WoW.exe")
        let tweakedURL = gameURL.appendingPathComponent("WoW_tweaked.exe")
        
        guard fileManager.fileExists(atPath: wowURL.path),
              fileManager.fileExists(atPath: tweakedURL.path) else {
            return nil
        }
        
        let baseVersion = BinaryVersionReader.readWoWVersion(from: wowURL) ?? "Unknown"
        let tweakedVersion = BinaryVersionReader.readWoWVersion(from: tweakedURL) ?? "Unknown"
        
        if baseVersion != tweakedVersion {
            return (baseVersion, tweakedVersion)
        }
        
        // Also check build number just in case the version string is the same but build changed
        let baseBuild = BinaryVersionReader.readWoWBuild(from: wowURL) ?? ""
        let tweakedBuild = BinaryVersionReader.readWoWBuild(from: tweakedURL) ?? ""
        
        if !baseBuild.isEmpty && !tweakedBuild.isEmpty && baseBuild != tweakedBuild {
            // Trim to show just the build part if it's long
            let b1 = baseBuild.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? baseBuild
            let b2 = tweakedBuild.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? tweakedBuild
            return (b1, b2)
        }
        
        return nil
    }

    private func patchesAppearValid(for version: GameVersion) -> Bool {
        let descriptor = PatchingStatusChecker.evaluateGamePatch(for: version)
        return descriptor.applied
    }

    private func startFocusTimer() {
        focusTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now() + .seconds(1), repeating: .milliseconds(500), leeway: .milliseconds(100))

        var attempts = 0
        timer.setEventHandler { [weak self, weak timer] in
            attempts += 1
            if attempts > 60 {
                timer?.cancel()
                DispatchQueue.main.async { [weak self] in self?.focusTimer = nil }
                return
            }
            guard let strongSelf = self, strongSelf.isProcessRunning(named: "wine") else { return }
            timer?.cancel()
            DispatchQueue.main.async { [weak self] in self?.focusTimer = nil }
            strongSelf.bringProcessToFront(named: "wine")
        }
        focusTimer = timer
        timer.resume()
    }

    private func isProcessRunning(named name: String) -> Bool {
        guard let result = try? ProcessRunner.run(
            executablePath: "/usr/bin/pgrep",
            arguments: ["-f", name],
            timeout: 5
        ) else {
            return false
        }
        return result.exitCode == 0
    }

    private func trackProcess(_ process: Process) {
        processQueue.sync {
            runningProcesses.append(process)
        }
    }

    private func untrackProcess(_ process: Process) {
        processQueue.sync {
            runningProcesses.removeAll { $0 === process }
        }
    }

    private func bringProcessToFront(named name: String) {
        let script = """
        tell application "System Events"
            set processList to (name of every process whose name contains "\(name)")
            if length of processList > 0 then
                set targetProcess to item 1 of processList
                tell process targetProcess
                    set frontmost to true
                end tell
            end if
        end tell
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
    }

    private func deleteWDBDirectories(at gameURL: URL) {
        let candidates = [
            gameURL.appendingPathComponent("WDB", isDirectory: true),
            gameURL.appendingPathComponent("Cache", isDirectory: true).appendingPathComponent("WDB", isDirectory: true)
        ]

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
                print("Removed WDB directory at \(url.path)")
            } catch {
                print("Failed to remove WDB directory at \(url.path): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Force quit

    static func forceQuitWine() {
        func pkill(_ args: [String]) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            p.arguments = args
            try? p.run()
            p.waitUntilExit()
        }

        // Wine processes run with their Windows path as the process name (e.g. "Z:\Volumes\...\WoW.exe").
        // pkill -f matches against the full argument string, so matching ".exe" catches them all.
        pkill(["-9", "-f", ".exe"])

        if let runtimeRoot = BundledWineRuntime.rootURL()?.path {
            for binary in ["wine", "wineserver"] {
                pkill(["-9", "-f", runtimeRoot + "/bin/" + binary])
            }
        }

        // Kill rosettax87 instances
        pkill(["-9", "-f", "rosettax87"])
    }
}
