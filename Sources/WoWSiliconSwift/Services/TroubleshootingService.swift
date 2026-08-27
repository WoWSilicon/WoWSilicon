import Foundation

enum TroubleshootingServiceError: LocalizedError {
    case gamePathMissing
    case nothingToDelete
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .gamePathMissing:
            return "Game path is not set. Please configure it first."
        case .nothingToDelete:
            return "Nothing to delete for this action."
        case .operationFailed(let reason):
            return reason
        }
    }
}

struct TroubleshootingContext: Sendable {
    let gamePath: String?
    let currentVersion: GameVersion?
    let isGamePatched: Bool
}

struct PermissionAccessCheck: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case passed
        case failed
        case unavailable
    }

    let id: String
    let name: String
    let status: String
    let detail: String?
    let state: State
}

enum TroubleshootingService {

    private static func gameDirectoryURL(from path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir) {
            return isDir.boolValue ? URL(fileURLWithPath: trimmed, isDirectory: true) : URL(fileURLWithPath: trimmed).deletingLastPathComponent()
        }
        let url = URL(fileURLWithPath: trimmed)
        return url.pathExtension.lowercased() == "exe" ? url.deletingLastPathComponent() : url
    }

    static func checkPermissions(
        context: TroubleshootingContext,
        wineBottleURL: URL = WineRegistrySupport.winePrefixURL()
    ) -> [PermissionAccessCheck] {
        var checks: [PermissionAccessCheck] = []
        let fileManager = FileManager.default

        guard let path = context.gamePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return [PermissionAccessCheck(
                id: "game-folder",
                name: "Game folder",
                status: "Not configured",
                detail: nil,
                state: .unavailable
            )] + runtimeAndLauncherChecks(context: context, wineBottleURL: wineBottleURL)
        }

        let gameDirectory = gameDirectoryURL(from: path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: gameDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return [PermissionAccessCheck(
                id: "game-folder",
                name: "Game folder",
                status: "Missing",
                detail: gameDirectory.path,
                state: .failed
            )] + runtimeAndLauncherChecks(context: context, wineBottleURL: wineBottleURL)
        }

        do {
            _ = try fileManager.contentsOfDirectory(atPath: gameDirectory.path)
            checks.append(PermissionAccessCheck(
                id: "game-folder-read",
                name: "Game folder read access",
                status: "Available",
                detail: gameDirectory.path,
                state: .passed
            ))
        } catch {
            checks.append(PermissionAccessCheck(
                id: "game-folder-read",
                name: "Game folder read access",
                status: "Denied",
                detail: error.localizedDescription,
                state: .failed
            ))
        }

        let probeURL = gameDirectory.appendingPathComponent(".wowsilicon-access-check-\(UUID().uuidString)")
        do {
            try Data("WoWSilicon access check".utf8).write(to: probeURL, options: .withoutOverwriting)
            try fileManager.removeItem(at: probeURL)
            checks.append(PermissionAccessCheck(
                id: "game-folder-write",
                name: "Game folder write access",
                status: "Available",
                detail: "Temporary file creation succeeded",
                state: .passed
            ))
        } catch {
            try? fileManager.removeItem(at: probeURL)
            checks.append(PermissionAccessCheck(
                id: "game-folder-write",
                name: "Game folder write access",
                status: "Denied",
                detail: error.localizedDescription,
                state: .failed
            ))
        }

        if let executableURL = context.currentVersion?.gameExecutableURL {
            checks.append(readAccessCheck(id: "game-executable", name: "Game executable", url: executableURL))
        }

        if context.currentVersion?.isWorldOfWarcraft == true {
            checks.append(readAccessCheck(
                id: "divx-decoder",
                name: "DivxDecoder.dll",
                url: gameDirectory.appendingPathComponent("DivxDecoder.dll")
            ))
        }

        checks.append(contentsOf: runtimeAndLauncherChecks(context: context, wineBottleURL: wineBottleURL))
        return checks
    }

    private static func readAccessCheck(id: String, name: String, url: URL) -> PermissionAccessCheck {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return PermissionAccessCheck(id: id, name: name, status: "Missing", detail: url.path, state: .unavailable)
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            try handle.close()
            return PermissionAccessCheck(id: id, name: name, status: "Readable", detail: nil, state: .passed)
        } catch {
            return PermissionAccessCheck(id: id, name: name, status: "Denied", detail: error.localizedDescription, state: .failed)
        }
    }

    private static func runtimeAndLauncherChecks(
        context: TroubleshootingContext,
        wineBottleURL: URL
    ) -> [PermissionAccessCheck] {
        var checks: [PermissionAccessCheck] = []
        checks.append(contentsOf: wineBottleChecks(bottleURL: wineBottleURL))
        if let launcherPath = context.currentVersion?.launcherExePath.trimmingCharacters(in: .whitespacesAndNewlines),
           !launcherPath.isEmpty {
            checks.append(readAccessCheck(
                id: "launcher-executable",
                name: "Launcher executable",
                url: URL(fileURLWithPath: launcherPath)
            ))
        } else {
            checks.append(PermissionAccessCheck(
                id: "launcher-executable",
                name: "Launcher executable",
                status: "Not configured",
                detail: nil,
                state: .unavailable
            ))
        }

        if BundledWineRuntime.wineExecutableURL() != nil {
            checks.append(PermissionAccessCheck(
                id: "wine-runtime",
                name: "Bundled Wine",
                status: "Executable",
                detail: nil,
                state: .passed
            ))
        } else {
            checks.append(PermissionAccessCheck(
                id: "wine-runtime",
                name: "Bundled Wine",
                status: "Missing or not executable",
                detail: nil,
                state: .failed
            ))
        }
        return checks
    }

    private static func wineBottleChecks(bottleURL: URL) -> [PermissionAccessCheck] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: bottleURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return [PermissionAccessCheck(
                id: "wine-bottle",
                name: "Wine bottle",
                status: "Not initialized",
                detail: bottleURL.path,
                state: .unavailable
            )]
        }

        var checks: [PermissionAccessCheck] = []
        do {
            _ = try fileManager.contentsOfDirectory(atPath: bottleURL.path)
            checks.append(PermissionAccessCheck(
                id: "wine-bottle-read",
                name: "Wine bottle read access",
                status: "Available",
                detail: bottleURL.path,
                state: .passed
            ))
        } catch {
            checks.append(PermissionAccessCheck(
                id: "wine-bottle-read",
                name: "Wine bottle read access",
                status: "Denied",
                detail: error.localizedDescription,
                state: .failed
            ))
        }

        let probeURL = bottleURL.appendingPathComponent(".wowsilicon-access-check-\(UUID().uuidString)")
        do {
            try Data("WoWSilicon access check".utf8).write(to: probeURL, options: .withoutOverwriting)
            try fileManager.removeItem(at: probeURL)
            checks.append(PermissionAccessCheck(
                id: "wine-bottle-write",
                name: "Wine bottle write access",
                status: "Available",
                detail: "Temporary file creation succeeded",
                state: .passed
            ))
        } catch {
            try? fileManager.removeItem(at: probeURL)
            checks.append(PermissionAccessCheck(
                id: "wine-bottle-write",
                name: "Wine bottle write access",
                status: "Denied",
                detail: error.localizedDescription,
                state: .failed
            ))
        }
        return checks
    }

    static func deleteWDBDirectories(gamePath: String?) throws -> [String] {
        guard let path = gamePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            throw TroubleshootingServiceError.gamePathMissing
        }
        let fm = FileManager.default
        let gameDir = gameDirectoryURL(from: path)
        let primary = gameDir.appendingPathComponent("WDB", isDirectory: true)
        let cache = gameDir.appendingPathComponent("Cache", isDirectory: true).appendingPathComponent("WDB", isDirectory: true)

        var deleted: [String] = []
        if fm.fileExists(atPath: primary.path) {
            try fm.removeItem(at: primary)
            deleted.append(primary.path)
        }
        if fm.fileExists(atPath: cache.path) {
            try fm.removeItem(at: cache)
            deleted.append(cache.path)
        }
        if deleted.isEmpty {
            throw TroubleshootingServiceError.nothingToDelete
        }
        return deleted
    }

    static func deleteWineBottle(
        bottleURL: URL = WineRegistrySupport.winePrefixURL(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> String {
        let fm = FileManager.default
        let wineBottle = try WineBottleService.validateSelectedBottleURL(
            bottleURL,
            homeDirectory: homeDirectory,
            fileManager: fm
        )
        guard WineBottleService.isWineBottle(at: wineBottle, fileManager: fm) else {
            throw TroubleshootingServiceError.nothingToDelete
        }
        try fm.removeItem(at: wineBottle)
        return wineBottle.path
    }

    static func deleteVanillaTweaks(gamePath: String?) throws {
        guard let path = gamePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            throw TroubleshootingServiceError.gamePathMissing
        }
        let tweaked = gameDirectoryURL(from: path).appendingPathComponent("WoW_tweaked.exe")
        guard FileManager.default.fileExists(atPath: tweaked.path) else {
            throw TroubleshootingServiceError.nothingToDelete
        }
        try FileManager.default.removeItem(at: tweaked)
    }

    static func resetApplicationSupport() throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("WoWSilicon", isDirectory: true)
        guard FileManager.default.fileExists(atPath: support.path) else {
            throw TroubleshootingServiceError.nothingToDelete
        }
        try FileManager.default.removeItem(at: support)
    }

    static func generateDebugLog(
        context: TroubleshootingContext,
        hideMacUserName: Bool,
        includeLatestErrorLog: Bool,
        permissionChecks: [PermissionAccessCheck]? = nil,
        wineBottleURL: URL = WineRegistrySupport.winePrefixURL()
    ) -> (full: String, preview: String) {
        var baseLog = "=== WoWSilicon Debug Log ===\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        baseLog += "Generated: \(formatter.string(from: Date()))\n"
        baseLog += "WoWSilicon Version: \(appVersion)\n\n"

        baseLog += "=== System Information ===\n"
        baseLog += "OS: macOS\n"
        let macModel = run(["/usr/sbin/sysctl", "-n", "hw.model"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
        let memSizeStr = run(["/usr/sbin/sysctl", "-n", "hw.memsize"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        let memoryGB = (Double(memSizeStr) ?? 0) / (1024 * 1024 * 1024)
        
        baseLog += "Mac Model: \(macModel)\n"
        baseLog += "Memory: \(String(format: "%.1f", memoryGB)) GB\n"
        baseLog += "Architecture: \(ProcessInfo.processInfo.processorCount)-core \(ProcessInfo.processInfo.activeProcessorCount) active\n"
        if let swVers = run(["/usr/bin/sw_vers"]) {
            baseLog += "macOS Version:\n\(swVers)\n"
        }

        baseLog += "\n=== WoWSilicon Configuration ===\n"
        if let version = context.currentVersion {
            baseLog += "Current Game Version: \(version.displayName) (\(version.id))\n"
            baseLog += "Profile Type: \(version.profileKind.rawValue)\n"
            if version.isWorldOfWarcraft {
                baseLog += "WoW Version: \(version.wowVersion)\n"
            }
            baseLog += "Game Path: \(version.gamePath)\n"
            baseLog += "Executable: \(version.executableName)\n"
            baseLog += "Supports Vanilla Tweaks: \(version.supportsVanillaTweaks)\n"
            baseLog += "Supports DLL Loading: \(version.supportsDLLLoading)\n"
            baseLog += "Uses Rosetta Patching: \(version.usesRosettaPatching)\n"
            baseLog += "Uses DivX Decoder Patch: \(version.usesDivxDecoderPatch)\n"

            baseLog += "\nVersion Settings:\n"
            let settings = version.settings
            baseLog += "  x87 Translation: \(settings.x87Backend.displayName) (\(settings.x87Backend.rawValue))\n"
            baseLog += "  Vanilla Tweaks: \(settings.enableVanillaTweaks)\n"
            baseLog += "  Remap Option as Alt: \(settings.remapOptionAsAlt)\n"
            baseLog += "  Auto Delete WDB: \(settings.autoDeleteWdb)\n"
            baseLog += "  Metal HUD: \(settings.enableMetalHud)\n"
            baseLog += "  Show Terminal Normally: \(settings.showTerminalNormally)\n"
            baseLog += "  Environment Variables: \(settings.environmentVariables)\n"
            let gs = settings.graphicsSettings
            baseLog += "  Graphics Backend: \(gs.backend.displayName)\n"
            if version.supportsCustomGraphicsSettings {
                baseLog += "  HDR Mode: \(gs.backend == .mtld3d && gs.hdrEnabled)\n"
                baseLog += "  Window Mode: \(gs.windowMode.rawValue)\n"
                baseLog += "  Resolution: \(gs.resolution.isEmpty ? "default" : gs.resolution)\n"
                baseLog += "  Refresh Rate: \(gs.refreshRate)Hz\n"
                baseLog += "  VSync: \(gs.vsync)\n"
                baseLog += "  Multisampling: \(gs.multisampling.rawValue)\n"
                baseLog += "  Texture Filtering: \(gs.textureFiltering.rawValue)\n"
                baseLog += "  Shadow Quality: \(gs.shadowQuality.rawValue)\n"
                baseLog += "  View Distance: \(gs.viewDistance)\n"
                baseLog += "  Particle Density: \(gs.particleDensity)\n"
                baseLog += "  Enable LibSilicon Patch: \(settings.enableLibSiliconPatch)\n"
            }
        } else {
            baseLog += "Current Game Version: none selected\n"
        }

        baseLog += "\n=== Paths ===\n"
        baseLog += "Game Path: \(context.gamePath ?? "Not set")\n"
        baseLog += "Wine Bottle: \(wineBottleURL.path)\n"
        baseLog += WineBottleService.isWineBottle(at: wineBottleURL)
            ? "  Wine bottle initialized\n"
            : "  Wine bottle not initialized\n"
        if let game = context.gamePath {
            baseLog += FileManager.default.fileExists(atPath: game) ? "  Game path exists\n" : "  Game path missing\n"
        }

        baseLog += "\n=== Permissions & Access ===\n"
        for check in permissionChecks ?? checkPermissions(context: context, wineBottleURL: wineBottleURL) {
            baseLog += "\(check.name): \(check.status)\n"
            if let detail = check.detail {
                baseLog += "  \(detail)\n"
            }
        }

        var fullLog = baseLog
        var previewLog = baseLog
        
        baseLog = "\n=== Bundled Wine Runtime ===\n"
        if let runtimeURL = BundledWineRuntime.rootURL() {
            baseLog += "Path: \(runtimeURL.path)\n"
            baseLog += "Wine executable: \(BundledWineRuntime.wineExecutableURL() == nil ? "Missing" : "Found")\n"

            let lockURL = runtimeURL
                .appendingPathComponent("share", isDirectory: true)
                .appendingPathComponent("wowsilicon", isDirectory: true)
                .appendingPathComponent("runtime-lock.json", isDirectory: false)
            if let data = try? Data(contentsOf: lockURL),
               let lock = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                baseLog += "Runtime revision: \(lock["runtimeRevision"] ?? "Unknown")\n"
                if let wine = lock["wine"] as? [String: Any] {
                    baseLog += "Wine version: \(wine["version"] ?? "Unknown")\n"
                    baseLog += "Wine commit: \(wine["commit"] ?? "Unknown")\n"
                }
                if let mtld3d = lock["mtld3d"] as? [String: Any] {
                    baseLog += "MTLd3D version: \(mtld3d["version"] ?? "Unknown")\n"
                }
            } else {
                baseLog += "Runtime lock: Missing\n"
            }
        } else {
            baseLog += "Path: Missing\n"
        }

        baseLog += "\n=== Patch Status ===\n"
        baseLog += "Game Patched: \(context.isGamePatched)\n"

        if let game = context.gamePath {
            baseLog += "\n=== Game Files ===\n"
            let gameURL = gameDirectoryURL(from: game)
            
            // Directory listing
            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: gameURL.path)
                let files = contents.filter { 
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: gameURL.appendingPathComponent($0).path, isDirectory: &isDir)
                    return !isDir.boolValue
                }.sorted()
                
                baseLog += "Game Path Directory Contents (Files):\n"
                for file in files {
                    baseLog += "  \(file)\n"
                }
                baseLog += "\n"
            } catch {
                baseLog += "Failed to list game directory: \(error.localizedDescription)\n\n"
            }

            let dllsURL = gameURL.appendingPathComponent("dlls.txt")
            if let content = try? String(contentsOf: dllsURL) {
                baseLog += "dlls.txt content:\n\(content)\n"
            } else {
                baseLog += "dlls.txt not found.\n"
            }
            let tweaked = gameURL.appendingPathComponent("WoW_tweaked.exe")
            baseLog += FileManager.default.fileExists(atPath: tweaked.path) ? "WoW_tweaked.exe: ✓ Found\n" : "WoW_tweaked.exe: Not found\n"
            let config = gameURL.appendingPathComponent("WTF", isDirectory: true).appendingPathComponent("Config.wtf")
            if let content = try? String(contentsOf: config) {
                baseLog += "Config.wtf (WTF):\n\(content)\n"
            }
            
            fullLog += baseLog
            previewLog += baseLog
            
            if includeLatestErrorLog {
                let errorTitle = "\n=== Latest Error Log ===\n"
                fullLog += errorTitle
                previewLog += errorTitle
                
                let errorsURL = gameURL.appendingPathComponent("Errors", isDirectory: true)
                do {
                    let contents = try FileManager.default.contentsOfDirectory(at: errorsURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
                    let txtFiles = contents.filter { $0.pathExtension == "txt" }
                    let sorted = try txtFiles.sorted {
                        let date1 = try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date.distantPast
                        let date2 = try $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date.distantPast
                        return date1 > date2
                    }
                    if let latest = sorted.first, let content = try? String(contentsOf: latest) {
                        let fileLine = "File: \(latest.lastPathComponent)\n\n"
                        fullLog += fileLine
                        previewLog += fileLine
                        
                        fullLog += content + "\n"
                        
                        // Limit size just in case it's massive for preview
                        let maxLen = 10000
                        if content.count > maxLen {
                            previewLog += content.prefix(maxLen) + "\n\n... (truncated)\n"
                        } else {
                            previewLog += content + "\n"
                        }
                    } else {
                        fullLog += "No .txt error logs found in Errors directory.\n"
                        previewLog += "No .txt error logs found in Errors directory.\n"
                    }
                } catch {
                    let message = "Could not read Errors directory: \(error.localizedDescription)\n"
                    fullLog += message
                    previewLog += message
                }
            }
        } else {
            fullLog += baseLog
            previewLog += baseLog
        }

        if hideMacUserName {
            let userName = NSUserName()
            fullLog = fullLog.replacingOccurrences(of: "/Users/\(userName)", with: "/Users/[REDACTED]")
            fullLog = fullLog.replacingOccurrences(of: "Z:\\\\Users\\\\\(userName)", with: "Z:\\\\Users\\\\[REDACTED]")
            fullLog = fullLog.replacingOccurrences(of: "Z:\\Users\\\(userName)", with: "Z:\\Users\\[REDACTED]")
            
            previewLog = previewLog.replacingOccurrences(of: "/Users/\(userName)", with: "/Users/[REDACTED]")
            previewLog = previewLog.replacingOccurrences(of: "Z:\\\\Users\\\\\(userName)", with: "Z:\\\\Users\\\\[REDACTED]")
            previewLog = previewLog.replacingOccurrences(of: "Z:\\Users\\\(userName)", with: "Z:\\Users\\[REDACTED]")
        }

        return (full: fullLog, preview: previewLog)
    }

    private static func run(_ components: [String]) -> String? {
        guard let executable = components.first else { return nil }
        let args = Array(components.dropFirst())
        guard let result = try? ProcessRunner.run(
            executablePath: executable,
            arguments: args,
            timeout: 10
        ) else {
            return nil
        }
        return result.combinedOutput
    }
}
