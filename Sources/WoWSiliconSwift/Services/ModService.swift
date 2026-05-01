import Foundation

struct ModInfo: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let path: String
    let enabled: Bool
    let required: Bool
    let size: Int64
    let lastModified: Date
    let description: String

    init(
        id: String,
        name: String,
        path: String,
        enabled: Bool,
        required: Bool,
        size: Int64,
        lastModified: Date,
        description: String
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.enabled = enabled
        self.required = required
        self.size = size
        self.lastModified = lastModified
        self.description = description
    }

    static func == (lhs: ModInfo, rhs: ModInfo) -> Bool {
        lhs.id == rhs.id
    }
}

enum ModServiceError: LocalizedError {
    case gamePathMissing
    case modsNotSupported
    case modsDirectoryMissing(String)
    case writeFailed(String)
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .gamePathMissing:
            return "Game path is not set. Configure it before managing mods."
        case .modsNotSupported:
            return "Mods are not supported for this version."
        case .modsDirectoryMissing(let path):
            return "Mods directory not found: \(path)"
        case .writeFailed(let reason):
            return reason
        case .deleteFailed(let reason):
            return reason
        }
    }
}

enum ModService {
    private static func getRequiredMods(for version: GameVersion) -> Set<String> {
        let mods: Set<String> = ["winerosetta.dll"]
        return mods
    }

    static func scanMods(version: GameVersion, supportsDLL: Bool) throws -> [ModInfo] {
        guard supportsDLL else { throw ModServiceError.modsNotSupported }
        guard !version.gamePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModServiceError.gamePathMissing
        }

        let modsURL = URL(fileURLWithPath: version.gamePath, isDirectory: true).appendingPathComponent("mods", isDirectory: true)
        try FileManager.default.createDirectory(at: modsURL, withIntermediateDirectories: true)

        let requiredMods = getRequiredMods(for: version)
        let enabledMods = enabledModSet(gamePath: version.gamePath, requiredMods: requiredMods)
        let entries = try FileManager.default.contentsOfDirectory(at: modsURL, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey], options: .skipsHiddenFiles)

        var mods: [ModInfo] = []
        for entry in entries {
            let values = try entry.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            guard entry.pathExtension.lowercased() == "dll" else { continue }

            let name = entry.lastPathComponent
            let required = requiredMods.contains(name.lowercased())
            let enabled = enabledMods.contains("mods/" + name)
            let description = descriptionForMod(name)
            let mod = ModInfo(
                id: entry.path,
                name: name,
                path: entry.path,
                enabled: enabled || required,
                required: required,
                size: Int64(values.fileSize ?? 0),
                lastModified: values.contentModificationDate ?? Date.distantPast,
                description: description
            )
            mods.append(mod)
        }

        return mods.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    static func setMod(_ mod: ModInfo, enabled: Bool, version: GameVersion) throws -> ModInfo {
        guard !mod.required else { return mod }
        guard !version.gamePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModServiceError.gamePathMissing
        }

        let requiredMods = getRequiredMods(for: version)
        var enabledMods = enabledModSet(gamePath: version.gamePath, requiredMods: requiredMods)

        if enabled {
            enabledMods.insert("mods/" + mod.name)
        } else {
            enabledMods.remove("mods/" + mod.name)
        }

        try writeDllsFile(enabledMods: enabledMods, gamePath: version.gamePath)

        return ModInfo(
            id: mod.id,
            name: mod.name,
            path: mod.path,
            enabled: enabled,
            required: mod.required,
            size: mod.size,
            lastModified: mod.lastModified,
            description: mod.description
        )
    }

    static func delete(mod: ModInfo, version: GameVersion) throws {
        guard !mod.required else { return }
        do {
            try FileManager.default.removeItem(atPath: mod.path)
        } catch {
            throw ModServiceError.deleteFailed(error.localizedDescription)
        }

        let requiredMods = getRequiredMods(for: version)
        var enabledMods = enabledModSet(gamePath: version.gamePath, requiredMods: requiredMods)
        enabledMods.remove("mods/" + mod.name)
        try writeDllsFile(enabledMods: enabledMods, gamePath: version.gamePath)
    }

    // MARK: - Helpers

    private static func enabledModSet(gamePath: String, requiredMods: Set<String>) -> Set<String> {
        let dllsURL = URL(fileURLWithPath: gamePath, isDirectory: true).appendingPathComponent("dlls.txt")
        guard let content = try? String(contentsOf: dllsURL) else {
            return Set(requiredMods.map { "mods/" + $0 })
        }
        var set = Set(requiredMods.map { "mods/" + $0 })
        for line in content.split(whereSeparator: { $0.isNewline }) {
            set.insert(line.trimmingCharacters(in: .whitespaces))
        }
        return set
    }

    private static func writeDllsFile(enabledMods: Set<String>, gamePath: String) throws {
        let dllsURL = URL(fileURLWithPath: gamePath, isDirectory: true).appendingPathComponent("dlls.txt")
        let lines = enabledMods.sorted()
        do {
            try lines.joined(separator: "\n").appending("\n").write(to: dllsURL, atomically: true, encoding: .utf8)
        } catch {
            throw ModServiceError.writeFailed(error.localizedDescription)
        }
    }

    private static func descriptionForMod(_ name: String) -> String {
        switch name.lowercased() {
        case "libsiliconpatch.dll":
            return "Replaces X87 instructions with SSE2 instructions for significant FPS gains."
        case "winerosetta.dll":
            return "Required Wine shim that enables WoW to run under Rosetta on Apple Silicon."
        case "d3d9.dll":
            return "Direct3D 9 wrapper providing compatibility and performance improvements."
        case "libdllldr.dll":
            return "Enables Mod support for WOTLK 3.3.5a."
        default:
            return "No description available."
        }
    }
}
