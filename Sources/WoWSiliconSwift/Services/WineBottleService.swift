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

    @discardableResult
    static func migrateExternalUserProfileIfNeeded(
        bottleURL: URL = currentBottleURL(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws -> Bool {
        try Task.checkCancellation()
        let usersURL = bottleURL.appendingPathComponent("drive_c/users", isDirectory: true)
        guard fileManager.fileExists(atPath: usersURL.path) else { return false }
        let userURLs = try fileManager.contentsOfDirectory(
            at: usersURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )

        let externalProfileURL = homeDirectory
            .appendingPathComponent("Wine", isDirectory: true)
            .standardizedFileURL
        var migrated = false

        for userURL in userURLs {
            try Task.checkCancellation()
            let values = try userURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink == true else { continue }

            let rawDestination = try fileManager.destinationOfSymbolicLink(atPath: userURL.path)
            let destinationURL: URL
            if rawDestination.hasPrefix("/") {
                destinationURL = URL(fileURLWithPath: rawDestination, isDirectory: true)
            } else {
                destinationURL = userURL.deletingLastPathComponent()
                    .appendingPathComponent(rawDestination, isDirectory: true)
            }
            guard destinationURL.standardizedFileURL == externalProfileURL else { continue }

            let temporaryPrefix = ".\(userURL.lastPathComponent)-WoWSilicon-migration-"
            let staleTemporaryURLs = try fileManager.contentsOfDirectory(
                at: usersURL,
                includingPropertiesForKeys: nil,
                options: []
            ).filter { $0.lastPathComponent.hasPrefix(temporaryPrefix) }
            for staleURL in staleTemporaryURLs {
                try fileManager.removeItem(at: staleURL)
            }

            let temporaryURL = usersURL.appendingPathComponent(
                "\(temporaryPrefix)\(UUID().uuidString)",
                isDirectory: true
            )
            defer { try? fileManager.removeItem(at: temporaryURL) }

            if fileManager.fileExists(atPath: externalProfileURL.path) {
                try fileManager.copyItem(at: externalProfileURL, to: temporaryURL)
            } else {
                try fileManager.createDirectory(at: temporaryURL, withIntermediateDirectories: false)
            }

            try Task.checkCancellation()
            try fileManager.removeItem(at: userURL)
            do {
                try fileManager.moveItem(at: temporaryURL, to: userURL)
            } catch {
                try? fileManager.createSymbolicLink(
                    atPath: userURL.path,
                    withDestinationPath: rawDestination
                )
                throw error
            }
            migrated = true
        }

        return migrated
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
