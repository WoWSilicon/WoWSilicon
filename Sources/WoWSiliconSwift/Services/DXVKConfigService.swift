import Foundation

enum DXVKConfigServiceError: LocalizedError {
    case gamePathMissing
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .gamePathMissing:
            return "Game path is not set. Configure it before adjusting the cursor size."
        case .writeFailed(let details):
            return "Failed to update cursor configuration: \(details)"
        }
    }
}

enum DXVKConfigService {
    private static func gameDirectoryURL(from gamePath: String) -> URL? {
        let trimmed = gamePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir) {
            return isDir.boolValue ? URL(fileURLWithPath: trimmed, isDirectory: true) : URL(fileURLWithPath: trimmed).deletingLastPathComponent()
        }
        let url = URL(fileURLWithPath: trimmed)
        return url.pathExtension.lowercased() == "exe" ? url.deletingLastPathComponent() : url
    }

    static func cursorSizeMultiplier(gamePath: String) -> Int? {
        guard let gameDirURL = gameDirectoryURL(from: gamePath) else { return nil }
        let url = gameDirURL.appendingPathComponent("dxvk.conf", isDirectory: false)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = content.split(whereSeparator: { $0.isNewline })
        for rawLine in lines {
            let trimmedLine = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.lowercased().hasPrefix("d3d9.enlargehardwarecursor") {
                let components = trimmedLine.split(separator: "=")
                guard let valueComponent = components.last else { continue }
                let numberString = valueComponent.trimmingCharacters(in: .whitespaces)
                if let value = Int(numberString) {
                    return value
                }
            }
        }
        return nil
    }

    static func setCursorSizeMultiplier(gamePath: String, multiplier: Int) throws {
        guard let gameDirURL = gameDirectoryURL(from: gamePath) else { throw DXVKConfigServiceError.gamePathMissing }
        let url = gameDirURL.appendingPathComponent("dxvk.conf", isDirectory: false)
        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        content = updateCursorSizeLine(content: content, multiplier: multiplier)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            try updateMtld3dCursorSize(gameURL: gameDirURL, multiplier: multiplier)
        } catch {
            throw DXVKConfigServiceError.writeFailed(error.localizedDescription)
        }
    }

    private static func updateMtld3dCursorSize(gameURL: URL, multiplier: Int) throws {
        let configURL = gameURL.appendingPathComponent("mtld3d.conf", isDirectory: false)
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }

        let content = try String(contentsOf: configURL, encoding: .utf8)
        let updated = ConfigService.updateMtld3dSetting(
            content: content,
            key: "cursor.scale",
            value: String(max(1, multiplier))
        )
        try updated.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func updateCursorSizeLine(content: String, multiplier: Int) -> String {
        if multiplier <= 1 {
            return removeCursorSizeLine(content: content)
        }

        let pattern = "(?m)^\\s*d3d9\\.enlargeHardwareCursor\\s*=\\s*\\d+\\s*$"
        let replacement = "d3d9.enlargeHardwareCursor = \(multiplier)"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(content.startIndex..., in: content)
            if regex.firstMatch(in: content, options: [], range: range) != nil {
                return regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: replacement)
            }
        }
        var newContent = content
        if !newContent.isEmpty && !newContent.hasSuffix("\n") {
            newContent += "\n"
        }
        newContent += replacement + "\n"
        return newContent
    }

    private static func removeCursorSizeLine(content: String) -> String {
        let pattern = "(?m)^\\s*d3d9\\.enlargeHardwareCursor\\s*=\\s*\\d+\\s*$\\n?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return content }
        let range = NSRange(content.startIndex..., in: content)
        let updated = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
        return updated.replacingOccurrences(of: "\n\n", with: "\n")
    }
}
