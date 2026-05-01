import Foundation

/// Service for applying and checking tahoe-patches on PE (DLL/EXE) files.
/// Patches set the IMAGE_DLL_CHARACTERISTICS_NX_COMPAT flag in the PE header.
enum TahoePatchService {
    /// Files that should be patched (case-insensitive matching)
    static let targetFileNames: Set<String> = []

    /// The DllCharacteristics flag we check for
    private static let nxCompatFlag: UInt16 = 0x0100  // IMAGE_DLL_CHARACTERISTICS_NX_COMPAT

    enum TahoePatchError: LocalizedError {
        case tahoePatchNotFound
        case fileNotFound(String)
        case invalidPEFile(String)
        case patchFailed(String, String)
        case revertFailed(String, String)

        var errorDescription: String? {
            switch self {
            case .tahoePatchNotFound:
                return "tahoe-patch binary not found in application resources."
            case .fileNotFound(let path):
                return "File not found: \(path)"
            case .invalidPEFile(let path):
                return "Invalid or unsupported PE file: \(path)"
            case .patchFailed(let file, let reason):
                return "Failed to patch \(file): \(reason)"
            case .revertFailed(let file, let reason):
                return "Failed to revert patch on \(file): \(reason)"
            }
        }
    }

    /// Result of checking a single file's patch status
    struct FileStatus {
        let url: URL
        let isPatched: Bool
    }

    // MARK: - Public API

    /// Find the tahoe-patch binary in app resources
    static func tahoePatchURL() -> URL? {
        PatchService.resourceURL(named: "tahoe-patch", extension: nil, subdirectory: "Patching/winerosetta")
    }

    /// Check if a PE file has the NX_COMPAT flag set (is patched)
    static func isFilePatched(at url: URL) -> Bool {
        guard let dllCharacteristics = readDllCharacteristics(at: url) else {
            return false
        }
        return (dllCharacteristics & nxCompatFlag) != 0
    }

    /// Find all target files in the game directory that exist but are NOT patched
    static func findUnpatchedFiles(in gameDirectory: URL, versionId: String?) -> [URL] {
        findTargetFiles(in: gameDirectory, versionId: versionId).filter { !isFilePatched(at: $0) }
    }

    /// Find all target files in the game directory that exist and ARE patched
    static func findPatchedFiles(in gameDirectory: URL, versionId: String?) -> [URL] {
        findTargetFiles(in: gameDirectory, versionId: versionId).filter { isFilePatched(at: $0) }
    }

    /// Find all target files that exist in the game directory
    static func findTargetFiles(in gameDirectory: URL, versionId: String?) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: gameDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var found: [URL] = []
        for case let fileURL as URL in enumerator {
            let fileName = fileURL.lastPathComponent.lowercased()
            if targetFileNames.contains(fileName) {
                found.append(fileURL)
            }
        }
        return found
    }

    /// Apply tahoe-patch to a single file
    static func applyPatch(to fileURL: URL) throws {
        guard let tahoePatch = tahoePatchURL() else {
            throw TahoePatchError.tahoePatchNotFound
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw TahoePatchError.fileNotFound(fileURL.path)
        }

        // Create a backup before patching (.exe.bak or .dll.bak)
        let backupURL = fileURL.appendingPathExtension("bak")
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            do {
                try FileManager.default.copyItem(at: fileURL, to: backupURL)
            } catch {
                throw TahoePatchError.patchFailed(fileURL.lastPathComponent, "Failed to create backup: \(error.localizedDescription)")
            }
        }

        try runTahoePatch(tahoePatch, action: "apply", target: fileURL)
    }

    /// Revert tahoe-patch from a single file
    static func revertPatch(from fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw TahoePatchError.fileNotFound(fileURL.path)
        }

        // Restore from backup if it exists
        let backupURL = fileURL.appendingPathExtension("bak")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
                try FileManager.default.copyItem(at: backupURL, to: fileURL)
                try FileManager.default.removeItem(at: backupURL)
            } catch {
                throw TahoePatchError.revertFailed(fileURL.lastPathComponent, "Failed to restore backup: \(error.localizedDescription)")
            }
            return
        }

        // Fallback to in-place revert using Tahoe patch
        guard let tahoePatch = tahoePatchURL() else {
            throw TahoePatchError.tahoePatchNotFound
        }

        try runTahoePatch(tahoePatch, action: "revert", target: fileURL)
    }

    /// Apply patches to all unpatched target files in the game directory
    static func applyPatchesToUnpatchedFiles(in gameDirectory: URL, versionId: String?) throws {
        let unpatched = findUnpatchedFiles(in: gameDirectory, versionId: versionId)
        for fileURL in unpatched {
            try applyPatch(to: fileURL)
        }
    }

    /// Revert patches from all patched target files in the game directory
    static func revertPatchesFromPatchedFiles(in gameDirectory: URL, versionId: String?) throws {
        let patched = findPatchedFiles(in: gameDirectory, versionId: versionId)
        for fileURL in patched {
            try revertPatch(from: fileURL)
        }
    }

    // MARK: - Private Helpers

    /// Run the tahoe-patch binary with the given action
    private static func runTahoePatch(_ tahoePatchURL: URL, action: String, target: URL) throws {
        // Ensure tahoe-patch is executable
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: tahoePatchURL.path
        )

        let task = Process()
        task.executableURL = tahoePatchURL
        task.arguments = [action, target.path]
        task.currentDirectoryURL = target.deletingLastPathComponent()

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        try task.run()
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorMessage = output.isEmpty ? "Exit code \(task.terminationStatus)" : output.trimmingCharacters(in: .whitespacesAndNewlines)
            if action == "apply" {
                throw TahoePatchError.patchFailed(target.lastPathComponent, errorMessage)
            } else {
                throw TahoePatchError.revertFailed(target.lastPathComponent, errorMessage)
            }
        }
    }

    /// Read DllCharacteristics field from a PE file
    /// Returns nil if the file is not a valid PE file
    private static func readDllCharacteristics(at url: URL) -> UInt16? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        // Read DOS header - check for MZ magic
        guard let dosHeader = try? handle.read(upToCount: 64), dosHeader.count >= 64 else {
            return nil
        }

        // Check MZ signature
        guard dosHeader[0] == 0x4D, dosHeader[1] == 0x5A else { // "MZ"
            return nil
        }

        // Get e_lfanew (offset to PE header) at offset 0x3C (60)
        let eLfanew = UInt32(dosHeader[60]) |
                      (UInt32(dosHeader[61]) << 8) |
                      (UInt32(dosHeader[62]) << 16) |
                      (UInt32(dosHeader[63]) << 24)

        // Seek to PE header
        do {
            try handle.seek(toOffset: UInt64(eLfanew))
        } catch {
            return nil
        }

        // Read PE signature and headers
        guard let peHeader = try? handle.read(upToCount: 0x60), peHeader.count >= 0x60 else {
            return nil
        }

        // Check PE signature "PE\0\0"
        guard peHeader[0] == 0x50, peHeader[1] == 0x45, peHeader[2] == 0x00, peHeader[3] == 0x00 else {
            return nil
        }

        // DllCharacteristics is at offset 0x5E from PE signature for 32-bit PE (PE32)
        // For PE32+, it's at offset 0x6E, but WoW 1.12.1 uses 32-bit executables
        // Optional header starts at offset 0x18 from PE signature
        // DllCharacteristics is at offset 0x46 from start of optional header (for PE32)
        // So total offset from PE signature = 0x18 + 0x46 = 0x5E

        let dllCharacteristicsOffset = 0x5E
        guard peHeader.count > dllCharacteristicsOffset + 1 else {
            return nil
        }

        let dllCharacteristics = UInt16(peHeader[dllCharacteristicsOffset]) |
                                 (UInt16(peHeader[dllCharacteristicsOffset + 1]) << 8)

        return dllCharacteristics
    }
}
