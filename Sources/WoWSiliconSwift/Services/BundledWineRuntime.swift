import Foundation

enum BundledWineRuntime {
    static let environmentOverride = "WOWSILICON_WINE_RUNTIME"

    static func rootURL(
        resourceURL: URL? = Bundle.main.resourceURL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let override = environment[environmentOverride]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return resourceURL?.appendingPathComponent("Wine", isDirectory: true)
    }

    static func wineExecutableURL(
        resourceURL: URL? = Bundle.main.resourceURL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let rootURL = rootURL(resourceURL: resourceURL, environment: environment) else {
            return nil
        }
        let executableURL = rootURL
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("wine", isDirectory: false)
        return fileManager.isExecutableFile(atPath: executableURL.path) ? executableURL : nil
    }

    static func mtld3dConfigurationURL(
        resourceURL: URL? = Bundle.main.resourceURL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let rootURL = rootURL(resourceURL: resourceURL, environment: environment) else {
            return nil
        }
        let configurationURL = rootURL
            .appendingPathComponent("lib", isDirectory: true)
            .appendingPathComponent("mtld3d.conf", isDirectory: false)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: configurationURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }
        return configurationURL
    }
}
