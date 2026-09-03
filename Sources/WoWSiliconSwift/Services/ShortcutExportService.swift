import AppKit
import Foundation

enum ShortcutExportError: LocalizedError {
    case signingFailed(String)
    case outputMissing
    case importFailed

    var errorDescription: String? {
        switch self {
        case .signingFailed(let detail):
            return detail.isEmpty
                ? "macOS could not sign the shortcut. Check your internet connection and try again."
                : "macOS could not sign the shortcut: \(detail)"
        case .outputMissing:
            return "macOS reported that the shortcut was signed, but did not create the file."
        case .importFailed:
            return "The shortcut was created, but could not be opened in Shortcuts."
        }
    }
}

enum ShortcutExportService {
    static func createSignedShortcut(name: String, shellScript: String) throws -> URL {
        let fileManager = FileManager.default
        let exportDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("WoWSilicon-Shortcut-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )

        let safeName = sanitizedFilename(name)
        let unsignedURL = exportDirectory.appendingPathComponent("Unsigned.shortcut")
        let signedURL = exportDirectory.appendingPathComponent("\(safeName).shortcut")
        try workflowData(name: name, shellScript: shellScript).write(to: unsignedURL, options: .atomic)
        defer { try? fileManager.removeItem(at: unsignedURL) }

        let result = try ProcessRunner.run(
            executablePath: "/usr/bin/shortcuts",
            arguments: [
                "sign", "--mode", "anyone",
                "--input", unsignedURL.path,
                "--output", signedURL.path
            ],
            timeout: 60
        )
        guard result.exitCode == 0 else {
            throw ShortcutExportError.signingFailed(
                result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard fileManager.fileExists(atPath: signedURL.path) else {
            throw ShortcutExportError.outputMissing
        }
        return signedURL
    }

    static func openForImport(_ shortcutURL: URL) throws {
        guard NSWorkspace.shared.open(shortcutURL) else {
            throw ShortcutExportError.importFailed
        }
    }

    static func workflowData(name: String, shellScript: String) throws -> Data {
        let workflow: [String: Any] = [
            "WFWorkflowActions": [[
                "WFWorkflowActionIdentifier": "is.workflow.actions.runshellscript",
                "WFWorkflowActionParameters": [
                    // Current macOS parameter names.
                    "WFShellScriptActionInputMethod": "Arguments",
                    "WFShellScriptActionScript": shellScript,
                    "WFShellScriptActionShell": "/bin/zsh",
                    // Retained for older macOS Shortcuts releases.
                    "Input": [
                        "Value": ["Type": "ExtensionInput"],
                        "WFSerializationType": "WFTextTokenAttachment"
                    ],
                    "InputMode": "as arguments",
                    "Script": shellScript,
                    "Shell": "/bin/zsh"
                ]
            ]],
            "WFWorkflowClientRelease": "3.0.2",
            "WFWorkflowClientVersion": "2600.0.0",
            "WFWorkflowIcon": [
                "WFWorkflowIconGlyphNumber": 59511,
                "WFWorkflowIconStartColor": 4282601983
            ],
            "WFWorkflowImportQuestions": [],
            "WFWorkflowInputContentItemClasses": [],
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowName": name,
            "WFWorkflowOutputContentItemClasses": [],
            "WFWorkflowTypes": []
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: workflow,
            format: .binary,
            options: 0
        )
    }

    private static func sanitizedFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let components = name.components(separatedBy: invalid).filter { !$0.isEmpty }
        let sanitized = components.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Launch WoW" : sanitized
    }
}
