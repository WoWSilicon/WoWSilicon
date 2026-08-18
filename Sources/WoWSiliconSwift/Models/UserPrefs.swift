import Foundation

struct UserPrefs: Codable, Equatable {
    var remapOptionAsAlt: Bool
    var showTerminalNormally: Bool
    var enableMetalHud: Bool
    var enableVanillaTweaks: Bool
    var autoDeleteWdb: Bool
    var telemetryEnabled: Bool
    var telemetryConsentAsked: Bool
    var telemetryInstallID: String
    var environmentVariables: String
    var vanillaTweaksParameters: String
    var x87Backend: X87Backend

    var enableRosettaX87: Bool {
        get { x87Backend != .disabled }
        set { x87Backend = newValue ? .rosettaX87 : .disabled }
    }

    static let defaults = UserPrefs(
        remapOptionAsAlt: false,
        showTerminalNormally: false,
        enableMetalHud: false,
        enableVanillaTweaks: false,
        autoDeleteWdb: true,
        telemetryEnabled: false,
        telemetryConsentAsked: false,
        telemetryInstallID: UUID().uuidString,
        environmentVariables: "",
        vanillaTweaksParameters: "",
        x87Backend: .rosettaX87
    )

    enum CodingKeys: String, CodingKey {
        case remapOptionAsAlt = "remap_option_as_alt"
        case showTerminalNormally = "show_terminal_normally"
        case enableMetalHud = "enable_metal_hud"
        case enableVanillaTweaks = "enable_vanilla_tweaks"
        case autoDeleteWdb = "auto_delete_wdb"
        case telemetryEnabled = "telemetry_enabled"
        case telemetryConsentAsked = "telemetry_consent_asked"
        case telemetryInstallID = "telemetry_install_id"
        case environmentVariables = "environment_variables"
        case vanillaTweaksParameters = "vanilla_tweaks_parameters"
        case x87Backend = "x87_backend"
        case enableRosettaX87 = "enable_rosetta_x87"
    }

    init(
        remapOptionAsAlt: Bool = false,
        showTerminalNormally: Bool = false,
        enableMetalHud: Bool = false,
        enableVanillaTweaks: Bool = false,
        autoDeleteWdb: Bool = true,
        telemetryEnabled: Bool = false,
        telemetryConsentAsked: Bool = false,
        telemetryInstallID: String = UUID().uuidString,
        environmentVariables: String = "",
        vanillaTweaksParameters: String = "",
        enableRosettaX87: Bool = true,
        x87Backend: X87Backend? = nil
    ) {
        self.remapOptionAsAlt = remapOptionAsAlt
        self.showTerminalNormally = showTerminalNormally
        self.enableMetalHud = enableMetalHud
        self.enableVanillaTweaks = enableVanillaTweaks
        self.autoDeleteWdb = autoDeleteWdb
        self.telemetryEnabled = telemetryEnabled
        self.telemetryConsentAsked = telemetryConsentAsked
        self.telemetryInstallID = telemetryInstallID
        self.environmentVariables = environmentVariables
        self.vanillaTweaksParameters = vanillaTweaksParameters
        self.x87Backend = x87Backend ?? (enableRosettaX87 ? .rosettaX87 : .disabled)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        remapOptionAsAlt = try container.decodeIfPresent(Bool.self, forKey: .remapOptionAsAlt) ?? false
        showTerminalNormally = try container.decodeIfPresent(Bool.self, forKey: .showTerminalNormally) ?? false
        enableMetalHud = try container.decodeIfPresent(Bool.self, forKey: .enableMetalHud) ?? false
        enableVanillaTweaks = try container.decodeIfPresent(Bool.self, forKey: .enableVanillaTweaks) ?? false
        autoDeleteWdb = try container.decodeIfPresent(Bool.self, forKey: .autoDeleteWdb) ?? true
        telemetryEnabled = try container.decodeIfPresent(Bool.self, forKey: .telemetryEnabled) ?? false
        telemetryConsentAsked = try container.decodeIfPresent(Bool.self, forKey: .telemetryConsentAsked) ?? false
        telemetryInstallID = try container.decodeIfPresent(String.self, forKey: .telemetryInstallID) ?? UUID().uuidString
        environmentVariables = try container.decodeIfPresent(String.self, forKey: .environmentVariables) ?? ""
        vanillaTweaksParameters = try container.decodeIfPresent(String.self, forKey: .vanillaTweaksParameters) ?? ""
        if let backend = try container.decodeIfPresent(X87Backend.self, forKey: .x87Backend) {
            x87Backend = backend
        } else {
            let enabled = try container.decodeIfPresent(Bool.self, forKey: .enableRosettaX87) ?? true
            x87Backend = enabled ? .rosettaX87 : .disabled
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(remapOptionAsAlt, forKey: .remapOptionAsAlt)
        try container.encode(showTerminalNormally, forKey: .showTerminalNormally)
        try container.encode(enableMetalHud, forKey: .enableMetalHud)
        try container.encode(enableVanillaTweaks, forKey: .enableVanillaTweaks)
        try container.encode(autoDeleteWdb, forKey: .autoDeleteWdb)
        try container.encode(telemetryEnabled, forKey: .telemetryEnabled)
        try container.encode(telemetryConsentAsked, forKey: .telemetryConsentAsked)
        try container.encode(telemetryInstallID, forKey: .telemetryInstallID)
        try container.encode(environmentVariables, forKey: .environmentVariables)
        try container.encode(vanillaTweaksParameters, forKey: .vanillaTweaksParameters)
        try container.encode(x87Backend, forKey: .x87Backend)
        try container.encode(enableRosettaX87, forKey: .enableRosettaX87)
    }
}
