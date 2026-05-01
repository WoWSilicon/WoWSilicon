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

enum TroubleshootingService {

    static func deleteWDBDirectories(gamePath: String?) throws -> [String] {
        guard let path = gamePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            throw TroubleshootingServiceError.gamePathMissing
        }
        let fm = FileManager.default
        let primary = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("WDB", isDirectory: true)
        let cache = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("Cache", isDirectory: true).appendingPathComponent("WDB", isDirectory: true)

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

    static func deleteWinePrefixes(gamePath: String?) throws -> [String] {
        guard let path = gamePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            throw TroubleshootingServiceError.gamePathMissing
        }
        let fm = FileManager.default
        let home = FileManager.default.homeDirectoryForCurrentUser
        let userWine = home.appendingPathComponent(".wine", isDirectory: true)
        let gameWine = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(".wine", isDirectory: true)

        var deleted: [String] = []
        if fm.fileExists(atPath: userWine.path) {
            try fm.removeItem(at: userWine)
            deleted.append(userWine.path)
        }
        if fm.fileExists(atPath: gameWine.path) {
            try fm.removeItem(at: gameWine)
            deleted.append(gameWine.path)
        }
        if deleted.isEmpty {
            throw TroubleshootingServiceError.nothingToDelete
        }
        return deleted
    }

    static func deleteVanillaTweaks(gamePath: String?) throws {
        guard let path = gamePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            throw TroubleshootingServiceError.gamePathMissing
        }
        let tweaked = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("WoW_tweaked.exe")
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

    static func generateDebugLog(context: TroubleshootingContext, hideMacUserName: Bool, includeLatestErrorLog: Bool) -> (full: String, preview: String) {
        var baseLog = "=== WoWSilicon Debug Log ===\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        baseLog += "Generated: \(formatter.string(from: Date()))\n\n"

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
            baseLog += "WoW Version: \(version.wowVersion)\n"
            baseLog += "Game Path: \(version.gamePath)\n"
            baseLog += "Executable: \(version.executableName)\n"
            baseLog += "Supports Vanilla Tweaks: \(version.supportsVanillaTweaks)\n"
            baseLog += "Supports DLL Loading: \(version.supportsDLLLoading)\n"
            baseLog += "Uses Rosetta Patching: \(version.usesRosettaPatching)\n"
            baseLog += "Uses DivX Decoder Patch: \(version.usesDivxDecoderPatch)\n"

            baseLog += "\nVersion Settings:\n"
            let settings = version.settings
            baseLog += "  Vanilla Tweaks: \(settings.enableVanillaTweaks)\n"
            baseLog += "  Remap Option as Alt: \(settings.remapOptionAsAlt)\n"
            baseLog += "  Auto Delete WDB: \(settings.autoDeleteWdb)\n"
            baseLog += "  Metal HUD: \(settings.enableMetalHud)\n"
            baseLog += "  Show Terminal Normally: \(settings.showTerminalNormally)\n"
            baseLog += "  Environment Variables: \(settings.environmentVariables)\n"
            let gs = settings.graphicsSettings
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
        } else {
            baseLog += "Current Game Version: none selected\n"
        }

        baseLog += "\n=== Paths ===\n"
        baseLog += "Game Path: \(context.gamePath ?? "Not set")\n"
        if let game = context.gamePath {
            baseLog += FileManager.default.fileExists(atPath: game) ? "  Game path exists\n" : "  Game path missing\n"
        }

        var fullLog = baseLog
        var previewLog = baseLog
        
        baseLog = "\n=== CrossOver Information ===\n"
        if let version = context.currentVersion {
            let crossOverPath = version.crossOverPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty 
                ? "/Applications/CrossOver.app" 
                : version.crossOverPath
            baseLog += "Path: \(crossOverPath)\n"
            
            let crossOverURL = URL(fileURLWithPath: crossOverPath, isDirectory: true)
            let cxVersion = PatchService.detectCrossOverVersion(at: crossOverURL)
            let cxVersionStr = cxVersion == .v26OrHigher ? "26 or newer" : "25 or older"
            baseLog += "Detected Version: \(cxVersionStr)\n"
            
            let wineloaderPath = crossOverPath + "/Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wineloader2"
            if FileManager.default.fileExists(atPath: wineloaderPath) {
                baseLog += "wineloader2: Found\n"
            } else {
                baseLog += "wineloader2: Not found\n"
            }
            
            if cxVersion == .v26OrHigher {
                let cxUnixDir = crossOverURL
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("SharedSupport", isDirectory: true)
                    .appendingPathComponent("CrossOver", isDirectory: true)
                    .appendingPathComponent("lib", isDirectory: true)
                    .appendingPathComponent("wine", isDirectory: true)
                    .appendingPathComponent("x86_64-unix", isDirectory: true)
                
                let wineBackup = cxUnixDir.appendingPathComponent("wine.bak", isDirectory: false)
                let ntdllBackup = cxUnixDir.appendingPathComponent("ntdll.so.bak", isDirectory: false)
                let ntdllActive = cxUnixDir.appendingPathComponent("ntdll.so", isDirectory: false)
                
                baseLog += "wine backup: " + (FileManager.default.fileExists(atPath: wineBackup.path) ? "✓ Found\n" : "✗ Missing\n")
                baseLog += "ntdll.so backup: " + (FileManager.default.fileExists(atPath: ntdllBackup.path) ? "✓ Found\n" : "✗ Missing\n")
                baseLog += "active ntdll.so: " + (FileManager.default.fileExists(atPath: ntdllActive.path) ? "✓ Found\n" : "✗ Missing\n")
            }
        } else {
            baseLog += "CrossOver Path: Unknown (No version selected)\n"
        }

        baseLog += "\n=== Patch Status ===\n"
        baseLog += "Game Patched: \(context.isGamePatched)\n"

        if let game = context.gamePath {
            baseLog += "\n=== Game Files ===\n"
            let gameURL = URL(fileURLWithPath: game, isDirectory: true)
            
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
                    fullLog += "Could not read Errors directory.\n"
                    previewLog += "Could not read Errors directory.\n"
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
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
