import Foundation

struct UserPrefsStore {
    private let fileManager = FileManager.default
    private let directoryName = "WoWSilicon"
    private let fileName = "prefs.json"

    func load() -> UserPrefs {
        guard let prefsURL = prefsFileURL(),
              fileManager.fileExists(atPath: prefsURL.path) else {
            return .defaults
        }

        do {
            let data = try Data(contentsOf: prefsURL)
            let prefs = try JSONDecoder().decode(UserPrefs.self, from: data)
            return prefs
        } catch {
            debugPrint("Failed to load prefs.json: \(error.localizedDescription)")
            return .defaults
        }
    }

    func save(_ prefs: UserPrefs) {
        guard let prefsURL = prefsFileURL() else {
            debugPrint("Unable to resolve prefs.json path")
            return
        }

        let directoryURL = prefsURL.deletingLastPathComponent()
        do {
            if !fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(prefs)
            try data.write(to: prefsURL, options: .atomic)
        } catch {
            debugPrint("Failed to save prefs.json: \(error.localizedDescription)")
        }
    }

    private func prefsFileURL() -> URL? {
        guard let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return supportDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}
