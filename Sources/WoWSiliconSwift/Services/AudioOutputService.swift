import Foundation

struct WineAudioOutputDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

enum AudioOutputServiceError: LocalizedError {
    case wineRuntimeMissing
    case helperMissing
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .wineRuntimeMissing:
            return "The bundled Wine runtime could not be found."
        case .helperMissing:
            return "The Wine audio helper is missing. Reinstall WoWSilicon and try again."
        case .commandFailed(let message):
            return message
        }
    }
}

enum AudioOutputService {
    static let helperEnvironmentOverride = "WOWSILICON_AUDIO_HELPER"

    static func availableOutputs(customVariables: String = "") throws -> [WineAudioOutputDevice] {
        let result = try runHelper(arguments: ["list"], customVariables: customVariables)
        return parseDeviceList(result.stdout)
    }

    static func selectOutput(id: String, customVariables: String = "") throws {
        let arguments = id.isEmpty ? ["clear"] : ["set", id]
        _ = try runHelper(arguments: arguments, customVariables: customVariables)
    }

    static func parseDeviceList(_ output: String) -> [WineAudioOutputDevice] {
        output.split(whereSeparator: { $0.isNewline }).compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else { return nil }
            let id = String(fields[0])
            guard !id.isEmpty else { return nil }
            let rawName = String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            return WineAudioOutputDevice(id: id, name: rawName.isEmpty ? id : rawName)
        }
    }

    private static func runHelper(
        arguments: [String],
        customVariables: String
    ) throws -> ProcessRunResult {
        guard let wineURL = BundledWineRuntime.wineExecutableURL() else {
            throw AudioOutputServiceError.wineRuntimeMissing
        }
        guard let helperURL = helperURL() else {
            throw AudioOutputServiceError.helperMissing
        }

        let result = try ProcessRunner.run(
            executablePath: wineURL.path,
            arguments: [helperURL.path] + arguments,
            environment: BundledWineRuntime.makeEnvironment(customVariables: customVariables),
            timeout: 20
        )
        guard result.exitCode == 0 else {
            let detail = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AudioOutputServiceError.commandFailed(
                detail.isEmpty ? "Wine could not update the audio output." : detail
            )
        }
        return result
    }

    private static func helperURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let override = environment[helperEnvironmentOverride]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           FileManager.default.fileExists(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        return PatchService.resourceURL(
            named: "wowsilicon-audio",
            extension: "exe",
            subdirectory: "Audio"
        )
    }
}
