import Foundation

enum MigrationService {
    static let legacyDirectoryName = "TurtleSilicon"
    static let currentDirectoryName = "WoWSilicon"

    static func legacyDirectoryExists() -> Bool {
        guard let support = applicationSupportURL() else { return false }
        let legacy = support.appendingPathComponent(legacyDirectoryName, isDirectory: true)
        return FileManager.default.fileExists(atPath: legacy.path)
    }

    static func migrate() throws {
        guard let support = applicationSupportURL() else {
            throw MigrationError.unableToLocateSupportDirectory
        }
        let fm = FileManager.default
        let legacy = support.appendingPathComponent(legacyDirectoryName, isDirectory: true)
        let current = support.appendingPathComponent(currentDirectoryName, isDirectory: true)

        guard fm.fileExists(atPath: legacy.path) else { return }

        if fm.fileExists(atPath: current.path) {
            let contents = try fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)
            for item in contents {
                let dest = current.appendingPathComponent(item.lastPathComponent)
                if !fm.fileExists(atPath: dest.path) {
                    try fm.moveItem(at: item, to: dest)
                }
            }
            try fm.removeItem(at: legacy)
        } else {
            try fm.moveItem(at: legacy, to: current)
        }
    }

    private static func applicationSupportURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }
}

enum MigrationError: Error {
    case unableToLocateSupportDirectory
}
