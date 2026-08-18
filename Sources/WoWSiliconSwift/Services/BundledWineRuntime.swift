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

    static func externalLibraryDirectoryURL(
        resourceURL: URL? = Bundle.main.resourceURL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        rootURL(resourceURL: resourceURL, environment: environment)?
            .appendingPathComponent("lib", isDirectory: true)
            .appendingPathComponent("external", isDirectory: true)
    }

    static func makeEnvironment(
        resourceURL: URL? = Bundle.main.resourceURL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var result = BundledX87Runtime.removingWineEnvironmentKeys(from: environment)
        guard let externalURL = externalLibraryDirectoryURL(
            resourceURL: resourceURL,
            environment: environment
        ) else {
            return result
        }

        let existing = environment["DYLD_LIBRARY_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing, !existing.isEmpty {
            result["DYLD_LIBRARY_PATH"] = "\(externalURL.path):\(existing)"
        } else {
            result["DYLD_LIBRARY_PATH"] = externalURL.path
        }
        return result
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
