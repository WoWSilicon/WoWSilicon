import Foundation

// MARK: - Graphics settings

enum WindowMode: String, Codable, CaseIterable, Sendable {
    case windowed
    case fullscreen

    var displayName: String {
        switch self {
        case .windowed: return "Windowed"
        case .fullscreen: return "Fullscreen"
        }
    }
}

enum Multisampling: String, Codable, CaseIterable, Sendable {
    case off
    case x2
    case x4
    case x8

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .x2: return "2x"
        case .x4: return "4x"
        case .x8: return "8x"
        }
    }

    var configValue: Int? {
        switch self {
        case .off: return nil
        case .x2: return 2
        case .x4: return 4
        case .x8: return 8
        }
    }
}

enum TextureFiltering: String, Codable, CaseIterable, Sendable {
    case bilinear
    case trilinear
    case anisotropicX16

    var displayName: String {
        switch self {
        case .bilinear: return "Bilinear"
        case .trilinear: return "Trilinear"
        case .anisotropicX16: return "Anisotropic 16x"
        }
    }
}

enum ShadowQuality: String, Codable, CaseIterable, Sendable {
    case off
    case low
    case high

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .high: return "High"
        }
    }
}

struct GraphicsSettings: Codable, Equatable, Sendable {
    var windowMode: WindowMode
    var resolution: String
    var refreshRate: Int
    var vsync: Bool
    var multisampling: Multisampling
    var textureFiltering: TextureFiltering
    var specular: Bool
    var projectedTextures: Bool
    var viewDistance: Int
    var groundEffectDensity: Int
    var weatherDensity: Int
    var particleDensity: Double
    var shadowQuality: ShadowQuality

    static let `default` = GraphicsSettings(
        windowMode: .windowed,
        resolution: "",
        refreshRate: 60,
        vsync: false,
        multisampling: .x2,
        textureFiltering: .anisotropicX16,
        specular: true,
        projectedTextures: true,
        viewDistance: 777,
        groundEffectDensity: 3,
        weatherDensity: 3,
        particleDensity: 1.0,
        shadowQuality: .off
    )

    static let commonResolutions = [
        "1280x720", "1280x800", "1440x900", "1600x900", "1680x1050",
        "1920x1080", "1920x1200", "2560x1440", "2560x1600", "3840x2160"
    ]

    static let commonRefreshRates = [30, 60, 120, 144, 165, 240]

    enum CodingKeys: String, CodingKey {
        case windowMode, resolution, refreshRate, vsync, multisampling
        case textureFiltering, specular, projectedTextures
        case viewDistance, groundEffectDensity, weatherDensity, particleDensity, shadowQuality
    }

    init(
        windowMode: WindowMode = .windowed,
        resolution: String = "",
        refreshRate: Int = 60,
        vsync: Bool = false,
        multisampling: Multisampling = .x2,
        textureFiltering: TextureFiltering = .anisotropicX16,
        specular: Bool = true,
        projectedTextures: Bool = true,
        viewDistance: Int = 777,
        groundEffectDensity: Int = 3,
        weatherDensity: Int = 3,
        particleDensity: Double = 1.0,
        shadowQuality: ShadowQuality = .off
    ) {
        self.windowMode = windowMode
        self.resolution = resolution
        self.refreshRate = refreshRate
        self.vsync = vsync
        self.multisampling = multisampling
        self.textureFiltering = textureFiltering
        self.specular = specular
        self.projectedTextures = projectedTextures
        self.viewDistance = viewDistance
        self.groundEffectDensity = groundEffectDensity
        self.weatherDensity = weatherDensity
        self.particleDensity = particleDensity
        self.shadowQuality = shadowQuality
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        windowMode = try c.decodeIfPresent(WindowMode.self, forKey: .windowMode) ?? .windowed
        resolution = try c.decodeIfPresent(String.self, forKey: .resolution) ?? ""
        refreshRate = try c.decodeIfPresent(Int.self, forKey: .refreshRate) ?? 60
        vsync = try c.decodeIfPresent(Bool.self, forKey: .vsync) ?? false
        multisampling = try c.decodeIfPresent(Multisampling.self, forKey: .multisampling) ?? .x2
        textureFiltering = try c.decodeIfPresent(TextureFiltering.self, forKey: .textureFiltering) ?? .anisotropicX16
        specular = try c.decodeIfPresent(Bool.self, forKey: .specular) ?? true
        projectedTextures = try c.decodeIfPresent(Bool.self, forKey: .projectedTextures) ?? true
        viewDistance = try c.decodeIfPresent(Int.self, forKey: .viewDistance) ?? 777
        // Migrate from old enum string ("off"/"low"/"medium"/"high") to Int (0–3)
        if let intVal = try? c.decodeIfPresent(Int.self, forKey: .groundEffectDensity) {
            groundEffectDensity = intVal
        } else if let strVal = try? c.decodeIfPresent(String.self, forKey: .groundEffectDensity) {
            switch strVal {
            case "off":    groundEffectDensity = 0
            case "low":    groundEffectDensity = 1
            case "medium": groundEffectDensity = 2
            default:       groundEffectDensity = 3
            }
        } else {
            groundEffectDensity = 3
        }
        weatherDensity = try c.decodeIfPresent(Int.self, forKey: .weatherDensity) ?? 3
        particleDensity = try c.decodeIfPresent(Double.self, forKey: .particleDensity) ?? 1.0
        shadowQuality = try c.decodeIfPresent(ShadowQuality.self, forKey: .shadowQuality) ?? .off
    }
}

// MARK: - Version settings

struct VersionSettings: Codable, Equatable, Sendable {
    var enableVanillaTweaks: Bool
    var remapOptionAsAlt: Bool
    var autoDeleteWdb: Bool
    var enableMetalHud: Bool
    var showTerminalNormally: Bool
    var environmentVariables: String
    var vanillaTweaksParameters: String
    var cursorSizeMultiplier: Int
    var graphicsSettings: GraphicsSettings
    var enableLibSiliconPatch: Bool
    var userDisabledLibSiliconPatch: Bool
    var useSystemProxy: Bool
    var noProxyList: String

    init(
        enableVanillaTweaks: Bool = false,
        remapOptionAsAlt: Bool = false,
        autoDeleteWdb: Bool = true,
        enableMetalHud: Bool = false,
        showTerminalNormally: Bool = false,
        environmentVariables: String = "",
        vanillaTweaksParameters: String = "",
        cursorSizeMultiplier: Int = 1,
        graphicsSettings: GraphicsSettings = GraphicsSettings(),
        enableLibSiliconPatch: Bool = false,
        userDisabledLibSiliconPatch: Bool = false,
        useSystemProxy: Bool = true,
        noProxyList: String = ""
    ) {
        self.enableVanillaTweaks = enableVanillaTweaks
        self.remapOptionAsAlt = remapOptionAsAlt
        self.autoDeleteWdb = autoDeleteWdb
        self.enableMetalHud = enableMetalHud
        self.showTerminalNormally = showTerminalNormally
        self.environmentVariables = environmentVariables
        self.vanillaTweaksParameters = vanillaTweaksParameters
        self.cursorSizeMultiplier = cursorSizeMultiplier
        self.graphicsSettings = graphicsSettings
        self.enableLibSiliconPatch = enableLibSiliconPatch
        self.userDisabledLibSiliconPatch = userDisabledLibSiliconPatch
        self.useSystemProxy = useSystemProxy
        self.noProxyList = noProxyList
    }

    enum CodingKeys: String, CodingKey {
        case enableVanillaTweaks, remapOptionAsAlt, autoDeleteWdb, enableMetalHud
        case showTerminalNormally, environmentVariables
        case vanillaTweaksParameters, cursorSizeMultiplier
        case graphicsSettings
        case enableLibSiliconPatch, userDisabledLibSiliconPatch
        case useSystemProxy
        case noProxyList
        // Legacy keys kept for migration only
        case reduceTerrainDistance, setMultisampleTo2x, setShadowLOD0, userDisabledShadowLOD
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enableVanillaTweaks = try container.decodeIfPresent(Bool.self, forKey: .enableVanillaTweaks) ?? false
        remapOptionAsAlt = try container.decodeIfPresent(Bool.self, forKey: .remapOptionAsAlt) ?? false
        autoDeleteWdb = try container.decodeIfPresent(Bool.self, forKey: .autoDeleteWdb) ?? true
        enableMetalHud = try container.decodeIfPresent(Bool.self, forKey: .enableMetalHud) ?? false
        showTerminalNormally = try container.decodeIfPresent(Bool.self, forKey: .showTerminalNormally) ?? false
        environmentVariables = try container.decodeIfPresent(String.self, forKey: .environmentVariables) ?? ""
        vanillaTweaksParameters = try container.decodeIfPresent(String.self, forKey: .vanillaTweaksParameters) ?? ""
        cursorSizeMultiplier = try container.decodeIfPresent(Int.self, forKey: .cursorSizeMultiplier) ?? 1
        enableLibSiliconPatch = try container.decodeIfPresent(Bool.self, forKey: .enableLibSiliconPatch) ?? false
        userDisabledLibSiliconPatch = try container.decodeIfPresent(Bool.self, forKey: .userDisabledLibSiliconPatch) ?? false
        useSystemProxy = try container.decodeIfPresent(Bool.self, forKey: .useSystemProxy) ?? true
        noProxyList = try container.decodeIfPresent(String.self, forKey: .noProxyList) ?? ""

        if let gs = try container.decodeIfPresent(GraphicsSettings.self, forKey: .graphicsSettings) {
            graphicsSettings = gs
        } else {
            // Migrate from legacy bool fields
            var gs = GraphicsSettings()
            if let reduceTerrain = try container.decodeIfPresent(Bool.self, forKey: .reduceTerrainDistance), reduceTerrain {
                gs.viewDistance = 177
            }
            if let multisample = try container.decodeIfPresent(Bool.self, forKey: .setMultisampleTo2x), multisample {
                gs.multisampling = .x2
            }
            if let shadowLOD = try container.decodeIfPresent(Bool.self, forKey: .setShadowLOD0), shadowLOD {
                gs.shadowQuality = .off
            }
            graphicsSettings = gs
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enableVanillaTweaks, forKey: .enableVanillaTweaks)
        try container.encode(remapOptionAsAlt, forKey: .remapOptionAsAlt)
        try container.encode(autoDeleteWdb, forKey: .autoDeleteWdb)
        try container.encode(enableMetalHud, forKey: .enableMetalHud)
        try container.encode(showTerminalNormally, forKey: .showTerminalNormally)
        try container.encode(environmentVariables, forKey: .environmentVariables)
        try container.encode(vanillaTweaksParameters, forKey: .vanillaTweaksParameters)
        try container.encode(cursorSizeMultiplier, forKey: .cursorSizeMultiplier)
        try container.encode(graphicsSettings, forKey: .graphicsSettings)
        try container.encode(enableLibSiliconPatch, forKey: .enableLibSiliconPatch)
        try container.encode(userDisabledLibSiliconPatch, forKey: .userDisabledLibSiliconPatch)
        try container.encode(useSystemProxy, forKey: .useSystemProxy)
        try container.encode(noProxyList, forKey: .noProxyList)
    }

    func mergedWithDefaults(_ defaults: VersionSettings) -> VersionSettings {
        var merged = self
        if defaults.enableLibSiliconPatch && !merged.userDisabledLibSiliconPatch {
            merged.enableLibSiliconPatch = true
        }
        return merged
    }
}

enum OptimizationLevel: String, Codable, Sendable {
    case low
    case mid
    case high
}

struct GameVersion: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var displayName: String
    var wowVersion: String
    var gamePath: String
    var crossOverPath: String
    var executableName: String
    var supportsVanillaTweaks: Bool
    var supportsDLLLoading: Bool
    var usesRosettaPatching: Bool
    var usesDivxDecoderPatch: Bool
    var optimizationLevel: OptimizationLevel
    var settings: VersionSettings
    var launcherExePath: String
    var wantsLauncher: Bool

    var hasLauncher: Bool { !launcherExePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var libSiliconPatchSubdirectory: String? {
        switch wowVersion {
        case "1.12.1": return "Patching/libSiliconPatch/vanilla"
        case "3.3.5a": return "Patching/libSiliconPatch/wotlk"
        default: return nil
        }
    }

    init(
        id: String,
        displayName: String,
        wowVersion: String,
        gamePath: String = "",
        crossOverPath: String = "",
        executableName: String,
        supportsVanillaTweaks: Bool,
        supportsDLLLoading: Bool,
        usesRosettaPatching: Bool,
        usesDivxDecoderPatch: Bool,
        optimizationLevel: OptimizationLevel = .low,
        settings: VersionSettings = VersionSettings(),
        launcherExePath: String = "",
        wantsLauncher: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.wowVersion = wowVersion
        self.gamePath = gamePath
        self.crossOverPath = crossOverPath
        self.executableName = executableName
        self.supportsVanillaTweaks = supportsVanillaTweaks
        self.supportsDLLLoading = supportsDLLLoading
        self.usesRosettaPatching = usesRosettaPatching
        self.usesDivxDecoderPatch = usesDivxDecoderPatch
        self.optimizationLevel = optimizationLevel
        self.settings = settings
        self.launcherExePath = launcherExePath
        self.wantsLauncher = wantsLauncher
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case wowVersion = "wow_version"
        case gamePath = "game_path"
        case crossOverPath = "crossover_path"
        case executableName
        case supportsVanillaTweaks = "supports_vanilla_tweaks"
        case supportsDLLLoading = "supports_dll_loading"
        case usesRosettaPatching = "uses_rosetta_patching"
        case usesDivxDecoderPatch = "uses_divx_decoder_patch"
        case optimizationLevel = "optimization_level"
        case settings
        case launcherExePath = "launcher_exe_path"
        case wantsLauncher = "wants_launcher"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        wowVersion = try container.decode(String.self, forKey: .wowVersion)
        gamePath = try container.decodeIfPresent(String.self, forKey: .gamePath) ?? ""
        crossOverPath = try container.decodeIfPresent(String.self, forKey: .crossOverPath) ?? ""
        executableName = try container.decodeIfPresent(String.self, forKey: .executableName) ?? "WoW.exe"
        supportsVanillaTweaks = try container.decodeIfPresent(Bool.self, forKey: .supportsVanillaTweaks) ?? false
        supportsDLLLoading = try container.decodeIfPresent(Bool.self, forKey: .supportsDLLLoading) ?? false
        usesRosettaPatching = try container.decodeIfPresent(Bool.self, forKey: .usesRosettaPatching) ?? false
        usesDivxDecoderPatch = try container.decodeIfPresent(Bool.self, forKey: .usesDivxDecoderPatch) ?? false
        optimizationLevel = try container.decodeIfPresent(OptimizationLevel.self, forKey: .optimizationLevel) ?? .low
        settings = try container.decodeIfPresent(VersionSettings.self, forKey: .settings) ?? VersionSettings()
        launcherExePath = try container.decodeIfPresent(String.self, forKey: .launcherExePath) ?? ""
        wantsLauncher = try container.decodeIfPresent(Bool.self, forKey: .wantsLauncher) ?? false
    }

    mutating func syncCapabilities(with defaults: GameVersion) {
        executableName = defaults.executableName
        supportsVanillaTweaks = defaults.supportsVanillaTweaks
        supportsDLLLoading = defaults.supportsDLLLoading
        usesRosettaPatching = defaults.usesRosettaPatching
        usesDivxDecoderPatch = defaults.usesDivxDecoderPatch
        optimizationLevel = defaults.optimizationLevel

        if !supportsVanillaTweaks {
            settings.enableVanillaTweaks = false
        }
    }
}

struct VersionManager: Codable, Sendable {
    var currentVersionID: String
    var versions: [String: GameVersion]

    static let defaultCurrentVersionID = "vanillasilicon"
    static let defaultOrder = [
        "vanillasilicon",
        "burningsilicon",
        "wrathsilicon"
    ]

    static let defaultVersions: [String: GameVersion] = [
        "vanillasilicon": GameVersion(
            id: "vanillasilicon",
            displayName: "VanillaSilicon (1.12.1)",
            wowVersion: "1.12.1",
            executableName: "WoW.exe",
            supportsVanillaTweaks: true,
            supportsDLLLoading: true,
            usesRosettaPatching: true,
            usesDivxDecoderPatch: false,
            optimizationLevel: .high,
            settings: VersionSettings(autoDeleteWdb: true, enableLibSiliconPatch: true)
        ),
        "burningsilicon": GameVersion(
            id: "burningsilicon",
            displayName: "BurningSilicon (2.4.3)",
            wowVersion: "2.4.3",
            executableName: "WoW.exe",
            supportsVanillaTweaks: false,
            supportsDLLLoading: true,
            usesRosettaPatching: true,
            usesDivxDecoderPatch: false,
            optimizationLevel: .mid,
            settings: VersionSettings(autoDeleteWdb: true)
        ),
        "wrathsilicon": GameVersion(
            id: "wrathsilicon",
            displayName: "WrathSilicon (3.3.5a)",
            wowVersion: "3.3.5a",
            executableName: "WoW.exe",
            supportsVanillaTweaks: false,
            supportsDLLLoading: true,
            usesRosettaPatching: true,
            usesDivxDecoderPatch: false,
            optimizationLevel: .high,
            settings: VersionSettings(autoDeleteWdb: true, enableLibSiliconPatch: true)
        )
    ]

    static func makeDefault() -> VersionManager {
        VersionManager(
            currentVersionID: defaultCurrentVersionID,
            versions: defaultVersions
        )
    }

    var currentVersion: GameVersion? {
        versions[currentVersionID]
    }

    mutating func ensureDefaults() {
        for (id, defaultVersion) in VersionManager.defaultVersions {
            if var existing = versions[id] {
                existing.syncCapabilities(with: defaultVersion)
                existing.settings = existing.settings.mergedWithDefaults(defaultVersion.settings)
                versions[id] = existing
            } else {
                versions[id] = defaultVersion
            }
        }

        versions.removeValue(forKey: "epochsilicon")
        versions.removeValue(forKey: "turtlesilicon")

        if versions[currentVersionID] == nil {
            currentVersionID = VersionManager.defaultCurrentVersionID
        }
    }

    func orderedVersions() -> [GameVersion] {
        var ordered: [GameVersion] = []
        var seen = Set<String>()

        for identifier in VersionManager.defaultOrder {
            if let version = versions[identifier] {
                ordered.append(version)
                seen.insert(identifier)
            }
        }

        for (key, value) in versions where !seen.contains(key) {
            ordered.append(value)
        }

        return ordered
    }

    mutating func updateCurrentVersion(_ update: (inout GameVersion) -> Void) {
        guard var version = versions[currentVersionID] else { return }
        update(&version)
        versions[currentVersionID] = version
    }

    mutating func setCurrentVersion(id: String) {
        guard versions[id] != nil else { return }
        currentVersionID = id
    }
}
