import Foundation

enum DependencyInstallStatus: Equatable {
    case unknown
    case missing
    case installed
    case inProgress(String)
    case error(String)

    var text: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .missing:
            return "Not installed"
        case .installed:
            return "Installed"
        case .inProgress(let message):
            return message
        case .error(let message):
            return message
        }
    }
}

enum DependencyServiceError: LocalizedError {
    case wineMissing
    case downloadFailed(String)
    case installFailed(String)
    case verificationFailed
    case gitInstallFailed(String)

    var errorDescription: String? {
        switch self {
        case .wineMissing:
            return "CrossOver wineloader not found. Please ensure you have applied the CrossOver patch."
        case .downloadFailed(let reason):
            return "Failed to download Microsoft Visual C++ Redistributable: \(reason)"
        case .installFailed(let output):
            return output.isEmpty ? "Failed to install Microsoft Visual C++ Redistributable." : output
        case .verificationFailed:
            return "The installer finished, but the Visual C++ Runtime files were not found in the Wine prefix."
        case .gitInstallFailed(let reason):
            return reason
        }
    }
}

enum DependencyService {
    private static let visualCppX86RedistURL = URL(string: "https://aka.ms/vs/17/release/vc_redist.x86.exe")!
    private static let visualCppX64RedistURL = URL(string: "https://aka.ms/vs/17/release/vc_redist.x64.exe")!
    private static let requiredX86RuntimeDLLs = [
        "msvcp140.dll",
        "vcruntime140.dll"
    ]
    private static let requiredX64RuntimeDLLs = [
        "msvcp140.dll",
        "vcruntime140.dll",
        "vcruntime140_1.dll"
    ]
    private static let overrideDLLs = [
        "concrt140",
        "msvcp140",
        "msvcp140_1",
        "msvcp140_2",
        "msvcp140_atomic_wait",
        "msvcp140_codecvt_ids",
        "vcamp140",
        "vccorlib140",
        "vcomp140",
        "vcruntime140",
        "vcruntime140_1"
    ]

    static func isGitInstalled() -> Bool {
        guard let gitURL = gitExecutableURL() else { return false }
        let task = Process()
        task.executableURL = gitURL
        task.arguments = ["--version"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            _ = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func gitExecutableURL() -> URL? {
        let standaloneCandidates = [
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
            "/usr/local/git/bin/git"
        ]

        if let path = standaloneCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }

        if commandLineToolsInstalled(), FileManager.default.isExecutableFile(atPath: "/usr/bin/git") {
            return URL(fileURLWithPath: "/usr/bin/git")
        }

        return nil
    }

    static func installGit() throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        task.arguments = ["--install"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            throw DependencyServiceError.gitInstallFailed("Failed to open Apple's Git installer: \(error.localizedDescription)")
        }

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let output = String(data: outputData, encoding: .utf8) ?? ""
            if output.localizedCaseInsensitiveContains("already installed") || isGitInstalled() {
                return
            }
            throw DependencyServiceError.gitInstallFailed(output.isEmpty ? "Failed to open Apple's Git installer." : output)
        }
    }

    static func isVisualCppRuntimeInstalled() -> Bool {
        let prefixURL = WineRegistrySupport.winePrefixURL()
        let syswow64URL = prefixURL.appendingPathComponent("drive_c/windows/syswow64", isDirectory: true)
        let system32URL = prefixURL.appendingPathComponent("drive_c/windows/system32", isDirectory: true)

        let hasX86Runtime = requiredX86RuntimeDLLs.allSatisfy { dll in
            FileManager.default.fileExists(atPath: syswow64URL.appendingPathComponent(dll).path)
        }
        let needsX64Runtime = isWin64Prefix(prefixURL: prefixURL)
        let hasX64Runtime = requiredX64RuntimeDLLs.allSatisfy { dll in
            FileManager.default.fileExists(atPath: system32URL.appendingPathComponent(dll).path)
        }

        return hasX86Runtime && (!needsX64Runtime || hasX64Runtime) && hasVisualCppOverrides()
    }

    static func installVisualCppRuntime(crossOverPath: String?) throws {
        guard let wineExecutable = WineRegistrySupport.wineloaderPath(from: crossOverPath) else {
            throw DependencyServiceError.wineMissing
        }

        let prefixURL = WineRegistrySupport.winePrefixURL()
        try FileManager.default.createDirectory(at: prefixURL, withIntermediateDirectories: true)

        try applyVisualCppOverrides(prefixURL: prefixURL, wineExecutable: wineExecutable)

        let x86InstallerURL = try downloadVisualCppRedistributable(from: visualCppX86RedistURL, name: "vc_redist.x86.exe")
        defer { try? FileManager.default.removeItem(at: x86InstallerURL) }
        try runInstaller(installerURL: x86InstallerURL, prefixURL: prefixURL, wineExecutable: wineExecutable)

        if isWin64Prefix(prefixURL: prefixURL) {
            let x64InstallerURL = try downloadVisualCppRedistributable(from: visualCppX64RedistURL, name: "vc_redist.x64.exe")
            defer { try? FileManager.default.removeItem(at: x64InstallerURL) }
            try runInstaller(installerURL: x64InstallerURL, prefixURL: prefixURL, wineExecutable: wineExecutable)
        }

        guard isVisualCppRuntimeInstalled() else {
            throw DependencyServiceError.verificationFailed
        }
    }

    private static func downloadVisualCppRedistributable(from sourceURL: URL, name: String) throws -> URL {
        do {
            let data = try Data(contentsOf: sourceURL)
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(name, isDirectory: false)
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            throw DependencyServiceError.downloadFailed(error.localizedDescription)
        }
    }

    private static func runInstaller(installerURL: URL, prefixURL: URL, wineExecutable: String) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: wineExecutable)
        task.arguments = [installerURL.path, "/install", "/quiet", "/norestart"]

        var environment = WineRegistrySupport.makeWineEnvironment(prefixURL: prefixURL, wineExecutable: wineExecutable)
        environment["WINEDLLOVERRIDES"] = "winemenubuilder.exe=d;mscoree=d;mshtml=d"
        task.environment = environment

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            throw DependencyServiceError.installFailed(error.localizedDescription)
        }

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            let output = String(data: outputData, encoding: .utf8) ?? ""
            throw DependencyServiceError.installFailed(output)
        }
    }

    private static func applyVisualCppOverrides(prefixURL: URL, wineExecutable: String) throws {
        let regURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wowsilicon-vcrun2022-overrides.reg", isDirectory: false)
        let overrideLines = overrideDLLs
            .map { #""*\#($0)"="native,builtin""# }
            .joined(separator: "\n")
        let regContent = """
        Windows Registry Editor Version 5.00

        [HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]
        \(overrideLines)
        """

        try regContent.write(to: regURL, atomically: true, encoding: .unicode)
        defer { try? FileManager.default.removeItem(at: regURL) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: wineExecutable)
        task.arguments = ["regedit", regURL.path]
        task.environment = WineRegistrySupport.makeWineEnvironment(prefixURL: prefixURL, wineExecutable: wineExecutable)

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            throw DependencyServiceError.installFailed(error.localizedDescription)
        }

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            let output = String(data: outputData, encoding: .utf8) ?? ""
            throw DependencyServiceError.installFailed(output)
        }
    }

    private static func isWin64Prefix(prefixURL: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: prefixURL.appendingPathComponent("drive_c/windows/syswow64", isDirectory: true).path
        )
    }

    private static func hasVisualCppOverrides() -> Bool {
        guard let content = try? String(contentsOf: WineRegistrySupport.userRegURL(), encoding: .utf8) else {
            return false
        }

        return overrideDLLs.allSatisfy { dll in
            content.contains(#""*\#(dll)"="native,builtin""#)
        }
    }

    private static func commandLineToolsInstalled() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        task.arguments = ["-p"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            _ = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
