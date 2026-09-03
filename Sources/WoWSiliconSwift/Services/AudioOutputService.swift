import Foundation

struct WineAudioOutputDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

struct WineAudioDetails: Equatable, Sendable {
    let deviceName: String
    let channelCount: Int
    let sampleRate: Int
    let bitsPerSample: Int
}

struct WineAudioSnapshot: Equatable, Sendable {
    let outputs: [WineAudioOutputDevice]
    let inputs: [WineAudioOutputDevice]
    let details: WineAudioDetails?
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

    static func snapshot(customVariables: String = "") throws -> WineAudioSnapshot {
        let result = try runHelper(arguments: ["snapshot"], customVariables: customVariables)
        return parseSnapshot(result.stdout)
    }

    static func selectOutput(id: String, customVariables: String = "") throws {
        let arguments = id.isEmpty ? ["clear"] : ["set", id]
        _ = try runHelper(arguments: arguments, customVariables: customVariables)
    }

    static func selectInput(id: String, customVariables: String = "") throws {
        let arguments = id.isEmpty ? ["clear-input"] : ["set-input", id]
        _ = try runHelper(arguments: arguments, customVariables: customVariables)
    }

    static func testOutput(
        spatializeStereo: Bool,
        normalizeAudio: Bool,
        customVariables: String = ""
    ) throws {
        try SpatialAudioService.setEnabled(spatializeStereo)
        try SpatialAudioService.setNormalizeAudio(normalizeAudio)
        let environment = [
            "WOWSILICON_SPATIAL_AUDIO_MODE": spatializeStereo ? "fixed" : "off",
            "WOWSILICON_SPATIAL_AUDIO_CONTROL": SpatialAudioService.controlURL().path,
            "WOWSILICON_NORMALIZE_AUDIO": normalizeAudio ? "1" : "0",
            "WOWSILICON_NORMALIZE_AUDIO_CONTROL": SpatialAudioService.normalizeAudioControlURL().path
        ]
        _ = try runHelper(
            arguments: ["test"],
            customVariables: customVariables,
            environmentOverrides: environment
        )
    }

    static func shortcutSelectionCommands(
        outputID: String,
        inputID: String,
        customVariables: String
    ) throws -> [String] {
        guard !outputID.isEmpty || !inputID.isEmpty else { return [] }
        guard let wineURL = BundledWineRuntime.wineExecutableURL() else {
            throw AudioOutputServiceError.wineRuntimeMissing
        }
        guard let helperURL = helperURL() else {
            throw AudioOutputServiceError.helperMissing
        }

        let winePrefix = BundledWineRuntime.shellEnvironmentAssignment(
            key: "WINEPREFIX",
            value: WineRegistrySupport.winePrefixURL().path
        )
        let dyldLibraryPath = BundledWineRuntime.shellEnvironmentAssignment(
            key: "DYLD_LIBRARY_PATH",
            value: BundledWineRuntime.makeEnvironment()["DYLD_LIBRARY_PATH"] ?? ""
        )
        let custom = BundledWineRuntime.shellEnvironmentAssignments(customVariables)
        let environment = [custom, winePrefix, dyldLibraryPath]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let executable = shellQuote(wineURL.path)
        let helper = shellQuote(helperURL.path)

        var commands: [String] = []
        if !outputID.isEmpty {
            commands.append("\(environment) \(executable) \(helper) set \(shellQuote(outputID))")
        }
        if !inputID.isEmpty {
            commands.append("\(environment) \(executable) \(helper) set-input \(shellQuote(inputID))")
        }
        return commands
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

    static func parseSnapshot(_ output: String) -> WineAudioSnapshot {
        var outputs: [WineAudioOutputDevice] = []
        var inputs: [WineAudioOutputDevice] = []
        var details: WineAudioDetails?

        for line in output.split(whereSeparator: { $0.isNewline }) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard let type = fields.first else { continue }
            if (type == "O" || type == "I"), fields.count == 3, !fields[1].isEmpty {
                let name = String(fields[2]).trimmingCharacters(in: .whitespacesAndNewlines)
                let device = WineAudioOutputDevice(
                    id: String(fields[1]),
                    name: name.isEmpty ? String(fields[1]) : name
                )
                if type == "O" { outputs.append(device) } else { inputs.append(device) }
            } else if type == "D", fields.count == 5,
                      let channels = Int(fields[2]),
                      let sampleRate = Int(fields[3]),
                      let bits = Int(fields[4]) {
                details = WineAudioDetails(
                    deviceName: String(fields[1]),
                    channelCount: channels,
                    sampleRate: sampleRate,
                    bitsPerSample: bits
                )
            }
        }
        return WineAudioSnapshot(outputs: outputs, inputs: inputs, details: details)
    }

    private static func runHelper(
        arguments: [String],
        customVariables: String,
        environmentOverrides: [String: String] = [:]
    ) throws -> ProcessRunResult {
        guard let wineURL = BundledWineRuntime.wineExecutableURL() else {
            throw AudioOutputServiceError.wineRuntimeMissing
        }
        guard let helperURL = helperURL() else {
            throw AudioOutputServiceError.helperMissing
        }

        var environment = BundledWineRuntime.makeEnvironment(customVariables: customVariables)
        environment.merge(environmentOverrides) { _, new in new }
        let result = try ProcessRunner.run(
            executablePath: wineURL.path,
            arguments: [helperURL.path] + arguments,
            environment: environment,
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

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
