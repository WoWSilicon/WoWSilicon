import Foundation

struct UserPrefs: Codable, Equatable {
    var remapOptionAsAlt: Bool
    var showTerminalNormally: Bool
    var enableMetalHud: Bool
    var enableVanillaTweaks: Bool
    var autoDeleteWdb: Bool
    var environmentVariables: String
    var vanillaTweaksParameters: String

    static let defaults = UserPrefs(
        remapOptionAsAlt: false,
        showTerminalNormally: false,
        enableMetalHud: false,
        enableVanillaTweaks: false,
        autoDeleteWdb: true,
        environmentVariables: "",
        vanillaTweaksParameters: ""
    )

    enum CodingKeys: String, CodingKey {
        case remapOptionAsAlt = "remap_option_as_alt"
        case showTerminalNormally = "show_terminal_normally"
        case enableMetalHud = "enable_metal_hud"
        case enableVanillaTweaks = "enable_vanilla_tweaks"
        case autoDeleteWdb = "auto_delete_wdb"
        case environmentVariables = "environment_variables"
        case vanillaTweaksParameters = "vanilla_tweaks_parameters"
    }

    init(
        remapOptionAsAlt: Bool = false,
        showTerminalNormally: Bool = false,
        enableMetalHud: Bool = false,
        enableVanillaTweaks: Bool = false,
        autoDeleteWdb: Bool = true,
        environmentVariables: String = "",
        vanillaTweaksParameters: String = ""
    ) {
        self.remapOptionAsAlt = remapOptionAsAlt
        self.showTerminalNormally = showTerminalNormally
        self.enableMetalHud = enableMetalHud
        self.enableVanillaTweaks = enableVanillaTweaks
        self.autoDeleteWdb = autoDeleteWdb
        self.environmentVariables = environmentVariables
        self.vanillaTweaksParameters = vanillaTweaksParameters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        remapOptionAsAlt = try container.decodeIfPresent(Bool.self, forKey: .remapOptionAsAlt) ?? false
        showTerminalNormally = try container.decodeIfPresent(Bool.self, forKey: .showTerminalNormally) ?? false
        enableMetalHud = try container.decodeIfPresent(Bool.self, forKey: .enableMetalHud) ?? false
        enableVanillaTweaks = try container.decodeIfPresent(Bool.self, forKey: .enableVanillaTweaks) ?? false
        autoDeleteWdb = try container.decodeIfPresent(Bool.self, forKey: .autoDeleteWdb) ?? true
        environmentVariables = try container.decodeIfPresent(String.self, forKey: .environmentVariables) ?? ""
        vanillaTweaksParameters = try container.decodeIfPresent(String.self, forKey: .vanillaTweaksParameters) ?? ""
    }
}
