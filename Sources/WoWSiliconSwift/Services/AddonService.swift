import Foundation

struct AddonInfo: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let path: String
    let hasGitRepo: Bool
    let gitRemoteURL: String?
    let lastUpdated: Date
    let description: String
    let localCommit: String?
    let remoteCommit: String?
    let needsUpdate: Bool

    init(
        id: String,
        name: String,
        path: String,
        hasGitRepo: Bool,
        gitRemoteURL: String?,
        lastUpdated: Date,
        description: String,
        localCommit: String?,
        remoteCommit: String?,
        needsUpdate: Bool
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.hasGitRepo = hasGitRepo
        self.gitRemoteURL = gitRemoteURL
        self.lastUpdated = lastUpdated
        self.description = description
        self.localCommit = localCommit
        self.remoteCommit = remoteCommit
        self.needsUpdate = needsUpdate
    }

    static func == (lhs: AddonInfo, rhs: AddonInfo) -> Bool {
        lhs.id == rhs.id
    }
}

enum AddonServiceError: LocalizedError {
    case gamePathMissing
    case addonsDirectoryMissing(String)
    case gitFailed(String)
    case installFailed(String)
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .gamePathMissing:
            return "Game path is not set. Configure it before managing addons."
        case .addonsDirectoryMissing(let path):
            return "Addons directory not found: \(path)"
        case .gitFailed(let output):
            return output.isEmpty ? "Git command failed." : output
        case .installFailed(let reason):
            return reason
        case .deleteFailed(let reason):
            return reason
        }
    }
}

enum AddonService {
    static func scanAddons(gamePath: String?, checkUpdates: Bool, progress: ((String) -> Void)?) throws -> [AddonInfo] {
        guard let gamePath = gamePath?.trimmingCharacters(in: .whitespacesAndNewlines), !gamePath.isEmpty else {
            throw AddonServiceError.gamePathMissing
        }

        let addonsURL = URL(fileURLWithPath: gamePath, isDirectory: true)
            .appendingPathComponent("Interface", isDirectory: true)
            .appendingPathComponent("Addons", isDirectory: true)

        guard FileManager.default.fileExists(atPath: addonsURL.path, isDirectory: nil) else {
            throw AddonServiceError.addonsDirectoryMissing(addonsURL.path)
        }

        let entries = try FileManager.default.contentsOfDirectory(at: addonsURL, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey], options: .skipsHiddenFiles)

        var addons: [AddonInfo] = []
        for (index, entry) in entries.enumerated() {
            let resourceValues = try entry.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues.isDirectory == true else { continue }

            progress?("Processing \(entry.lastPathComponent) (\(index + 1)/\(entries.count))…")

            let addonPath = entry.path
            let hasGitRepo = FileManager.default.fileExists(atPath: entry.appendingPathComponent(".git", isDirectory: true).path)

            let gitRemote = hasGitRepo ? gitRemoteURL(at: addonPath) : nil
            let localCommit = hasGitRepo ? gitCommit(at: addonPath, ref: "HEAD") : nil
            let remoteCommit = hasGitRepo && checkUpdates ? firstAvailableRemoteCommit(at: addonPath) : nil
            let needsUpdate = hasGitRepo && checkUpdates && localCommit != nil && remoteCommit != nil && localCommit != remoteCommit

            let lastMod = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let description = addonDescription(at: addonPath)

            let info = AddonInfo(
                id: addonPath,
                name: entry.lastPathComponent,
                path: addonPath,
                hasGitRepo: hasGitRepo,
                gitRemoteURL: gitRemote,
                lastUpdated: lastMod,
                description: description,
                localCommit: localCommit,
                remoteCommit: remoteCommit,
                needsUpdate: needsUpdate
            )
            addons.append(info)
        }

        return addons.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    static func update(addon: AddonInfo) throws -> AddonInfo {
        guard addon.hasGitRepo else { throw AddonServiceError.gitFailed("Addon is not a git repository") }
        let output = try runGit(arguments: ["pull"], at: addon.path)
        if output.exitStatus != 0 {
            throw AddonServiceError.gitFailed(output.stderr)
        }

        let now = Date()
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: addon.path)
        let localCommit = gitCommit(at: addon.path, ref: "HEAD")
        let remoteCommit = firstAvailableRemoteCommit(at: addon.path)

        return AddonInfo(
            id: addon.id,
            name: addon.name,
            path: addon.path,
            hasGitRepo: addon.hasGitRepo,
            gitRemoteURL: addon.gitRemoteURL,
            lastUpdated: now,
            description: addon.description,
            localCommit: localCommit,
            remoteCommit: remoteCommit,
            needsUpdate: localCommit != remoteCommit
        )
    }

    static func delete(addon: AddonInfo) throws {
        do {
            try FileManager.default.removeItem(atPath: addon.path)
        } catch {
            throw AddonServiceError.deleteFailed(error.localizedDescription)
        }
    }

    static func install(from urlString: String, gamePath: String?) throws {
        guard let gamePath = gamePath?.trimmingCharacters(in: .whitespacesAndNewlines), !gamePath.isEmpty else {
            throw AddonServiceError.gamePathMissing
        }
        guard let repoURL = URL(string: urlString), repoURL.scheme?.hasPrefix("http") == true else {
            throw AddonServiceError.installFailed("Invalid repository URL")
        }

        let addonsDir = URL(fileURLWithPath: gamePath, isDirectory: true)
            .appendingPathComponent("Interface", isDirectory: true)
            .appendingPathComponent("Addons", isDirectory: true)
        
        let initialDirName = repoURL.lastPathComponent.replacingOccurrences(of: ".git", with: "")
        let targetDir = addonsDir.appendingPathComponent(initialDirName, isDirectory: true)

        if FileManager.default.fileExists(atPath: targetDir.path) {
            throw AddonServiceError.installFailed("An addon with this name already exists.")
        }

        let result = try runGit(arguments: ["clone", urlString, targetDir.path], at: nil)
        if result.exitStatus != 0 {
            throw AddonServiceError.installFailed(result.stderr.isEmpty ? "git clone failed" : result.stderr)
        }

        if let contents = try? FileManager.default.contentsOfDirectory(atPath: targetDir.path),
           let tocFile = contents.first(where: { $0.lowercased().hasSuffix(".toc") }) {
            let newDirName = (tocFile as NSString).deletingPathExtension
            if newDirName != initialDirName {
                let finalTargetDir = addonsDir.appendingPathComponent(newDirName, isDirectory: true)
                do {
                    if FileManager.default.fileExists(atPath: finalTargetDir.path) {
                        try FileManager.default.removeItem(at: finalTargetDir)
                    }
                    try FileManager.default.moveItem(at: targetDir, to: finalTargetDir)
                } catch {
                    try? FileManager.default.removeItem(at: targetDir)
                    throw AddonServiceError.installFailed("Failed to rename addon directory.")
                }
            }
        }
    }

    // MARK: - Helpers

    private static func addonDescription(at path: String) -> String {
        guard let toc = try? FileManager.default.contentsOfDirectory(atPath: path).first(where: { $0.lowercased().hasSuffix(".toc") }) else {
            return "No description available"
        }
        let tocPath = (path as NSString).appendingPathComponent(toc)
        guard let content = try? String(contentsOfFile: tocPath, encoding: .utf8) else {
            return "No description available"
        }
        for line in content.split(separator: "\n") {
            if line.hasPrefix("## Notes:") {
                return line.replacingOccurrences(of: "## Notes:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return "No description available"
    }

    private static func gitRemoteURL(at path: String) -> String? {
        let configPath = (path as NSString).appendingPathComponent(".git/config")
        guard let content = try? String(contentsOfFile: configPath) else { return nil }
        let lines = content.split(separator: "\n")
        for (index, line) in lines.enumerated() where line.contains("[remote \"origin\"]") {
            if index + 1 < lines.count {
                let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if next.hasPrefix("url = ") {
                    return next.replacingOccurrences(of: "url = ", with: "")
                }
            }
        }
        return nil
    }

    private static func gitCommit(at path: String, ref: String) -> String? {
        let result = try? runGit(arguments: ["rev-parse", ref], at: path)
        guard let output = result, output.exitStatus == 0 else { return nil }
        return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstAvailableRemoteCommit(at path: String) -> String? {
        _ = try? runGit(arguments: ["fetch", "origin"], at: path)
        return gitCommit(at: path, ref: "origin/HEAD") ?? gitCommit(at: path, ref: "origin/main") ?? gitCommit(at: path, ref: "origin/master")
    }

    private struct GitResult {
        let stdout: String
        let stderr: String
        let exitStatus: Int32
    }

    private static func runGit(arguments: [String], at directory: String?) throws -> GitResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        if let directory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let combined = String(data: data, encoding: .utf8) ?? ""
        return GitResult(
            stdout: combined,
            stderr: combined,
            exitStatus: process.terminationStatus
        )
    }
}
