import Foundation

enum RetinaModeServiceError: LocalizedError {
    case wineMissing
    case commandFailed(String)
    case registryWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .wineMissing:
            return "Bundled Wine executable not found. Reinstall WoWSilicon and try again."
        case .commandFailed(let output):
            return output.isEmpty ? "Failed to update Wine registry." : output
        case .registryWriteFailed(let reason):
            return reason
        }
    }
}

enum RetinaModeService {
    private static let retinaLineY = #""RetinaMode"="Y""#

    static func setRetinaMode(enabled: Bool) throws {
        guard let wineExecutable = WineRegistrySupport.wineExecutablePath() else {
            throw RetinaModeServiceError.wineMissing
        }

        let prefixURL = WineRegistrySupport.winePrefixURL()
        try FileManager.default.createDirectory(at: prefixURL, withIntermediateDirectories: true)

        try runBatch(prefixURL: prefixURL, wineExecutable: wineExecutable, enabled: enabled)
        try setRegistryValueFast(enabled: enabled)
    }

    static func isRetinaModeEnabled() -> Bool {
        if let accurate = isRetinaModeEnabledAccurately() {
            return accurate
        }
        return isRetinaModeEnabledFast()
    }

    static func isRetinaModeEnabledFast() -> Bool {
        let regURL = WineRegistrySupport.userRegURL()
        guard let content = try? String(contentsOf: regURL, encoding: .utf8) else {
            return false
        }

        let lines = content.components(separatedBy: "\n")
        var inSection = false
        var lastValue: String? = nil

        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("[") {
                inSection = WineRegistrySupport.isMacDriverSection(trimmed)
                continue
            }

            if inSection && trimmed.contains("RetinaMode") {
                if trimmed.contains("\"Y\"") { lastValue = "Y" }
                else if trimmed.contains("\"N\"") { lastValue = "N" }
            }
        }

        return lastValue == "Y"
    }

    private static func isRetinaModeEnabledAccurately() -> Bool? {
        guard let wineExecutable = WineRegistrySupport.wineExecutablePath() else { return nil }

        let prefixURL = WineRegistrySupport.winePrefixURL()
        guard let result = try? ProcessRunner.run(
            executablePath: wineExecutable,
            arguments: ["reg", "query", WineRegistrySupport.macDriverRegistryKey, "/v", "RetinaMode"],
            environment: WineRegistrySupport.makeWineEnvironment(prefixURL: prefixURL, wineExecutable: wineExecutable),
            timeout: 10
        ) else {
            return nil
        }
        guard result.exitCode == 0 else { return false }

        let output = result.stdout
        return output.contains("RetinaMode") && output.contains("Y")
    }

    private static func runBatch(prefixURL: URL, wineExecutable: String, enabled: Bool) throws {
        let batchContent = makeBatchScript(enable: enabled)
        let batchURL = FileManager.default.temporaryDirectory.appendingPathComponent("wine_retina_mode.bat")
        try batchContent.write(to: batchURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: batchURL) }

        let result = try ProcessRunner.run(
            executablePath: wineExecutable,
            arguments: ["cmd", "/c", batchURL.path],
            environment: WineRegistrySupport.makeWineEnvironment(prefixURL: prefixURL, wineExecutable: wineExecutable),
            timeout: 60
        )

        if result.exitCode != 0 {
            throw RetinaModeServiceError.commandFailed(result.combinedOutput)
        }
    }

    private static func makeBatchScript(enable: Bool) -> String {
        if enable {
            return """
            @echo off
            reg add "\(WineRegistrySupport.macDriverRegistryKey)" /v "RetinaMode" /t REG_SZ /d "Y" /f
            """
        } else {
            return """
            @echo off
            reg delete "\(WineRegistrySupport.macDriverRegistryKey)" /v "RetinaMode" /f 2>nul
            """
        }
    }

    private static func setRegistryValueFast(enabled: Bool) throws {
        let regURL = WineRegistrySupport.userRegURL()
        try FileManager.default.createDirectory(at: regURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var lines: [String]
        if FileManager.default.fileExists(atPath: regURL.path) {
            let content = try String(contentsOf: regURL, encoding: .utf8)
            lines = content.components(separatedBy: "\n")
        } else {
            lines = "WINE REGISTRY Version 2\n;; All keys relative to \\User\n\n".components(separatedBy: "\n")
        }

        let updated = upsertRetinaMode(lines: lines, enabled: enabled)
        do {
            try updated.joined(separator: "\n").write(to: regURL, atomically: true, encoding: .utf8)
        } catch {
            throw RetinaModeServiceError.registryWriteFailed("Failed to update Wine registry file: \(error.localizedDescription)")
        }
    }

    private static func upsertRetinaMode(lines: [String], enabled: Bool) -> [String] {
        var lines = lines
        let desiredLine = enabled ? retinaLineY : nil

        if let sectionIndex = lines.firstIndex(where: { WineRegistrySupport.isMacDriverSection($0) }) {
            let sectionHeader = lines[sectionIndex].trimmingCharacters(in: .whitespacesAndNewlines)

            // Remove all existing RetinaMode entries within the section to avoid duplicates
            var index = sectionIndex + 1
            while index < lines.count {
                let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("[") && trimmed != sectionHeader { break }
                if trimmed.contains("RetinaMode") {
                    lines.remove(at: index)
                    continue
                }
                index += 1
            }

            var insertIndex = sectionIndex + 1

            var timestampExists = false
            var probeIndex = sectionIndex + 1
            while probeIndex < lines.count {
                let trimmed = lines[probeIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("[") && trimmed != sectionHeader { break }
                if trimmed.hasPrefix("#time=") { timestampExists = true; break }
                probeIndex += 1
            }

            if !timestampExists {
                lines.insert(WineRegistrySupport.timestampLine, at: insertIndex)
                insertIndex += 1
            }

            if let desiredLine {
                lines.insert(desiredLine, at: insertIndex)
            }
            return lines
        } else {
            var updated = lines
            if !(updated.last?.isEmpty ?? true) { updated.append("") }
            updated.append(WineRegistrySupport.macDriverSection)
            updated.append(WineRegistrySupport.timestampLine)
            if let desiredLine { updated.append(desiredLine) }
            return updated
        }
    }
}
