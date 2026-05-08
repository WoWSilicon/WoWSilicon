import Foundation
import Darwin
import CryptoKit

enum PatchServiceError: LocalizedError {
    case gamePathMissing
    case invalidGamePath(String)
    case resourceMissing(String)
    case fileOperationFailed(String)
    case crossOverNotFound
    case unsupportedCrossOverVersion
    case crossOverWineloaderMissing(String)

    var errorDescription: String? {
        switch self {
        case .gamePathMissing:
            return "Game path is not set. Please choose your game directory first."
        case .invalidGamePath(let path):
            return "The selected game path is invalid or inaccessible: \(path)"
        case .resourceMissing(let name):
            return "Bundled resource \(name) is missing from the application package."
        case .fileOperationFailed(let reason):
            return reason
        case .crossOverNotFound:
            return "CrossOver.app not found at /Applications/CrossOver.app"
        case .unsupportedCrossOverVersion:
            return "CrossOver 26 is required for this WoWSilicon version."
        case .crossOverWineloaderMissing(let path):
            return "CrossOver wineloader not found at \(path)"
        }
    }
}

enum PatchService {
    enum CrossOverVersion {
        case v25OrLower
        case v26
        case v27OrHigher
    }

    static func detectCrossOverVersion(at crossOverURL: URL) -> CrossOverVersion {
        let plistURL = crossOverURL.appendingPathComponent("Contents/Info.plist")
        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let versionString = plist["CFBundleShortVersionString"] as? String,
           let majorVersion = Int(versionString.split(separator: ".").first ?? "") {
            
            if majorVersion < 26 {
                return .v25OrLower
            } else if majorVersion == 26 {
                return .v26
            } else {
                return .v27OrHigher
            }
        }
        
        // Fallback: Check if the new wine binary location exists
        let winev26Path = crossOverURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("SharedSupport", isDirectory: true)
            .appendingPathComponent("CrossOver", isDirectory: true)
            .appendingPathComponent("lib", isDirectory: true)
            .appendingPathComponent("wine", isDirectory: true)
            .appendingPathComponent("x86_64-unix", isDirectory: true)
            .appendingPathComponent("wine", isDirectory: false)
            
        return FileManager.default.fileExists(atPath: winev26Path.path) ? .v26 : .v25OrLower
    }

    static func applyGamePatch(for version: GameVersion) throws {
        guard !version.gamePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PatchServiceError.gamePathMissing
        }

        let gameURL = URL(fileURLWithPath: version.gamePath, isDirectory: true)
        try ensureDirectoryExists(gameURL, errorOnMissing: .invalidGamePath(version.gamePath))

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

        let rosettaURL = gameURL.appendingPathComponent("rosettax87", isDirectory: true)
        if FileManager.default.fileExists(atPath: rosettaURL.path) {
            try FileManager.default.removeItem(at: rosettaURL)
        }
        try FileManager.default.createDirectory(at: rosettaURL, withIntermediateDirectories: true)
        try copyResource(named: "rosettax87", extension: nil, subdirectory: "Patching/rosettax87", to: rosettaURL.appendingPathComponent("rosettax87"), makeExecutable: true)
        try copyResource(named: "libRuntimeRosettax87", extension: nil, subdirectory: "Patching/rosettax87", to: rosettaURL.appendingPathComponent("libRuntimeRosettax87"), makeExecutable: true)

        try updateDllsTxt(in: gameURL, enableLibSiliconPatch: version.settings.enableLibSiliconPatch && version.libSiliconPatchSubdirectory != nil)

        if version.usesRosettaPatching && version.supportsDLLLoading {
            try patchDivxDecoder(version: version, gameURL: gameURL)
        }

    }

    private static func patchDivxDecoder(version: GameVersion, gameURL: URL) throws {
        let wineloaderPath = resolveWineloaderPath(for: version)
        guard FileManager.default.fileExists(atPath: wineloaderPath) else {
            throw PatchServiceError.crossOverWineloaderMissing(wineloaderPath)
        }

        var env = ProcessInfo.processInfo.environment
        env["WINEDLLOVERRIDES"] = "winemenubuilder.exe=d;mscoree=d;mshtml=d"
        env["WINEDEBUG"] = "-all"

        let patches: [(entry: String, file: String)] = [
            ("PatchDivxDecoder", "DivxDecoder.dll"),
            ("PatchDivxTac",     "DivxTac.dll"),
        ]

        for patch in patches {
            guard FileManager.default.fileExists(atPath: gameURL.appendingPathComponent(patch.file).path) else {
                continue  // this client doesn't have this DLL — skip
            }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: wineloaderPath)
            task.environment = env
            task.arguments = ["rundll32", "libDllLdr.dll,\(patch.entry)", gameURL.path]
            task.currentDirectoryURL = gameURL

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            try task.run()
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if task.terminationStatus != 0 {
                let output = String(data: outputData, encoding: .utf8) ?? ""
                throw PatchServiceError.fileOperationFailed("Failed to run \(patch.entry): \(output)")
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

    private static func resolveWineloaderPath(for version: GameVersion) -> String {
        let crossOverPath = version.crossOverPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "/Applications/CrossOver.app"
            : version.crossOverPath
        return crossOverPath + "/Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wineloader2"
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
        try removeIfExists(gameURL.appendingPathComponent("rosettax87"))
        try revertDivxDecoder(gameURL: gameURL)

        try removeDllEntries(in: gameURL)

    }

    static func applyCrossOverPatch(crossOverPath: String? = nil) throws {
        let resolvedPath = crossOverPath ?? "/Applications/CrossOver.app"
        let crossOverURL = URL(fileURLWithPath: resolvedPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: crossOverURL.path) else {
            throw PatchServiceError.crossOverNotFound
        }

        let crossOverVersion = detectCrossOverVersion(at: crossOverURL)
        guard crossOverVersion == .v26 else {
            throw PatchServiceError.unsupportedCrossOverVersion
        }

        let wineloaderBasePath = crossOverURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("SharedSupport", isDirectory: true)
            .appendingPathComponent("CrossOver", isDirectory: true)
            .appendingPathComponent("CrossOver-Hosted Application", isDirectory: true)

        let wineloaderOrig = wineloaderBasePath.appendingPathComponent("wineloader", isDirectory: false)
        guard FileManager.default.fileExists(atPath: wineloaderOrig.path) else {
            throw PatchServiceError.crossOverWineloaderMissing(wineloaderOrig.path)
        }

        let wineloaderCopy = wineloaderBasePath.appendingPathComponent("wineloader2", isDirectory: false)

        // Copy wineloader to wineloader2
        try copyItem(from: wineloaderOrig, to: wineloaderCopy)

        // Remove code signature from wineloader2
        try removeSignature(at: wineloaderCopy)

        // Set executable permissions
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: wineloaderCopy.path)

        if crossOverVersion == .v26 {
            let cxUnixDir = crossOverURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("SharedSupport", isDirectory: true)
                .appendingPathComponent("CrossOver", isDirectory: true)
                .appendingPathComponent("lib", isDirectory: true)
                .appendingPathComponent("wine", isDirectory: true)
                .appendingPathComponent("x86_64-unix", isDirectory: true)

            let wineBinary = cxUnixDir.appendingPathComponent("wine", isDirectory: false)
            let wineBackup = cxUnixDir.appendingPathComponent("wine.bak", isDirectory: false)
            
            if FileManager.default.fileExists(atPath: wineBinary.path) && isSigned(at: wineBinary) {
                try copyItem(from: wineBinary, to: wineBackup)
            }
            if FileManager.default.fileExists(atPath: wineBinary.path) {
                try removeSignature(at: wineBinary)
            }

            let ntdllBinary = cxUnixDir.appendingPathComponent("ntdll.so", isDirectory: false)
            let ntdllBackup = cxUnixDir.appendingPathComponent("ntdll.so.bak", isDirectory: false)

            guard let bundledNtdllURL = resourceURL(named: "ntdll", extension: "so", subdirectory: "Patching/winerosetta") else {
                throw PatchServiceError.resourceMissing("ntdll.so")
            }

            let isPatched = fileChecksum(at: ntdllBinary) == fileChecksum(at: bundledNtdllURL)
            if !isPatched {
                if FileManager.default.fileExists(atPath: ntdllBinary.path) && isSignedByCodeWeavers(at: ntdllBinary) {
                    try copyItem(from: ntdllBinary, to: ntdllBackup)
                }
                try copyResource(named: "ntdll", extension: "so", subdirectory: "Patching/winerosetta", to: ntdllBinary)
            }
        }
    }

    static func removeCrossOverPatch(crossOverPath: String? = nil) throws {
        let resolvedPath = crossOverPath ?? "/Applications/CrossOver.app"
        let crossOverURL = URL(fileURLWithPath: resolvedPath, isDirectory: true)
        
        let crossOverVersion = FileManager.default.fileExists(atPath: crossOverURL.path) ? detectCrossOverVersion(at: crossOverURL) : .v25OrLower

        let wineloader2URL = crossOverURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("SharedSupport", isDirectory: true)
            .appendingPathComponent("CrossOver", isDirectory: true)
            .appendingPathComponent("CrossOver-Hosted Application", isDirectory: true)
            .appendingPathComponent("wineloader2", isDirectory: false)

        try removeIfExists(wineloader2URL)

        if crossOverVersion == .v26 {
            let cxUnixDir = crossOverURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("SharedSupport", isDirectory: true)
                .appendingPathComponent("CrossOver", isDirectory: true)
                .appendingPathComponent("lib", isDirectory: true)
                .appendingPathComponent("wine", isDirectory: true)
                .appendingPathComponent("x86_64-unix", isDirectory: true)

            let wineBinary = cxUnixDir.appendingPathComponent("wine", isDirectory: false)
            let wineBackup = cxUnixDir.appendingPathComponent("wine.bak", isDirectory: false)
            
            if FileManager.default.fileExists(atPath: wineBackup.path) {
                try copyItem(from: wineBackup, to: wineBinary)
                try removeIfExists(wineBackup)
            }

            let ntdllBinary = cxUnixDir.appendingPathComponent("ntdll.so", isDirectory: false)
            let ntdllBackup = cxUnixDir.appendingPathComponent("ntdll.so.bak", isDirectory: false)

            if FileManager.default.fileExists(atPath: ntdllBackup.path) {
                try copyItem(from: ntdllBackup, to: ntdllBinary)
                try removeIfExists(ntdllBackup)
            }
        }
    }


    // MARK: - Helpers

    private static func ensureDirectoryExists(_ url: URL, errorOnMissing: PatchServiceError) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw errorOnMissing
        }
    }

    private static func copyResource(named name: String, extension ext: String?, subdirectory: String, to destination: URL, makeExecutable: Bool = false) throws {
        guard let source = resourceURL(named: name, extension: ext, subdirectory: subdirectory) else {
            let resourceName = ext == nil ? name : "\(name).\(ext!)"
            throw PatchServiceError.resourceMissing(resourceName)
        }
        try copyItem(from: source, to: destination)

        if makeExecutable {
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: destination.path)
        }
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

    private static func removeSignature(at url: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["--remove-signature", url.path]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                let output = String(data: outputData, encoding: .utf8) ?? ""
                try? FileManager.default.removeItem(at: url)
                throw PatchServiceError.fileOperationFailed(output.isEmpty ? "codesign --remove-signature failed." : output)
            }
        } catch let error as PatchServiceError {
            throw error
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw PatchServiceError.fileOperationFailed("codesign --remove-signature failed: \(error.localizedDescription)")
        }
    }

    static func isSigned(at url: URL) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-d", url.path]
        let pipe = Pipe()
        task.standardError = pipe
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    static func isSignedByCodeWeavers(at url: URL) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dvv", url.path]
        let pipe = Pipe()
        task.standardError = pipe
        try? task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0, let output = String(data: data, encoding: .utf8) else { return false }
        return output.contains("CodeWeavers")
    }

    static func fileChecksum(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
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
