import Foundation

struct VersionStore {
    struct LoadResult {
        var manager: VersionManager
        var warnings: [String]
        var decodeFailed: Bool = false
    }

    private let fileManager: FileManager
    private let supportDirectory: URL?
    private let directoryName = "WoWSilicon"
    private let fileName = "versions.json"

    init(fileManager: FileManager = .default, supportDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.supportDirectory = supportDirectory
    }

    func loadVersionManager() -> LoadResult {
        var warnings: [String] = []

        guard let versionsURL = versionsFileURL() else {
            warnings.append("Failed to resolve Application Support directory. Using defaults.")
            var fallback = VersionManager.makeDefault()
            fallback.ensureDefaults()
            return LoadResult(manager: fallback, warnings: warnings)
        }

        var manager: VersionManager
        var loadedFromNewStore = false
        var decodeFailed = false
        if fileManager.fileExists(atPath: versionsURL.path) {
            do {
                let data = try Data(contentsOf: versionsURL)
                manager = try JSONDecoder().decode(VersionManager.self, from: data)
                loadedFromNewStore = true
            } catch {
                warnings.append("Failed to load versions.json: \(error.localizedDescription)")
                manager = VersionManager.makeDefault()
                decodeFailed = true
            }
        } else {
            manager = VersionManager.makeDefault()
        }

        var mergedFromLegacy = false
        let needsLegacyMerge = !loadedFromNewStore || manager.versions.values.allSatisfy {
            $0.gamePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if needsLegacyMerge, let legacy = loadLegacyVersionManager() {
            let merged = merge(current: manager, legacy: legacy)
            manager = merged
            mergedFromLegacy = true
        }

        manager.ensureDefaults()

        if mergedFromLegacy {
            do {
                try save(manager: manager)
            } catch {
                warnings.append("Failed to persist merged preferences: \(error.localizedDescription)")
            }
        }

        return LoadResult(manager: manager, warnings: warnings, decodeFailed: decodeFailed)
    }

    func save(manager: VersionManager) throws {
        guard let fileURL = versionsFileURL() else {
            throw VersionStoreError.unableToLocateSupportDirectory
        }

        let directoryURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        var managerToSave = manager
        managerToSave.ensureDefaults()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(managerToSave)
        try data.write(to: fileURL, options: .atomic)
    }

    private func versionsFileURL() -> URL? {
        guard let supportDirectory = supportDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return supportDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private func legacyVersionsFileURL() -> URL? {
        guard let supportDirectory = supportDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return supportDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("version_manager.json", isDirectory: false)
    }

    private func loadLegacyVersionManager() -> VersionManager? {
        guard let legacyURL = legacyVersionsFileURL(),
              fileManager.fileExists(atPath: legacyURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: legacyURL)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            var legacyManager = VersionManager.makeDefault()

            if let currentID = root["current_version_id"] as? String,
               legacyManager.versions[currentID] != nil {
                legacyManager.currentVersionID = currentID
            }

            guard let legacyVersions = root["versions"] as? [String: Any] else {
                return legacyManager
            }

            for (id, payload) in legacyVersions {
                guard var version = legacyManager.versions[id] ?? VersionManager.defaultVersions[id],
                      let dict = payload as? [String: Any] else {
                    continue
                }

                if let rawGamePath = dict["game_path"] as? String {
                    let trimmed = rawGamePath.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        version.gamePath = trimmed
                    }
                }

                if let rawCrossOverPath = dict["crossover_path"] as? String {
                    let trimmed = rawCrossOverPath.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        version.crossOverPath = trimmed
                    }
                }

                if let settings = dict["settings"] as? [String: Any] {
                    if let value = settings["environment_variables"] as? String {
                        version.settings.environmentVariables = value
                    }
                    if let value = settings["vanilla_tweaks_parameters"] as? String {
                        version.settings.vanillaTweaksParameters = value
                    }
                    if let value = settings["enable_vanilla_tweaks"] as? Bool {
                        version.settings.enableVanillaTweaks = value
                    }
                    if let value = settings["remap_option_as_alt"] as? Bool {
                        version.settings.remapOptionAsAlt = value
                    }
                    if let value = settings["auto_delete_wdb"] as? Bool {
                        version.settings.autoDeleteWdb = value
                    }
                    if let value = settings["enable_metal_hud"] as? Bool {
                        version.settings.enableMetalHud = value
                    }
                    if let value = settings["show_terminal_normally"] as? Bool {
                        version.settings.showTerminalNormally = value
                    }
                    if let value = settings["enable_lib_silicon_patch"] as? Bool {
                        version.settings.enableLibSiliconPatch = value
                    }
                    if let value = settings["user_disabled_lib_silicon_patch"] as? Bool {
                        version.settings.userDisabledLibSiliconPatch = value
                    }
                    // Legacy graphics bool migration
                    var gs = version.settings.graphicsSettings
                    if let value = settings["reduce_terrain_distance"] as? Bool, value {
                        gs.viewDistance = 177
                    }
                    if let value = settings["set_multisample_to_2x"] as? Bool, value {
                        gs.multisampling = .x2
                    }
                    if let value = settings["set_shadow_lod_0"] as? Bool, value {
                        gs.shadowQuality = .off
                    }
                    version.settings.graphicsSettings = gs
                }

                legacyManager.versions[id] = version
            }

            return legacyManager
        } catch {
            debugPrint("Failed to parse legacy version_manager.json: \(error.localizedDescription)")
            return nil
        }
    }

    private func merge(current: VersionManager, legacy: VersionManager) -> VersionManager {
        var merged = current

        for (id, legacyVersion) in legacy.versions {
            guard var target = merged.versions[id] else {
                merged.versions[id] = legacyVersion
                continue
            }

            if target.gamePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !legacyVersion.gamePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                target.gamePath = legacyVersion.gamePath
            }

            if target.crossOverPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !legacyVersion.crossOverPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                target.crossOverPath = legacyVersion.crossOverPath
            }

            // Merge settings (legacy values take precedence if set)
            target.settings = mergeSettings(current: target.settings, legacy: legacyVersion.settings)

            merged.versions[id] = target
        }

        if let legacyCurrent = legacy.versions[legacy.currentVersionID] {
            let legacyHasPaths = !legacyCurrent.gamePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if legacyHasPaths {
                merged.currentVersionID = legacy.currentVersionID
            }
        }

        return merged
    }

    private func mergeSettings(current: VersionSettings, legacy: VersionSettings) -> VersionSettings {
        var merged = current

        if !legacy.environmentVariables.isEmpty {
            merged.environmentVariables = legacy.environmentVariables
        }
        let trimmedLegacyParameters = legacy.vanillaTweaksParameters.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLegacyParameters.isEmpty {
            merged.vanillaTweaksParameters = trimmedLegacyParameters
        }
        merged.enableVanillaTweaks = legacy.enableVanillaTweaks
        merged.autoDeleteWdb = true
        merged.enableMetalHud = legacy.enableMetalHud
        merged.showTerminalNormally = legacy.showTerminalNormally
        merged.remapOptionAsAlt = legacy.remapOptionAsAlt
        merged.graphicsSettings = legacy.graphicsSettings
        merged.enableLibSiliconPatch = legacy.enableLibSiliconPatch
        merged.userDisabledLibSiliconPatch = legacy.userDisabledLibSiliconPatch

        return merged
    }
}

enum VersionStoreError: Error {
    case unableToLocateSupportDirectory
}
