import Foundation

enum ConfigServiceError: LocalizedError {
    case gamePathMissing
    case unableToCreateDirectories(String)
    case readFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .gamePathMissing:
            return "Game path is not set. Configure it before applying graphics settings."
        case .unableToCreateDirectories(let details):
            return "Failed to create WTF directory: \(details)"
        case .readFailed(let details):
            return "Failed to read Config.wtf: \(details)"
        case .writeFailed(let details):
            return "Failed to write Config.wtf: \(details)"
        }
    }
}

struct ConfigService {

    // MARK: - Public API

    static func applyGraphicsSettings(for version: GameVersion) throws {
        let gs = version.settings.graphicsSettings
        let configURL = try configFileURL(for: version)
        var content = (try? String(contentsOf: configURL)) ?? ""

        func set(_ key: String, _ value: String) {
            content = updateOrInsertSetting(content: content, key: key, value: value)
        }
        func remove(_ key: String) {
            content = removeSetting(content: content, key: key)
        }

        // Display — gxWindow always 1 (true fullscreen causes issues on macOS); gxMaximize drives windowed vs borderless
        set("gxWindow", "1")
        set("gxMaximize", gs.windowMode == .fullscreen ? "1" : "0")
        if !gs.resolution.isEmpty {
            set("gxResolution", gs.resolution)
        }
        set("gxRefresh", String(gs.refreshRate))
        set("gxVSync", gs.vsync ? "1" : "0")

        // Multisampling
        if let samples = gs.multisampling.configValue {
            set("gxMultisample", String(samples))
            set("gxMultisampleQuality", "0.000000")
            set("gxColorBits", "24")
            set("gxDepthBits", "24")
        } else {
            remove("gxMultisample")
            remove("gxMultisampleQuality")
            remove("gxColorBits")
            remove("gxDepthBits")
        }

        // Texture filtering — key depends on client version
        applyTextureFiltering(version: version, filtering: gs.textureFiltering, set: set)

        // Lighting
        set("specular", gs.specular ? "1" : "0")

        // Projected textures (TBC+ only)
        if version.wowVersion != "1.12.1" {
            set("projectedTextures", gs.projectedTextures ? "1" : "0")
        }

        // View distance
        set("farclip", String(gs.viewDistance))

        // Ground effects — key depends on client version
        applyGroundEffect(version: version, density: gs.groundEffectDensity, set: set, remove: remove)

        // Weather
        set("weatherDensity", String(gs.weatherDensity))

        // Particles
        let particleStr = String(format: "%.1f", gs.particleDensity)
        set("particleDensity", particleStr)

        // Shadows
        applyShadowSettings(version: version, quality: gs.shadowQuality, set: set, remove: remove)

        try content.write(to: configURL, atomically: true, encoding: .utf8)
        try applyMtld3dSettings(for: version)
    }

    static func applyMtld3dSettings(for version: GameVersion) throws {
        let configURL = URL(fileURLWithPath: version.gamePath, isDirectory: true)
            .appendingPathComponent("mtld3d.conf", isDirectory: false)
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }

        do {
            let content = try String(contentsOf: configURL, encoding: .utf8)
            let graphics = version.settings.graphicsSettings
            let hdrEnabled = graphics.backend == .d9mt && graphics.hdrEnabled
            let updated = updateMtld3dSetting(
                content: content,
                key: "color.hdr.enable",
                value: hdrEnabled ? "true" : "false"
            )
            try updated.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            throw ConfigServiceError.writeFailed("Failed to update mtld3d.conf: \(error.localizedDescription)")
        }
    }

    static func updateMtld3dSetting(content: String, key: String, value: String) -> String {
        var lines = content.components(separatedBy: .newlines)
        let replacement = "\(key) = \(value)"

        if let index = lines.firstIndex(where: { line in
            var candidate = line.trimmingCharacters(in: .whitespaces)
            if candidate.hasPrefix("#") {
                candidate.removeFirst()
                candidate = candidate.trimmingCharacters(in: .whitespaces)
            }
            guard let rawKey = candidate.split(separator: "=", maxSplits: 1).first else {
                return false
            }
            return String(rawKey).trimmingCharacters(in: .whitespaces) == key
        }) {
            lines[index] = replacement
        } else {
            if lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append(replacement)
        }
        return lines.joined(separator: "\n")
    }

    static func readGraphicsSettings(for version: GameVersion) -> GraphicsSettings {
        guard let configURL = try? configFileURL(for: version),
              let content = try? String(contentsOf: configURL) else {
            return GraphicsSettings()
        }

        var gs = version.settings.graphicsSettings

        if let v = readSetting(content: content, key: "gxMaximize") {
            gs.windowMode = v == "1" ? .fullscreen : .windowed
        }
        if let v = readSetting(content: content, key: "gxResolution"), !v.isEmpty {
            gs.resolution = v
        }
        if let v = readSetting(content: content, key: "gxRefresh"), let i = Int(v) {
            gs.refreshRate = i
        }
        if let v = readSetting(content: content, key: "gxVSync") {
            gs.vsync = v == "1"
        }

        // Multisampling
        if let v = readSetting(content: content, key: "gxMultisample"), let n = Int(v) {
            switch n {
            case 2:  gs.multisampling = .x2
            case 4:  gs.multisampling = .x4
            case 8:  gs.multisampling = .x8
            default: gs.multisampling = .off
            }
        }

        // Texture filtering
        if version.wowVersion == "1.12.1" {
            if let aniso = readSetting(content: content, key: "anisotropic"), Int(aniso) ?? 0 > 1 {
                gs.textureFiltering = .anisotropicX16
            } else if let tri = readSetting(content: content, key: "trilinear") {
                gs.textureFiltering = tri == "1" ? .trilinear : .bilinear
            }
        } else {
            if let v = readSetting(content: content, key: "textureFilteringMode"), let n = Int(v) {
                switch n {
                case 0:  gs.textureFiltering = .bilinear
                case 1:  gs.textureFiltering = .trilinear
                default: gs.textureFiltering = .anisotropicX16
                }
            }
        }

        if let v = readSetting(content: content, key: "specular") {
            gs.specular = v == "1"
        }
        if let v = readSetting(content: content, key: "projectedTextures") {
            gs.projectedTextures = v == "1"
        }
        if let v = readSetting(content: content, key: "farclip"),
           let d = Double(v) {
            gs.viewDistance = Int(d)
        }

        // Ground effects — map raw density value back to 0–3 scale
        let densityKey = version.wowVersion == "1.12.1" ? "frillDensity" : "groundEffectDensity"
        if let v = readSetting(content: content, key: densityKey), let n = Int(v) {
            switch n {
            case 0:        gs.groundEffectDensity = 0
            case 1..<32:   gs.groundEffectDensity = 1
            case 32..<48:  gs.groundEffectDensity = 2
            default:       gs.groundEffectDensity = 3
            }
        }

        if let v = readSetting(content: content, key: "weatherDensity"), let n = Int(v) {
            gs.weatherDensity = n
        }
        if let v = readSetting(content: content, key: "particleDensity"), let d = Double(v) {
            gs.particleDensity = d
        }

        // Shadows
        if let v = readSetting(content: content, key: "shadowLevel") ?? readSetting(content: content, key: "shadowlod") {
            switch v {
            case "0": gs.shadowQuality = .off
            case "1": gs.shadowQuality = .low
            default:  gs.shadowQuality = .high
            }
        }

        return gs
    }

    // MARK: - Version-specific helpers

    private static func applyTextureFiltering(
        version: GameVersion,
        filtering: TextureFiltering,
        set: (String, String) -> Void
    ) {
        if version.wowVersion == "1.12.1" {
            switch filtering {
            case .bilinear:
                set("trilinear", "0")
                set("anisotropic", "1")
            case .trilinear:
                set("trilinear", "1")
                set("anisotropic", "1")
            case .anisotropicX16:
                set("trilinear", "1")
                set("anisotropic", "16")
            }
        } else {
            switch filtering {
            case .bilinear:       set("textureFilteringMode", "0")
            case .trilinear:      set("textureFilteringMode", "1")
            case .anisotropicX16: set("textureFilteringMode", "5")
            }
        }
    }

    private static func applyGroundEffect(
        version: GameVersion,
        density: Int,
        set: (String, String) -> Void,
        remove: (String) -> Void
    ) {
        let densityKey = version.wowVersion == "1.12.1" ? "frillDensity" : "groundEffectDensity"
        let distKey = "groundEffectDist"

        switch density {
        case 0:
            set(densityKey, "0")
            set(distKey, "0")
        case 1:
            set(densityKey, "16")
            set(distKey, "70")
        case 2:
            set(densityKey, "32")
            set(distKey, "100")
        default:
            set(densityKey, "64")
            set(distKey, "140")
        }
    }

    private static func applyShadowSettings(
        version: GameVersion,
        quality: ShadowQuality,
        set: (String, String) -> Void,
        remove: (String) -> Void
    ) {
        // 1.12.1 uses shadowlod; TBC/WotLK uses shadowLevel
        let key = version.wowVersion == "1.12.1" ? "shadowlod" : "shadowLevel"
        switch quality {
        case .off:
            set(key, "0")
        case .low:
            set(key, "1")
        case .high:
            set(key, "2")
        }
    }

    // MARK: - File helpers

    private static func configFileURL(for version: GameVersion) throws -> URL {
        let trimmed = version.gamePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ConfigServiceError.gamePathMissing }

        let wtfDir = URL(fileURLWithPath: trimmed, isDirectory: true).appendingPathComponent("WTF", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: wtfDir, withIntermediateDirectories: true)
        } catch {
            throw ConfigServiceError.unableToCreateDirectories(error.localizedDescription)
        }

        return wtfDir.appendingPathComponent("Config.wtf", isDirectory: false)
    }

    private static func updateOrInsertSetting(content: String, key: String, value: String) -> String {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = "(?i)SET\\s+\(escapedKey)\\s+\"[^\"]*\""
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let replacement = "SET \(key) \"\(value)\""

        if let regex = regex,
           regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)) != nil {
            return regex.stringByReplacingMatches(
                in: content, options: [],
                range: NSRange(content.startIndex..., in: content),
                withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
            )
        }

        var newContent = content
        if !newContent.isEmpty && !newContent.hasSuffix("\n") { newContent += "\n" }
        newContent += replacement + "\n"
        return newContent
    }

    private static func removeSetting(content: String, key: String) -> String {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = "(?i)SET\\s+\(escapedKey)\\s+\"[^\"]*\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return content }
        let result = regex.stringByReplacingMatches(
            in: content, options: [],
            range: NSRange(content.startIndex..., in: content),
            withTemplate: ""
        )
        return result.replacingOccurrences(of: "\n\n", with: "\n")
    }

    private static func readSetting(content: String, key: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = "SET\\s+\(escapedKey)\\s+\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: content) else { return nil }
        return String(content[valueRange])
    }
}
