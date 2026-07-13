import Foundation

enum BundledRosettaRuntime {
    static let environmentOverride = "WOWSILICON_ROSETTA_X87_PATH"

    static func executableURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        let executableURL: URL?
        if let override = environment[environmentOverride]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            executableURL = URL(fileURLWithPath: override, isDirectory: false)
        } else {
            executableURL = PatchService.resourceURL(
                named: "rosettax87",
                extension: nil,
                subdirectory: "Patching/rosettax87"
            )
        }

        guard let executableURL,
              fileManager.isExecutableFile(atPath: executableURL.path) else {
            return nil
        }

        let runtimeURL = executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("libRuntimeRosettax87", isDirectory: false)
        guard fileManager.isExecutableFile(atPath: runtimeURL.path) else {
            return nil
        }
        return executableURL
    }
}
