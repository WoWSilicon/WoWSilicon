import Foundation

enum WineRegistrySupport {
    static let macDriverRegistryKey = #"HKEY_CURRENT_USER\Software\Wine\Mac Driver"#
    static let macDriverSection = "[Software\\Wine\\Mac Driver]"
    static let legacyMacDriverSection = "[Software\\\\Wine\\\\Mac Driver]"
    static let timestampLine = "#time=1dbd859c084de18"

    static func winePrefixURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".wine", isDirectory: true)
    }

    static func userRegURL() -> URL {
        winePrefixURL().appendingPathComponent("user.reg")
    }

    static func isMacDriverSection(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix(macDriverSection) || trimmed.hasPrefix(legacyMacDriverSection)
    }

    static func wineloaderPath(from crossOverPath: String?) -> String? {
        let resolvedPath = crossOverPath ?? "/Applications/CrossOver.app"
        let wineloader2Path = resolvedPath + "/Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wineloader2"
        guard FileManager.default.fileExists(atPath: wineloader2Path) else {
            return nil
        }
        return wineloader2Path
    }

    static func makeWineEnvironment(prefixURL: URL, wineExecutable: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = prefixURL.path
        environment["__COMPAT_LAYER"] = "RunAsInvoker"

        let wineDirectory = (wineExecutable as NSString).deletingLastPathComponent
        if var path = environment["PATH"] {
            let components = path.split(separator: ":").map(String.init)
            if !components.contains(wineDirectory) {
                path = "\(wineDirectory):\(path)"
                environment["PATH"] = path
            }
        } else {
            environment["PATH"] = wineDirectory
        }

        return environment
    }
}
