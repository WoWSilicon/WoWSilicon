import Foundation

enum BundledX87Runtime {
    struct ResolvedRuntime: Equatable, Sendable {
        let executableURL: URL
        let wineEnvironmentKey: String
    }

    static let rosettaEnvironmentOverride = "WOWSILICON_ROSETTA_X87_PATH"
    static let sidecarEnvironmentOverride = "WOWSILICON_X87_SIDECAR_PATH"

    static func resolve(
        _ backend: X87Backend,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> ResolvedRuntime? {
        guard backend != .disabled else { return nil }

        let overrideKey: String
        let resourceName: String
        let resourceSubdirectory: String
        let wineEnvironmentKey: String

        switch backend {
        case .disabled:
            return nil
        case .rosettaX87:
            overrideKey = rosettaEnvironmentOverride
            resourceName = "rosettax87"
            resourceSubdirectory = "Patching/rosettax87"
            wineEnvironmentKey = "ROSETTA_X87_PATH"
        case .x87Sidecar:
            overrideKey = sidecarEnvironmentOverride
            resourceName = "x87sidecar"
            resourceSubdirectory = "Patching/x87sidecar"
            wineEnvironmentKey = "X87_SIDECAR_PATH"
        }

        let executableURL: URL?
        if let override = environment[overrideKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            executableURL = URL(fileURLWithPath: override, isDirectory: false)
        } else {
            executableURL = PatchService.resourceURL(
                named: resourceName,
                extension: nil,
                subdirectory: resourceSubdirectory
            )
        }

        guard let executableURL,
              fileManager.isExecutableFile(atPath: executableURL.path) else {
            return nil
        }

        if backend == .rosettaX87 {
            let companionURL = executableURL
                .deletingLastPathComponent()
                .appendingPathComponent("libRuntimeRosettax87", isDirectory: false)
            guard fileManager.isExecutableFile(atPath: companionURL.path) else {
                return nil
            }
        }

        return ResolvedRuntime(
            executableURL: executableURL,
            wineEnvironmentKey: wineEnvironmentKey
        )
    }

    static func expectedBundlePath(for backend: X87Backend) -> String {
        switch backend {
        case .disabled:
            return ""
        case .rosettaX87:
            return "Contents/Resources/Patching/rosettax87/rosettax87"
        case .x87Sidecar:
            return "Contents/Resources/Patching/x87sidecar/x87sidecar"
        }
    }
}
