import Foundation

enum VanillaTweaksError: LocalizedError {
    case resourcesMissing
    case wowExecutableMissing(String)
    case wineMissing(String)
    case rosettaMissing
    case executionFailed(String)
    case outputMissing(String)
    case invalidParameterFormat(String)

    var errorDescription: String? {
        switch self {
        case .resourcesMissing:
            return "Could not locate vanilla-tweaks.exe in the app bundle."
        case .wowExecutableMissing(let path):
            return "WoW.exe not found at \(path)."
        case .wineMissing(let path):
            return "Bundled Wine executable not found at \(path). Reinstall WoWSilicon and try again."
        case .rosettaMissing:
            return "Bundled rosettax87 runtime is missing. Reinstall WoWSilicon and try again."
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

        guard let wineExecutable = BundledWineRuntime.wineExecutableURL() else {
            let expectedPath = BundledWineRuntime.rootURL()?
                .appendingPathComponent("bin/wine", isDirectory: false).path ?? "Contents/Resources/Wine/bin/wine"
            throw VanillaTweaksError.wineMissing(expectedPath)
        }

        let gameURL = URL(fileURLWithPath: trimmedGame, isDirectory: true)
        let wowURL = gameURL.appendingPathComponent("WoW.exe")
        guard fileManager.fileExists(atPath: wowURL.path) else {
            throw VanillaTweaksError.wowExecutableMissing(wowURL.path)
        }

        guard let tweaksURL = PatchService.resourceURL(named: "vanilla-tweaks", extension: "exe", subdirectory: "Patching/vanilla-tweaks") else {
            throw VanillaTweaksError.resourcesMissing
        }

        let workingTweaksURL = gameURL.appendingPathComponent("vanilla-tweaks.exe")
        try? fileManager.removeItem(at: workingTweaksURL)
        try fileManager.copyItem(at: tweaksURL, to: workingTweaksURL)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: Int(0o755))], ofItemAtPath: workingTweaksURL.path)

        let result = try ProcessRunner.run(
            executablePath: wineExecutable.path,
            arguments: try makeArguments(for: version.settings),
            environment: try makeWineEnvironment(wineExecutable: wineExecutable),
            currentDirectory: gameURL,
            timeout: 300
        )
        let output = result.combinedOutput

        try? fileManager.removeItem(at: workingTweaksURL)

        let tweakedPath = gameURL.appendingPathComponent("WoW_tweaked.exe")
        if !fileManager.fileExists(atPath: tweakedPath.path) {
            if result.exitCode == 0 {
                throw VanillaTweaksError.outputMissing(output)
            }
            throw VanillaTweaksError.executionFailed(output.isEmpty ? "vanilla-tweaks exited with code \(result.exitCode)" : output)
        }

        if result.exitCode != 0 {
            throw VanillaTweaksError.executionFailed(output.isEmpty ? "vanilla-tweaks exited with code \(result.exitCode)" : output)
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
    
    private static func makeWineEnvironment(wineExecutable: URL) throws -> [String: String] {
        var environment = BundledWineRuntime.makeEnvironment()
        environment["WINE_LARGE_ADDRESS_AWARE"] = "1"
        guard let rosettaExecutable = BundledRosettaRuntime.executableURL() else {
            throw VanillaTweaksError.rosettaMissing
        }
        environment["ROSETTA_X87_PATH"] = rosettaExecutable.path

        let wineDirectory = wineExecutable.deletingLastPathComponent().path
        if var path = environment["PATH"] {
            let components = path.split(separator: ":").map(String.init)
            if !components.contains(wineDirectory) {
                path = "\(wineDirectory):\(path)"
                environment["PATH"] = path
            }
        } else {
            environment["PATH"] = wineDirectory
        }
        
        return environment
    }
}
