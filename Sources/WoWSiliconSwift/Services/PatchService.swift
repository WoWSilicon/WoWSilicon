import Foundation
import Darwin

enum PatchServiceError: LocalizedError {
    case gamePathMissing
    case invalidGamePath(String)
    case gameClientNotDetected
    case resourceMissing(String)
    case fileOperationFailed(String)
    case bundledWineMissing(String)

    var errorDescription: String? {
        switch self {
        case .gamePathMissing:
            return "Game path is not set. Please choose your game directory first."
        case .invalidGamePath(let path):
            return "The selected game path is invalid or inaccessible: \(path)"
        case .gameClientNotDetected:
            return "This folder does not look like a World of Warcraft client. Select the folder containing DivxDecoder.dll."
        case .resourceMissing(let name):
            return "Bundled resource \(name) is missing from the application package."
        case .fileOperationFailed(let reason):
            return reason
        case .bundledWineMissing(let path):
            return "Bundled Wine executable not found at \(path)"
        }
    }
}

enum PatchService {
    static func applyGamePatch(for version: GameVersion) throws {
        guard !version.gamePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PatchServiceError.gamePathMissing
        }

        let gameURL = URL(fileURLWithPath: version.gamePath, isDirectory: true)
        try ensureDirectoryExists(gameURL, errorOnMissing: .invalidGamePath(version.gamePath))
        guard isSupportedGameClient(at: gameURL) else {
            throw PatchServiceError.gameClientNotDetected
        }

        let modsURL = gameURL.appendingPathComponent("mods", isDirectory: true)
        try FileManager.default.createDirectory(at: modsURL, withIntermediateDirectories: true)

        try copyResource(named: "winerosetta", extension: "dll", subdirectory: "Patching/winerosetta", to: modsURL.appendingPathComponent("winerosetta.dll"))
        try copyResource(named: "d3d9", extension: "dll", subdirectory: "Patching/d9vk", to: gameURL.appendingPathComponent("d3d9.dll"))

        // Remove legacy exe-patching artifacts
        try removeIfExists(gameURL.appendingPathComponent("Wow_patched.exe"))
        try removeIfExists(modsURL.appendingPathComponent("libDllLdr.dll"))

        if version.usesRosettaPatching && version.supportsDLLLoading {
            try copyResource(named: "libDllLdr", extension: "dll", subdirectory: "Patching/winerosetta", to: gameURL.appendingPathComponent("libDllLdr.dll"))
        } else {
            try removeIfExists(gameURL.appendingPathComponent("libDllLdr.dll"))
        }

        if version.settings.enableLibSiliconPatch, let subdir = version.libSiliconPatchSubdirectory {
            try copyResource(named: "libSiliconPatch", extension: "dll", subdirectory: subdir, to: modsURL.appendingPathComponent("libSiliconPatch.dll"))
        } else {
            try removeIfExists(modsURL.appendingPathComponent("libSiliconPatch.dll"))
        }

        // Optional utility used by vanilla tweaks
        if version.supportsVanillaTweaks, let vanillaTweaksURL = resourceURL(named: "vanilla-tweaks", extension: "exe", subdirectory: "Patching/vanilla-tweaks") {
            let destination = gameURL.appendingPathComponent("vanilla-tweaks.exe")
            try copyItem(from: vanillaTweaksURL, to: destination)
        }

        try removeIfExists(gameURL.appendingPathComponent("rosettax87", isDirectory: true))

        try updateDllsTxt(in: gameURL, enableLibSiliconPatch: version.settings.enableLibSiliconPatch && version.libSiliconPatchSubdirectory != nil)

        if version.usesRosettaPatching && version.supportsDLLLoading {
            try patchDivxDecoder(gameURL: gameURL)
        }

        ensureGxResolution(in: gameURL)
    }

    private static func patchDivxDecoder(gameURL: URL) throws {
        guard let wineExecutable = BundledWineRuntime.wineExecutableURL() else {
            let expectedPath = BundledWineRuntime.rootURL()?
                .appendingPathComponent("bin/wine", isDirectory: false).path ?? "Contents/Resources/Wine/bin/wine"
            throw PatchServiceError.bundledWineMissing(expectedPath)
        }

        var env = ProcessInfo.processInfo.environment
        env["WINEDLLOVERRIDES"] = "winemenubuilder.exe=d;mscoree=d;mshtml=d"
        env["WINEDEBUG"] = "-all"
        env["WINE_LARGE_ADDRESS_AWARE"] = "1"
        guard let rosettaExecutable = BundledRosettaRuntime.executableURL() else {
            throw PatchServiceError.resourceMissing("rosettax87 runtime")
        }
        env["ROSETTA_X87_PATH"] = rosettaExecutable.path

        let patches: [(entry: String, file: String)] = [
            ("PatchDivxDecoder", "DivxDecoder.dll"),
            ("PatchDivxTac",     "DivxTac.dll"),
        ]

        for patch in patches {
            guard FileManager.default.fileExists(atPath: gameURL.appendingPathComponent(patch.file).path) else {
                continue  // this client doesn't have this DLL — skip
            }

            let result = try ProcessRunner.run(
                executablePath: wineExecutable.path,
                arguments: ["rundll32", "libDllLdr.dll,\(patch.entry)", gameURL.path],
                environment: env,
                currentDirectory: gameURL,
                timeout: 120
            )

            if result.exitCode != 0 {
                throw PatchServiceError.fileOperationFailed("Failed to run \(patch.entry): \(result.combinedOutput)")
            }
        }
    }

    private static func revertDivxDecoder(gameURL: URL) throws {
        for name in ["DivxDecoder.dll", "DivxTac.dll"] {
            let fileURL = gameURL.appendingPathComponent(name)
            let bakURL  = gameURL.appendingPathComponent("\(name).bak")
            guard FileManager.default.fileExists(atPath: bakURL.path) else { continue }
            try removeIfExists(fileURL)
            do {
                try FileManager.default.moveItem(at: bakURL, to: fileURL)
            } catch {
                throw PatchServiceError.fileOperationFailed("Failed to restore \(name) from backup: \(error.localizedDescription)")
            }
        }
    }

    static func isSupportedGameClient(at gameURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: gameURL.appendingPathComponent("DivxDecoder.dll").path)
            || FileManager.default.fileExists(atPath: gameURL.appendingPathComponent("DivxDecoder.dll.bak").path)
    }

    static func removeGamePatch(for version: GameVersion) throws {
        guard !version.gamePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PatchServiceError.gamePathMissing
        }

        let gameURL = URL(fileURLWithPath: version.gamePath, isDirectory: true)
        try ensureDirectoryExists(gameURL, errorOnMissing: .invalidGamePath(version.gamePath))

        let modsURL = gameURL.appendingPathComponent("mods", isDirectory: true)

        try removeIfExists(modsURL.appendingPathComponent("winerosetta.dll"))
        try removeIfExists(modsURL.appendingPathComponent("libSiliconPatch.dll"))
        try removeIfExists(modsURL.appendingPathComponent("libDllLdr.dll"))
        try removeIfExists(gameURL.appendingPathComponent("libDllLdr.dll"))
        try removeIfExists(gameURL.appendingPathComponent("Wow_patched.exe"))
        try removeIfExists(gameURL.appendingPathComponent("d3d9.dll"))
        try removeIfExists(gameURL.appendingPathComponent("vanilla-tweaks.exe"))
        try removeIfExists(gameURL.appendingPathComponent("rosettax87", isDirectory: true))
        try revertDivxDecoder(gameURL: gameURL)

        try removeDllEntries(in: gameURL)

    }

    // MARK: - Helpers

    private static func ensureDirectoryExists(_ url: URL, errorOnMissing: PatchServiceError) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw errorOnMissing
        }
    }

    private static func copyResource(named name: String, extension ext: String?, subdirectory: String, to destination: URL) throws {
        guard let source = resourceURL(named: name, extension: ext, subdirectory: subdirectory) else {
            let resourceName = ext == nil ? name : "\(name).\(ext!)"
            throw PatchServiceError.resourceMissing(resourceName)
        }
        try copyItem(from: source, to: destination)
    }

    private static func copyItem(from source: URL, to destination: URL) throws {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            let reason: String
            if (error as NSError).code == EPERM {
                reason = "Insufficient permissions to modify \(destination.path). Grant the app access in System Settings > Privacy & Security > App Management."
            } else {
                reason = "Failed to copy \(source.lastPathComponent) to \(destination.path): \(error.localizedDescription)"
            }
            throw PatchServiceError.fileOperationFailed(reason)
        }
    }

    private static func removeIfExists(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw PatchServiceError.fileOperationFailed("Failed to remove \(url.path): \(error.localizedDescription)")
            }
        }
    }

    private static func ensureGxResolution(in gameURL: URL) {
        let configURL = gameURL
            .appendingPathComponent("WTF", isDirectory: true)
            .appendingPathComponent("Config.wtf", isDirectory: false)

        let fm = FileManager.default
        let configExists = fm.fileExists(atPath: configURL.path)

        if configExists {
            // WoW has historically written Config.wtf in non-UTF-8 encodings on some
            // platforms. If the read fails, do NOT fall back to empty-string —
            // that would clobber the user's entire config with a single SET line.
            var usedEncoding: UInt = 0
            guard var text = try? NSString(contentsOf: configURL, usedEncoding: &usedEncoding) as String else {
                return
            }

            let hasResolution = text.range(of: "SET\\s+gxResolution\\s+\"", options: [.regularExpression, .caseInsensitive]) != nil
            if hasResolution { return }

            if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
            text += "SET gxResolution \"2560x1600\"\n"
            let encoding = String.Encoding(rawValue: usedEncoding == 0 ? String.Encoding.utf8.rawValue : usedEncoding)
            try? text.write(to: configURL, atomically: true, encoding: encoding)
        } else {
            // Fresh install: create WTF/ and seed a minimal Config.wtf.
            let wtfDir = configURL.deletingLastPathComponent()
            try? fm.createDirectory(at: wtfDir, withIntermediateDirectories: true)
            let seed = "SET gxResolution \"2560x1600\"\n"
            try? seed.write(to: configURL, atomically: true, encoding: .utf8)
        }
    }

    private static func updateDllsTxt(in gameDirectory: URL, enableLibSiliconPatch: Bool) throws {
        let dllsURL = gameDirectory.appendingPathComponent("dlls.txt")
        var content = (try? String(contentsOf: dllsURL)) ?? ""

        func ensureEntry(_ entry: String) {
            let lines = content
                .split(whereSeparator: { $0.isNewline })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            if !lines.contains(entry.lowercased()) {
                if !content.hasSuffix("\n") && !content.isEmpty {
                    content.append("\n")
                }
                content.append(entry)
                content.append("\n")
            }
        }

        ensureEntry("mods/winerosetta.dll")
        if enableLibSiliconPatch {
            ensureEntry("mods/libSiliconPatch.dll")
        } else {
            content = content
                .split(whereSeparator: { $0.isNewline })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { line in
                    let lower = line.lowercased()
                    return lower != "mods/libsiliconpatch.dll" && lower != "libsiliconpatch.dll"
                }
                .joined(separator: "\n")
            if !content.isEmpty {
                content.append("\n")
            }
        }

        try content.write(to: dllsURL, atomically: true, encoding: .utf8)
    }

    private static func removeDllEntries(in gameDirectory: URL) throws {
        let dllsURL = gameDirectory.appendingPathComponent("dlls.txt")
        guard let content = try? String(contentsOf: dllsURL) else {
            return
        }

        let filtered = content
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                let lower = line.lowercased()
                return lower != "mods/winerosetta.dll" && lower != "mods/libsiliconpatch.dll" && lower != "libsiliconpatch.dll"
            }
            .joined(separator: "\n")

        try filtered.write(to: dllsURL, atomically: true, encoding: .utf8)
    }

    static func resourceURL(named name: String, extension ext: String?, subdirectory: String) -> URL? {
        for bundle in CandidateBundles.all {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
                return url
            }
            if let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
            if let lastComponent = subdirectory.split(separator: "/").last,
               let url = bundle.url(forResource: name, withExtension: ext, subdirectory: String(lastComponent)) {
                return url
            }
        }

        // Fallback to manually building the path inside the main bundle's resource directory.
        if let manualURL = CandidateBundles.locateManually(named: name, extension: ext, subdirectory: subdirectory) {
            return manualURL
        }

        return nil
    }
}

private enum CandidateBundles {
    private static let resourceBundleNames = [
        "WoWSilicon-swift_WoWSiliconSwift",
        "WoWSilicon_WoWSiliconSwift",
        "WoWSiliconSwift_WoWSiliconSwift"
    ]

    static let all: [Bundle] = {
        var bundles: [Bundle] = []
        var seenPaths = Set<String>()

        func addBundle(_ bundle: Bundle?) {
            guard let bundle else { return }
            let path = bundle.bundlePath
            guard !seenPaths.contains(path) else { return }
            seenPaths.insert(path)
            bundles.append(bundle)
        }

        addBundle(Bundle.main)

        if let resourceURL = Bundle.main.resourceURL {
            if let contents = try? FileManager.default.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for url in contents where url.pathExtension == "bundle" {
                    addBundle(Bundle(url: url))
                }
            }
        }

        class BundleToken {}
        let finderBundle = Bundle(for: BundleToken.self)
        addBundle(finderBundle)

        for candidate in candidateDirectories(from: finderBundle) + candidateDirectories(from: Bundle.main) {
            for name in resourceBundleNames {
                let bundleURL = candidate.appendingPathComponent("\(name).bundle")
                addBundle(Bundle(url: bundleURL))
            }
        }

        return bundles
    }()

    private static func candidateDirectories(from bundle: Bundle) -> [URL] {
        var urls: [URL] = []
        if let resourceURL = bundle.resourceURL {
            urls.append(resourceURL)
            urls.append(resourceURL.deletingLastPathComponent())
        }
        urls.append(bundle.bundleURL)
        urls.append(bundle.bundleURL.deletingLastPathComponent())
        return urls
    }

    static func locateManually(named name: String, extension ext: String?, subdirectory: String) -> URL? {
        guard let resourceRoot = Bundle.main.resourceURL else { return nil }
        let pathsToTry: [URL] = [
            resourceRoot.appendingPathComponent(subdirectory),
            resourceRoot.appendingPathComponent((subdirectory as NSString).lastPathComponent)
        ]

        let possibleFileNames: [String]
        if let ext, !ext.isEmpty {
            possibleFileNames = ["\(name).\(ext)"]
        } else {
            possibleFileNames = [name]
        }

        for directory in pathsToTry {
            for file in possibleFileNames {
                let candidate = directory.appendingPathComponent(file)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return nil
    }
}
