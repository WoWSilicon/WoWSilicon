import Foundation

enum WineBottleServiceError: LocalizedError {
    case unsafeLocation(String)
    case directoryNotEmpty(String)
    case destinationAlreadyExists(String)
    case legacyBottleMissing(String)

    var errorDescription: String? {
        switch self {
        case .unsafeLocation(let path):
            return "Choose a dedicated folder for the Wine bottle. \(path) is too broad to use safely."
        case .directoryNotEmpty(let path):
            return "The selected folder is not empty and does not appear to be a Wine bottle: \(path)"
        case .destinationAlreadyExists(let path):
            return "The new Wine bottle already exists at \(path)."
        case .legacyBottleMissing(let path):
            return "No Wine bottle was found at \(path)."
        }
    }
}

enum WineBottleService {
    static func defaultBottleURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("WoWSilicon", isDirectory: true)
    }

    static func legacyBottleURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory.appendingPathComponent(".wine", isDirectory: true)
    }

    static func currentBottleURL(
        prefs: UserPrefs = UserPrefsStore().load(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let path = prefs.wineBottlePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return defaultBottleURL(homeDirectory: homeDirectory) }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            .standardizedFileURL
    }

    static func isWineBottle(
        at url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        var driveCIsDirectory: ObjCBool = false
        let hasDriveC = fileManager.fileExists(
            atPath: url.appendingPathComponent("drive_c", isDirectory: true).path,
            isDirectory: &driveCIsDirectory
        ) && driveCIsDirectory.boolValue
        let hasRegistry = fileManager.fileExists(
            atPath: url.appendingPathComponent("system.reg", isDirectory: false).path
        )
        return hasDriveC && hasRegistry
    }

    static func shouldOfferLegacyMigration(
        prefs: UserPrefs,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Bool {
        guard !prefs.wineBottleMigrationAsked,
              prefs.wineBottlePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let legacy = legacyBottleURL(homeDirectory: homeDirectory)
        let destination = defaultBottleURL(homeDirectory: homeDirectory)
        return isWineBottle(at: legacy, fileManager: fileManager)
            && destinationIsAvailable(destination, fileManager: fileManager)
    }

    static func validateSelectedBottleURL(
        _ url: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws -> URL {
        let selected = url.standardizedFileURL
        let unsafeLocations = [
            URL(fileURLWithPath: "/", isDirectory: true).standardizedFileURL.path,
            homeDirectory.standardizedFileURL.path,
            homeDirectory.deletingLastPathComponent().standardizedFileURL.path,
            "/Applications", "/Library", "/System", "/Users", "/Volumes", "/private", "/tmp",
        ] + ["Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public"]
            .map { homeDirectory.appendingPathComponent($0, isDirectory: true).standardizedFileURL.path }
        guard !unsafeLocations.contains(selected.path) else {
            throw WineBottleServiceError.unsafeLocation(selected.path)
        }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: selected.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw WineBottleServiceError.unsafeLocation(selected.path)
            }
            let contents = try fileManager.contentsOfDirectory(atPath: selected.path)
            if !contents.isEmpty && !isWineBottle(at: selected, fileManager: fileManager) {
                throw WineBottleServiceError.directoryNotEmpty(selected.path)
            }
        }
        return selected
    }

    static func copyLegacyBottle(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws -> URL {
        let source = legacyBottleURL(homeDirectory: homeDirectory)
        let destination = defaultBottleURL(homeDirectory: homeDirectory)
        guard isWineBottle(at: source, fileManager: fileManager) else {
            throw WineBottleServiceError.legacyBottleMissing(source.path)
        }
        guard destinationIsAvailable(destination, fileManager: fileManager) else {
            throw WineBottleServiceError.destinationAlreadyExists(destination.path)
        }
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".WoWSilicon-migration-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporary) }
        try fileManager.copyItem(at: source, to: temporary)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporary, to: destination)
        return destination
    }

    private static func destinationIsAvailable(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return true }
        guard isDirectory.boolValue,
              let contents = try? fileManager.contentsOfDirectory(atPath: url.path) else {
            return false
        }
        return contents.isEmpty
    }
}
