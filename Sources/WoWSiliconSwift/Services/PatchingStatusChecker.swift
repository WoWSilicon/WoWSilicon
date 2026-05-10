import Foundation
import CryptoKit

struct PatchStatusDescriptor {
    let applied: Bool
    let text: String
    let level: StatusLevel
    let actionable: Bool
}

enum PatchingStatusChecker {
    private static let dllsEntry = "mods/winerosetta.dll"

    static func evaluateGamePatch(for version: GameVersion) -> PatchStatusDescriptor {
        guard !version.gamePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PatchStatusDescriptor(
                applied: false,
                text: "Not set",
                level: .error,
                actionable: false
            )
        }

        let gamePath = version.gamePath
        let gameURL = URL(fileURLWithPath: gamePath, isDirectory: true)

        guard PatchService.isSupportedGameClient(at: gameURL) else {
            return PatchStatusDescriptor(
                applied: false,
                text: "Not a WoW client",
                level: .error,
                actionable: false
            )
        }

        if version.usesRosettaPatching {
            var requiredFiles = [
                gamePath.appendingPathComponent("mods/winerosetta.dll"),
                gamePath.appendingPathComponent("d3d9.dll"),
                gamePath.appendingPathComponent("rosettax87/rosettax87"),
                gamePath.appendingPathComponent("rosettax87/libRuntimeRosettax87")
            ]

            if version.supportsDLLLoading {
                requiredFiles.append(gamePath.appendingPathComponent("libDllLdr.dll"))
                requiredFiles.append(gamePath.appendingPathComponent("DivxDecoder.dll.bak"))
            }

            if version.libSiliconPatchSubdirectory != nil && version.settings.enableLibSiliconPatch {
                requiredFiles.append(gamePath.appendingPathComponent("mods/libSiliconPatch.dll"))
            }

            if let missingPath = requiredFiles.first(where: { !fileExists(at: $0) }) {
                return PatchStatusDescriptor(
                    applied: false,
                    text: "Missing \(missingPath.lastPathComponent)",
                    level: .error,
                    actionable: true
                )
            }

            if !dllRegistered(in: gamePath.appendingPathComponent("dlls.txt"), entry: dllsEntry) {
                return PatchStatusDescriptor(
                    applied: false,
                    text: "dlls.txt missing \(dllsEntry)",
                    level: .warning,
                    actionable: true
                )
            }

            if let outdated = outdatedResource(in: gamePath, for: version) {
                return PatchStatusDescriptor(
                    applied: false,
                    text: "\(outdated) outdated",
                    level: .warning,
                    actionable: true
                )
            }

            return PatchStatusDescriptor(
                applied: true,
                text: "Applied",
                level: .success,
                actionable: true
            )
        }

        if version.usesDivxDecoderPatch {
            let divxPath = gamePath.appendingPathComponent("DivxDecoder.dll")
            let d3d9Path = gamePath.appendingPathComponent("d3d9.dll")
            if !fileExists(at: divxPath) || !fileExists(at: d3d9Path) {
                let missingName = !fileExists(at: divxPath) ? "DivxDecoder.dll" : "d3d9.dll"
                return PatchStatusDescriptor(
                    applied: false,
                    text: "Missing \(missingName)",
                    level: .error,
                    actionable: true
                )
            }

            return PatchStatusDescriptor(
                applied: true,
                text: "Applied",
                level: .success,
                actionable: true
            )
        }

        // Versions that do not require patching
        return PatchStatusDescriptor(
            applied: true,
            text: "Not required",
            level: .info,
            actionable: false
        )
    }

    static func evaluateCrossOverPatch(crossOverPath: String? = nil) -> PatchStatusDescriptor {
        let resolvedPath = crossOverPath ?? "/Applications/CrossOver.app"
        let crossOverURL = URL(fileURLWithPath: resolvedPath, isDirectory: true)
        
        let wineloader2Path = resolvedPath + "/Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wineloader2"

        // Check if CrossOver is installed
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            return PatchStatusDescriptor(
                applied: false,
                text: "CrossOver not found",
                level: .error,
                actionable: false
            )
        }

        let crossOverVersion = PatchService.detectCrossOverVersion(at: crossOverURL)
        guard crossOverVersion == .v26 else {
            return PatchStatusDescriptor(
                applied: false,
                text: "CrossOver 26 required",
                level: .error,
                actionable: false
            )
        }

        // Check if wineloader2 exists
        guard FileManager.default.fileExists(atPath: wineloader2Path) else {
            return PatchStatusDescriptor(
                applied: false,
                text: "Not Applied",
                level: .error,
                actionable: true
            )
        }

        // Check if wineloader2 is executable
        guard FileManager.default.isExecutableFile(atPath: wineloader2Path) else {
            return PatchStatusDescriptor(
                applied: false,
                text: "Not executable",
                level: .error,
                actionable: true
            )
        }

        let cxUnixDir = crossOverURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("SharedSupport", isDirectory: true)
            .appendingPathComponent("CrossOver", isDirectory: true)
            .appendingPathComponent("lib", isDirectory: true)
            .appendingPathComponent("wine", isDirectory: true)
            .appendingPathComponent("x86_64-unix", isDirectory: true)

        let wineBinary = cxUnixDir.appendingPathComponent("wine", isDirectory: false)
        let ntdllBinary = cxUnixDir.appendingPathComponent("ntdll.so", isDirectory: false)

        if PatchService.isSigned(at: wineBinary) {
            return PatchStatusDescriptor(
                applied: false,
                text: "wine needs patch",
                level: .warning,
                actionable: true
            )
        }

        guard let bundledNtdllURL = PatchService.resourceURL(named: "ntdll", extension: "so", subdirectory: "Patching/winerosetta") else {
            return PatchStatusDescriptor(
                applied: false,
                text: "Missing ntdll resource",
                level: .error,
                actionable: false
            )
        }

        if PatchService.fileChecksum(at: ntdllBinary) != PatchService.fileChecksum(at: bundledNtdllURL) {
            return PatchStatusDescriptor(
                applied: false,
                text: "ntdll.so needs patch",
                level: .warning,
                actionable: true
            )
        }

        return PatchStatusDescriptor(
            applied: true,
            text: "Applied",
            level: .success,
            actionable: true
        )
    }


    // MARK: - Helpers

    private static func dllRegistered(in dllsPath: URL, entry: String) -> Bool {
        guard let data = try? Data(contentsOf: dllsPath),
              let contents = String(data: data, encoding: .utf8) else {
            return false
        }
        return contents
            .split(whereSeparator: \.isNewline)
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(entry) == .orderedSame }
    }

    private static func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private struct ResourceExpectation {
        let relativePath: String
        let resourceName: String
        let resourceExtension: String?
        let resourceSubdirectory: String
        let displayName: String
    }

    private static func outdatedResource(in gamePath: String, for version: GameVersion) -> String? {
        let expectations = resourceExpectations(for: version)
        for expectation in expectations {
            let targetURL = gamePath.appendingPathComponent(expectation.relativePath)
            guard let targetChecksum = fileChecksum(at: targetURL) else { continue }

            guard let sourceURL = PatchService.resourceURL(
                named: expectation.resourceName,
                extension: expectation.resourceExtension,
                subdirectory: expectation.resourceSubdirectory
            ), let sourceChecksum = fileChecksum(at: sourceURL) else {
                continue
            }

            if targetChecksum != sourceChecksum {
                return expectation.displayName
            }
        }
        return nil
    }

    private static func resourceExpectations(for version: GameVersion) -> [ResourceExpectation] {
        var expectations: [ResourceExpectation] = [
            ResourceExpectation(
                relativePath: "mods/winerosetta.dll",
                resourceName: "winerosetta",
                resourceExtension: "dll",
                resourceSubdirectory: "Patching/winerosetta",
                displayName: "winerosetta.dll"
            ),
            ResourceExpectation(
                relativePath: "d3d9.dll",
                resourceName: "d3d9",
                resourceExtension: "dll",
                resourceSubdirectory: "Patching/d9vk",
                displayName: "d3d9.dll"
            ),
            ResourceExpectation(
                relativePath: "rosettax87/rosettax87",
                resourceName: "rosettax87",
                resourceExtension: nil,
                resourceSubdirectory: "Patching/rosettax87",
                displayName: "rosettax87"
            ),
            ResourceExpectation(
                relativePath: "rosettax87/libRuntimeRosettax87",
                resourceName: "libRuntimeRosettax87",
                resourceExtension: nil,
                resourceSubdirectory: "Patching/rosettax87",
                displayName: "libRuntimeRosettax87"
            )
        ]

        if version.usesRosettaPatching && version.supportsDLLLoading {
            expectations.append(
                ResourceExpectation(
                    relativePath: "libDllLdr.dll",
                    resourceName: "libDllLdr",
                    resourceExtension: "dll",
                    resourceSubdirectory: "Patching/winerosetta",
                    displayName: "libDllLdr.dll"
                )
            )
        }

        if let subdir = version.libSiliconPatchSubdirectory, version.settings.enableLibSiliconPatch {
            expectations.append(
                ResourceExpectation(
                    relativePath: "mods/libSiliconPatch.dll",
                    resourceName: "libSiliconPatch",
                    resourceExtension: "dll",
                    resourceSubdirectory: subdir,
                    displayName: "libSiliconPatch.dll"
                )
            )
        }

        return expectations
    }

    private static func fileChecksum(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    func appendingPathComponent(_ component: String) -> URL {
        URL(fileURLWithPath: self).appendingPathComponent(component)
    }
}
