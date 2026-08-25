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
        customVariables: String = "",
        winePrefixURL: URL = WineBottleService.currentBottleURL(),
        resourceURL: URL? = Bundle.main.resourceURL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var result = environment
        result.merge(parseEnvironmentVariables(customVariables)) { _, custom in custom }
        result = BundledX87Runtime.removingWineEnvironmentKeys(from: result)
        result["WINEPREFIX"] = winePrefixURL.path
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

    static func parseEnvironmentVariables(_ rawValue: String) -> [String: String] {
        let normalized = rawValue.replacingOccurrences(of: ";", with: "\n")
        var result: [String: String] = [:]

        for rawLine in normalized.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"),
                  let separator = line.firstIndex(of: "=") else {
                continue
            }

            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard isValidEnvironmentKey(key) else { continue }
            result[key] = value
        }

        return result
    }

    static func shellEnvironmentAssignments(_ rawValue: String) -> String {
        var variables = BundledX87Runtime.removingWineEnvironmentKeys(
            from: parseEnvironmentVariables(rawValue)
        )
        variables.removeValue(forKey: "WINEPREFIX")
        return variables.sorted { $0.key < $1.key }
            .map { "\($0.key)=\(shellQuote($0.value))" }
            .joined(separator: " ")
    }

    static func shellEnvironmentAssignment(key: String, value: String) -> String {
        "\(key)=\(shellQuote(value))"
    }

    private static func isValidEnvironmentKey(_ key: String) -> Bool {
        guard let first = key.utf8.first,
              first == 95 || (65...90).contains(first) || (97...122).contains(first) else {
            return false
        }
        return key.utf8.dropFirst().allSatisfy {
            $0 == 95 || (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
