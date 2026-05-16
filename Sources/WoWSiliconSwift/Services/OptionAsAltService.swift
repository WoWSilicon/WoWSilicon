import Foundation

enum OptionAsAltServiceError: LocalizedError {
    case wineMissing
    case commandFailed(String)
    case registryWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .wineMissing:
            return "CrossOver wineloader not found. Please ensure you have applied the CrossOver patch."
        case .commandFailed(let output):
            return output.isEmpty ? "Failed to update Wine registry." : output
        case .registryWriteFailed(let reason):
            return reason
        }
    }
}

enum OptionAsAltService {
    private static let leftOptionLine = #""LeftOptionIsAlt"="Y""#
    private static let rightOptionLine = #""RightOptionIsAlt"="Y""#

    static func setOptionAsAlt(enabled: Bool, crossOverPath: String? = nil) throws {
        guard let wineExecutable = WineRegistrySupport.wineloaderPath(from: crossOverPath) else {
            throw OptionAsAltServiceError.wineMissing
        }

        let prefixURL = WineRegistrySupport.winePrefixURL()
        try FileManager.default.createDirectory(at: prefixURL, withIntermediateDirectories: true)

        if enabled {
            try? setRegistryValuesFast(enabled: false)
            try runBatch(prefixURL: prefixURL, wineExecutable: wineExecutable, enabled: true)
            try setRegistryValuesFast(enabled: true)
        } else {
            var batchError: Error?
            do {
                try runBatch(prefixURL: prefixURL, wineExecutable: wineExecutable, enabled: false)
            } catch {
                batchError = error
            }

            var fileError: Error?
            do {
                try setRegistryValuesFast(enabled: false)
            } catch {
                fileError = error
            }

            if let batchError {
                throw batchError
            }
            if let fileError {
                throw fileError
            }
        }
    }

    static func isOptionAsAltEnabled(crossOverPath: String? = nil) -> Bool {
        if let accurate = isOptionAsAltEnabledAccurately(crossOverPath: crossOverPath) {
            return accurate
        }
        return isOptionAsAltEnabledFast()
    }

    static func isOptionAsAltEnabledFast() -> Bool {
        let regURL = WineRegistrySupport.userRegURL()
        guard let content = try? String(contentsOf: regURL, encoding: .utf8) else {
            return false
        }

        if WineRegistrySupport.isMacDriverSection(content) {
            let leftFound = content.contains(leftOptionLine)
            let rightFound = content.contains(rightOptionLine)
            return leftFound && rightFound
        }

        return false
    }

    // MARK: - Helpers
    private static func isOptionAsAltEnabledAccurately(crossOverPath: String? = nil) -> Bool? {
        guard let wineExecutable = WineRegistrySupport.wineloaderPath(from: crossOverPath) else {
            return nil
        }

        let prefixURL = WineRegistrySupport.winePrefixURL()
        let left = queryRegistryValue(prefixURL: prefixURL, wineExecutable: wineExecutable, valueName: "LeftOptionIsAlt")
        let right = queryRegistryValue(prefixURL: prefixURL, wineExecutable: wineExecutable, valueName: "RightOptionIsAlt")

        return left && right
    }

    private static func queryRegistryValue(prefixURL: URL, wineExecutable: String, valueName: String) -> Bool {
        guard let result = try? ProcessRunner.run(
            executablePath: wineExecutable,
            arguments: ["reg", "query", WineRegistrySupport.macDriverRegistryKey, "/v", valueName],
            environment: WineRegistrySupport.makeWineEnvironment(prefixURL: prefixURL, wineExecutable: wineExecutable),
            timeout: 10
        ) else {
            return false
        }

        guard result.exitCode == 0 else {
            return false
        }

        let output = result.stdout
        return output.contains(valueName) && output.contains("Y")
    }

    private static func runBatch(prefixURL: URL, wineExecutable: String, enabled: Bool) throws {
        let batchContent = makeBatchScript(enable: enabled)
        let batchURL = FileManager.default.temporaryDirectory.appendingPathComponent(enabled ? "wine_registry_add.bat" : "wine_registry_delete.bat")
        try batchContent.write(to: batchURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: batchURL) }

        let environment = WineRegistrySupport.makeWineEnvironment(prefixURL: prefixURL, wineExecutable: wineExecutable)

        let result = try ProcessRunner.run(
            executablePath: wineExecutable,
            arguments: ["cmd", "/c", batchURL.path],
            environment: environment,
            timeout: 60
        )

        if result.exitCode != 0 {
            let commandDescription = """
            Executable: \(wineExecutable)
            Arguments: cmd /c \(batchURL.path)
            Environment:
              WINEPREFIX=\(environment["WINEPREFIX"] ?? "unset")
            Batch Contents:
            \(batchContent)
            """
            throw OptionAsAltServiceError.commandFailed("""
            \(commandDescription)
            Exit Code: \(result.exitCode)
            Output:
            \(result.combinedOutput)
            """)
        }
    }

    private static func makeBatchScript(enable: Bool) -> String {
        if enable {
            return """
            @echo off
            reg add "\(WineRegistrySupport.macDriverRegistryKey)" /v "LeftOptionIsAlt" /t REG_SZ /d "Y" /f
            reg add "\(WineRegistrySupport.macDriverRegistryKey)" /v "RightOptionIsAlt" /t REG_SZ /d "Y" /f
            """
        } else {
            return """
            @echo off
            reg delete "\(WineRegistrySupport.macDriverRegistryKey)" /v "LeftOptionIsAlt" /f 2>nul
            reg delete "\(WineRegistrySupport.macDriverRegistryKey)" /v "RightOptionIsAlt" /f 2>nul
            """
        }
    }

    private static func setRegistryValuesFast(enabled: Bool) throws {
        let regURL = WineRegistrySupport.userRegURL()
        try FileManager.default.createDirectory(at: regURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var lines: [String]
        if FileManager.default.fileExists(atPath: regURL.path) {
            let content = try String(contentsOf: regURL, encoding: .utf8)
            lines = content.components(separatedBy: "\n")
        } else {
            lines = "WINE REGISTRY Version 2\n;; All keys relative to \\User\n\n".components(separatedBy: "\n")
        }

        let updatedLines: [String]
        if enabled {
            updatedLines = addOptionAsAltSettings(lines: lines)
        } else {
            updatedLines = removeOptionAsAltSettings(lines: lines)
        }

        do {
            try updatedLines.joined(separator: "\n").write(to: regURL, atomically: true, encoding: .utf8)
        } catch {
            throw OptionAsAltServiceError.registryWriteFailed("Failed to update Wine registry file: \(error.localizedDescription)")
        }
    }

    private static func addOptionAsAltSettings(lines: [String]) -> [String] {
        var lines = lines
        if let sectionIndex = lines.firstIndex(where: { WineRegistrySupport.isMacDriverSection($0) }) {
            let sectionHeader = lines[sectionIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            var leftFound = false
            var rightFound = false

            var index = sectionIndex + 1
            while index < lines.count {
                let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("[") && trimmed != sectionHeader {
                    break
                }
                if trimmed.contains("LeftOptionIsAlt") {
                    leftFound = true
                    if !trimmed.contains("\"Y\"") {
                        lines[index] = leftOptionLine
                    }
                }
                if trimmed.contains("RightOptionIsAlt") {
                    rightFound = true
                    if !trimmed.contains("\"Y\"") {
                        lines[index] = rightOptionLine
                    }
                }
                index += 1
            }

            var insertIndex = sectionIndex + 1

            var timestampExists = false
            var probeIndex = sectionIndex + 1
            while probeIndex < lines.count {
                let trimmed = lines[probeIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("[") && trimmed != sectionHeader {
                    break
                }
                if trimmed.hasPrefix("#time=") {
                    timestampExists = true
                    break
                }
                probeIndex += 1
            }

            if !timestampExists {
                lines.insert(WineRegistrySupport.timestampLine, at: insertIndex)
                insertIndex += 1
            }

            if !leftFound {
                lines.insert(leftOptionLine, at: insertIndex)
                insertIndex += 1
            }

            if !rightFound {
                lines.insert(rightOptionLine, at: insertIndex)
            }

            return lines
        } else {
            var updated = lines
            if !(updated.last?.isEmpty ?? true) {
                updated.append("")
            }
            updated.append(WineRegistrySupport.macDriverSection)
            updated.append(WineRegistrySupport.timestampLine)
            updated.append(leftOptionLine)
            updated.append(rightOptionLine)
            return updated
        }
    }

    private static func removeOptionAsAltSettings(lines: [String]) -> [String] {
        var updated: [String] = []
        updated.reserveCapacity(lines.count)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("LeftOptionIsAlt") || trimmed.contains("RightOptionIsAlt") {
                continue
            }
            updated.append(line)
        }

        return removeEmptyMacDriverSections(lines: updated)
    }

    private static func removeEmptyMacDriverSections(lines: [String]) -> [String] {
        var result: [String] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if WineRegistrySupport.isMacDriverSection(trimmed) {
                var sectionEnd = index + 1
                var hasContent = false

                while sectionEnd < lines.count {
                    let nextTrimmed = lines[sectionEnd].trimmingCharacters(in: .whitespacesAndNewlines)
                    if nextTrimmed.hasPrefix("[") {
                        break
                    }
                    if !nextTrimmed.isEmpty && !nextTrimmed.hasPrefix("#time=") {
                        hasContent = true
                    }
                    sectionEnd += 1
                }

                if hasContent {
                    while index < sectionEnd {
                        result.append(lines[index])
                        index += 1
                    }
                } else {
                    index = sectionEnd
                }
                continue
            }

            result.append(lines[index])
            index += 1
        }

        return result
    }
}
