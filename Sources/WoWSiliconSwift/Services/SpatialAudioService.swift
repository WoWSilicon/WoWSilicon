import Foundation

enum SpatialAudioService {
    static func controlURL(
        applicationSupportURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        let supportURL = applicationSupportURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return supportURL
            .appendingPathComponent("WoWSilicon", isDirectory: true)
            .appendingPathComponent("spatial-audio-mode", isDirectory: false)
    }

    static func setEnabled(
        _ enabled: Bool,
        controlURL: URL = controlURL(),
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: controlURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let mode = enabled ? "fixed\n" : "off\n"
        try Data(mode.utf8).write(to: controlURL, options: .atomic)
    }

    static func nightModeControlURL(
        applicationSupportURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        controlURL(applicationSupportURL: applicationSupportURL, fileManager: fileManager)
            .deletingLastPathComponent()
            .appendingPathComponent("night-mode", isDirectory: false)
    }

    static func setNightMode(
        _ enabled: Bool,
        controlURL: URL = nightModeControlURL(),
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: controlURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data((enabled ? "on\n" : "off\n").utf8).write(to: controlURL, options: .atomic)
    }
}
