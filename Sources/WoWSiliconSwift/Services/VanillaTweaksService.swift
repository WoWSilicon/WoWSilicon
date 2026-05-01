import Foundation

enum VanillaTweaksError: LocalizedError {
    case resourcesMissing
    case wowExecutableMissing(String)
    case crossOverWineloaderMissing(String)
    case executionFailed(String)
    case outputMissing(String)
    case invalidParameterFormat(String)

    var errorDescription: String? {
        switch self {
        case .resourcesMissing:
            return "Could not locate vanilla-tweaks.exe in the app bundle."
        case .wowExecutableMissing(let path):
            return "WoW.exe not found at \(path)."
        case .crossOverWineloaderMissing(let path):
            return "CrossOver wineloader not found at \(path). Please ensure you have applied the CrossOver patch."
        case .executionFailed(let message):
            return message
        case .outputMissing(let output):
            return "vanilla-tweaks completed but WoW_tweaked.exe was not created.\n\(output)"
        case .invalidParameterFormat(let parameter):
            return "Invalid vanilla-tweaks parameter: \(parameter).\nUse '--flag' or '--flag value' formats."
        }
    }
}

enum VanillaTweaksService {
    static func applyTweaks(version: GameVersion) throws {
        let fileManager = FileManager.default

        guard version.supportsVanillaTweaks else {
            throw VanillaTweaksError.resourcesMissing 
        }

        let trimmedGame = version.gamePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGame.isEmpty else {
            throw VanillaTweaksError.resourcesMissing
        }

        let crossOverPath = version.crossOverPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty 
            ? "/Applications/CrossOver.app" 
            : version.crossOverPath
            
        let wineloaderPath = crossOverPath + "/Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wineloader2"
        
        guard fileManager.fileExists(atPath: wineloaderPath) else {
            throw VanillaTweaksError.crossOverWineloaderMissing(wineloaderPath)
        }

        let gameURL = URL(fileURLWithPath: trimmedGame, isDirectory: true)
        let wowURL = gameURL.appendingPathComponent("WoW.exe")
        guard fileManager.fileExists(atPath: wowURL.path) else {
            throw VanillaTweaksError.wowExecutableMissing(wowURL.path)
        }

        guard let tweaksURL = PatchService.resourceURL(named: "vanilla-tweaks", extension: "exe", subdirectory: "Patching/winerosetta") else {
            throw VanillaTweaksError.resourcesMissing
        }

        let workingTweaksURL = gameURL.appendingPathComponent("vanilla-tweaks.exe")
        try? fileManager.removeItem(at: workingTweaksURL)
        try fileManager.copyItem(at: tweaksURL, to: workingTweaksURL)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: workingTweaksURL.path)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: wineloaderPath)
        task.arguments = try makeArguments(for: version.settings)
        task.currentDirectoryURL = gameURL
        task.environment = makeWineEnvironment(wineloaderPath: wineloaderPath)

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        try task.run()
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        try? fileManager.removeItem(at: workingTweaksURL)

        let tweakedPath = gameURL.appendingPathComponent("WoW_tweaked.exe")
        if !fileManager.fileExists(atPath: tweakedPath.path) {
            if task.terminationStatus == 0 {
                throw VanillaTweaksError.outputMissing(output)
            }
            throw VanillaTweaksError.executionFailed(output.isEmpty ? "vanilla-tweaks exited with code \(task.terminationStatus)" : output)
        }

        if task.terminationStatus != 0 {
            throw VanillaTweaksError.executionFailed(output.isEmpty ? "vanilla-tweaks exited with code \(task.terminationStatus)" : output)
        }
    }

    private static func makeArguments(for settings: VersionSettings) throws -> [String] {
        let base = ["./vanilla-tweaks.exe", "--no-frilldistance", "--no-farclip"]
        let custom = try parseCustomParameters(settings.vanillaTweaksParameters)
        return base + custom + ["./WoW.exe"]
    }

    private static func parseCustomParameters(_ rawValue: String) throws -> [String] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var arguments: [String] = []
        let lines = trimmed.components(separatedBy: .newlines)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            let parts = trimmedLine.split(whereSeparator: { $0.isWhitespace })
            guard !parts.isEmpty else { continue }

            guard parts[0].hasPrefix("--") else {
                throw VanillaTweaksError.invalidParameterFormat(trimmedLine)
            }

            switch parts.count {
            case 1:
                arguments.append(String(parts[0]))
            case 2:
                arguments.append(String(parts[0]))
                arguments.append(String(parts[1]))
            default:
                throw VanillaTweaksError.invalidParameterFormat(trimmedLine)
            }
        }
        return arguments
    }
    
    private static func makeWineEnvironment(wineloaderPath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        
        let wineDirectory = (wineloaderPath as NSString).deletingLastPathComponent
        if var path = environment["PATH"] {
            let components = path.split(separator: ":").map(String.init)
            if !components.contains(wineDirectory) {
                path = "\(wineDirectory):\(path)"
                environment["PATH"] = path
            }
        } else {
            environment["PATH"] = wineDirectory
        }
        
        // vanilla-tweaks is a console app, so we might not need X11 or Mac Driver settings.
        return environment
    }
}
