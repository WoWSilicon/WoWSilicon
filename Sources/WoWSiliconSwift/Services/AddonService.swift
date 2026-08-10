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
    let installedAddonNames: [String]
    let repositoryPath: String?
    let manifestPath: String?

    var isManagedRepository: Bool {
        repositoryPath != nil && manifestPath != nil
    }

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
        needsUpdate: Bool,
        installedAddonNames: [String] = [],
        repositoryPath: String? = nil,
        manifestPath: String? = nil
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
        self.installedAddonNames = installedAddonNames
        self.repositoryPath = repositoryPath
        self.manifestPath = manifestPath
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
    private static let repositoriesDirectoryName = ".wowsilicon-repositories"
    private static let manifestFileName = "manifest.json"

    private struct Paths {
        let addons: URL
        let repositories: URL
        let manifest: URL
    }

    private struct Manifest: Codable {
        var version = 1
        var repositories: [ManagedRepository] = []
    }

    private struct ManagedRepository: Codable {
        let id: String
        var name: String
        var remoteURL: String
        var directoryName: String
        var deployments: [Deployment]
    }

    private struct Deployment: Codable {
        enum Mode: String, Codable {
            case symbolicLink
            case copy
        }

        let name: String
        let sourceRelativePath: String
        let mode: Mode
    }

    struct AddonDirectory: Equatable {
        let name: String
        let url: URL
    }

    static func scanAddons(gamePath: String?, checkUpdates: Bool, progress: ((String) -> Void)?) throws -> [AddonInfo] {
        let paths = try paths(for: gamePath)
        let manifest = try loadManifest(at: paths.manifest)
        var addons: [AddonInfo] = []
        var managedAddonNames = Set<String>()

        for (index, repository) in manifest.repositories.enumerated() {
            progress?("Processing \(repository.name) (\(index + 1)/\(manifest.repositories.count))…")
            managedAddonNames.formUnion(repository.deployments.map { $0.name.lowercased() })

            let repositoryURL = paths.repositories.appendingPathComponent(repository.directoryName, isDirectory: true)
            guard FileManager.default.fileExists(atPath: repositoryURL.path) else { continue }

            let localCommit = gitCommit(at: repositoryURL.path, ref: "HEAD")
            let remoteCommit = checkUpdates ? firstAvailableRemoteCommit(at: repositoryURL.path) : nil
            let needsUpdate = checkUpdates && localCommit != nil && remoteCommit != nil && localCommit != remoteCommit
            let lastModified = (try? repositoryURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let installedNames = repository.deployments.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let description = managedDescription(repository: repository, repositoryURL: repositoryURL)

            addons.append(AddonInfo(
                id: repository.id,
                name: repository.name,
                path: repositoryURL.path,
                hasGitRepo: true,
                gitRemoteURL: gitRemoteURL(at: repositoryURL.path) ?? repository.remoteURL,
                lastUpdated: lastModified,
                description: description,
                localCommit: localCommit,
                remoteCommit: remoteCommit,
                needsUpdate: needsUpdate,
                installedAddonNames: installedNames,
                repositoryPath: repositoryURL.path,
                manifestPath: paths.manifest.path
            ))
        }

        let entries = try FileManager.default.contentsOfDirectory(
            at: paths.addons,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        )

        for (index, entry) in entries.enumerated() {
            guard !managedAddonNames.contains(entry.lastPathComponent.lowercased()) else { continue }
            let resourceValues = try entry.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues.isDirectory == true else { continue }

            progress?("Processing \(entry.lastPathComponent) (\(index + 1)/\(entries.count))…")
            let addonPath = entry.path
            let hasGitRepo = FileManager.default.fileExists(atPath: entry.appendingPathComponent(".git", isDirectory: true).path)
            let localCommit = hasGitRepo ? gitCommit(at: addonPath, ref: "HEAD") : nil
            let remoteCommit = hasGitRepo && checkUpdates ? firstAvailableRemoteCommit(at: addonPath) : nil
            let needsUpdate = hasGitRepo && checkUpdates && localCommit != nil && remoteCommit != nil && localCommit != remoteCommit
            let lastModified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast

            addons.append(AddonInfo(
                id: addonPath,
                name: entry.lastPathComponent,
                path: addonPath,
                hasGitRepo: hasGitRepo,
                gitRemoteURL: hasGitRepo ? gitRemoteURL(at: addonPath) : nil,
                lastUpdated: lastModified,
                description: addonDescription(at: addonPath),
                localCommit: localCommit,
                remoteCommit: remoteCommit,
                needsUpdate: needsUpdate
            ))
        }

        return addons.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func update(addon: AddonInfo) throws -> AddonInfo {
        guard addon.hasGitRepo else { throw AddonServiceError.gitFailed("Addon is not a git repository") }
        if addon.isManagedRepository {
            return try updateManagedRepository(addon)
        }

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
            description: addonDescription(at: addon.path),
            localCommit: localCommit,
            remoteCommit: remoteCommit,
            needsUpdate: localCommit != remoteCommit
        )
    }

    static func delete(addon: AddonInfo) throws {
        if addon.isManagedRepository {
            try deleteManagedRepository(addon)
            return
        }

        do {
            try FileManager.default.removeItem(atPath: addon.path)
        } catch {
            throw AddonServiceError.deleteFailed(error.localizedDescription)
        }
    }

    static func install(from urlString: String, gamePath: String?) throws {
        let paths = try paths(for: gamePath)
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let remoteURL = URL(string: trimmedURL),
              let scheme = remoteURL.scheme?.lowercased(),
              ["http", "https", "file"].contains(scheme) else {
            throw AddonServiceError.installFailed("Invalid repository URL")
        }

        var manifest = try loadManifest(at: paths.manifest)
        guard !manifest.repositories.contains(where: { normalizedRemoteURL($0.remoteURL) == normalizedRemoteURL(trimmedURL) }) else {
            throw AddonServiceError.installFailed("This repository is already installed.")
        }

        try FileManager.default.createDirectory(at: paths.repositories, withIntermediateDirectories: true)
        let repositoryName = repositoryName(from: remoteURL)
        let directoryName = uniqueRepositoryDirectoryName(repositoryName, in: paths.repositories)
        let repositoryURL = paths.repositories.appendingPathComponent(directoryName, isDirectory: true)

        let result = try runGit(arguments: ["clone", "--", trimmedURL, repositoryURL.path], at: nil)
        guard result.exitStatus == 0 else {
            try? FileManager.default.removeItem(at: repositoryURL)
            throw AddonServiceError.installFailed(result.stderr.isEmpty ? "git clone failed" : result.stderr)
        }

        do {
            let addonDirectories = try discoverAddonDirectories(in: repositoryURL)
            guard !addonDirectories.isEmpty else {
                throw AddonServiceError.installFailed("No installable addon folders were found. Each addon folder must contain a matching .toc file.")
            }

            let repositoryID = UUID().uuidString
            let deployments = try deploy(
                addonDirectories,
                from: repositoryURL,
                to: paths.addons,
                replacing: [],
                repositoryID: repositoryID,
                manifest: manifest
            )
            let repository = ManagedRepository(
                id: repositoryID,
                name: repositoryName,
                remoteURL: trimmedURL,
                directoryName: directoryName,
                deployments: deployments
            )
            manifest.repositories.append(repository)

            do {
                try saveManifest(manifest, at: paths.manifest)
            } catch {
                try? removeDeployments(deployments, from: paths.addons)
                throw error
            }
        } catch {
            try? FileManager.default.removeItem(at: repositoryURL)
            if let serviceError = error as? AddonServiceError { throw serviceError }
            throw AddonServiceError.installFailed(error.localizedDescription)
        }
    }

    static func discoverAddonDirectories(in repositoryURL: URL) throws -> [AddonDirectory] {
        var discovered: [AddonDirectory] = []
        try discoverAddonDirectories(in: repositoryURL, isRoot: true, discovered: &discovered)

        var names = Set<String>()
        for addon in discovered {
            guard names.insert(addon.name.lowercased()).inserted else {
                throw AddonServiceError.installFailed("The repository contains more than one addon named \(addon.name).")
            }
        }
        return discovered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func discoverAddonDirectories(
        in directory: URL,
        isRoot: Bool,
        discovered: inout [AddonDirectory]
    ) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let directoryName = directory.lastPathComponent
        let tocNames = contents
            .filter { $0.pathExtension.lowercased() == "toc" }
            .compactMap { normalizedAddonName(fromTOC: $0.deletingPathExtension().lastPathComponent) }
        let matchingName = tocNames.first { $0.caseInsensitiveCompare(directoryName) == .orderedSame }
        let addonName = matchingName ?? (isRoot ? tocNames.first : nil)

        if let addonName {
            discovered.append(AddonDirectory(name: addonName, url: directory))
            if !isRoot { return }
        }

        let ignoredDirectories = Set(["node_modules", "vendor", "build", "dist", "target"])
        for child in contents {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true,
                  !ignoredDirectories.contains(child.lastPathComponent.lowercased()) else { continue }
            try discoverAddonDirectories(in: child, isRoot: false, discovered: &discovered)
        }
    }

    private static func normalizedAddonName(fromTOC baseName: String) -> String? {
        let suffixes = [
            "-Classic", "_Classic", "-BCC", "_BCC", "-Vanilla", "_Vanilla",
            "-TBC", "_TBC", "-Mainline", "_Mainline", "-Wrath", "_Wrath",
            "-WOTLKC", "_WOTLKC"
        ]
        for suffix in suffixes where baseName.lowercased().hasSuffix(suffix.lowercased()) {
            return String(baseName.dropLast(suffix.count))
        }
        return baseName.isEmpty ? nil : baseName
    }

    private static func updateManagedRepository(_ addon: AddonInfo) throws -> AddonInfo {
        guard let repositoryPath = addon.repositoryPath,
              let manifestPath = addon.manifestPath else {
            throw AddonServiceError.gitFailed("Managed repository metadata is missing.")
        }
        let repositoryURL = URL(fileURLWithPath: repositoryPath, isDirectory: true)
        let manifestURL = URL(fileURLWithPath: manifestPath)
        let repositoriesURL = manifestURL.deletingLastPathComponent()
        let addonsURL = try addonsDirectory(in: repositoriesURL.deletingLastPathComponent())
        var manifest = try loadManifest(at: manifestURL)
        guard let index = manifest.repositories.firstIndex(where: { $0.id == addon.id }) else {
            throw AddonServiceError.gitFailed("Managed repository metadata was not found.")
        }

        let output = try runGit(arguments: ["pull", "--ff-only"], at: repositoryPath)
        guard output.exitStatus == 0 else {
            throw AddonServiceError.gitFailed(output.stderr)
        }

        let addonDirectories = try discoverAddonDirectories(in: repositoryURL)
        guard !addonDirectories.isEmpty else {
            throw AddonServiceError.installFailed("The updated repository no longer contains any installable addon folders.")
        }

        let oldDeployments = manifest.repositories[index].deployments
        let deployments = try deploy(
            addonDirectories,
            from: repositoryURL,
            to: addonsURL,
            replacing: oldDeployments,
            repositoryID: addon.id,
            manifest: manifest
        )
        manifest.repositories[index].deployments = deployments
        manifest.repositories[index].remoteURL = gitRemoteURL(at: repositoryPath) ?? manifest.repositories[index].remoteURL
        try saveManifest(manifest, at: manifestURL)

        let now = Date()
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: repositoryPath)
        let localCommit = gitCommit(at: repositoryPath, ref: "HEAD")
        let remoteCommit = firstAvailableRemoteCommit(at: repositoryPath)
        return AddonInfo(
            id: addon.id,
            name: addon.name,
            path: repositoryPath,
            hasGitRepo: true,
            gitRemoteURL: manifest.repositories[index].remoteURL,
            lastUpdated: now,
            description: managedDescription(repository: manifest.repositories[index], repositoryURL: repositoryURL),
            localCommit: localCommit,
            remoteCommit: remoteCommit,
            needsUpdate: localCommit != remoteCommit,
            installedAddonNames: deployments.map(\.name).sorted(),
            repositoryPath: repositoryPath,
            manifestPath: manifestPath
        )
    }

    private static func deleteManagedRepository(_ addon: AddonInfo) throws {
        guard let repositoryPath = addon.repositoryPath,
              let manifestPath = addon.manifestPath else {
            throw AddonServiceError.deleteFailed("Managed repository metadata is missing.")
        }
        let manifestURL = URL(fileURLWithPath: manifestPath)
        let addonsURL = try addonsDirectory(in: manifestURL.deletingLastPathComponent().deletingLastPathComponent())
        var manifest = try loadManifest(at: manifestURL)
        guard let index = manifest.repositories.firstIndex(where: { $0.id == addon.id }) else {
            throw AddonServiceError.deleteFailed("Managed repository metadata was not found.")
        }

        let repository = manifest.repositories[index]
        do {
            try removeDeployments(repository.deployments, from: addonsURL)
            try FileManager.default.removeItem(atPath: repositoryPath)
            manifest.repositories.remove(at: index)
            try saveManifest(manifest, at: manifestURL)
        } catch {
            throw AddonServiceError.deleteFailed(error.localizedDescription)
        }
    }

    private static func deploy(
        _ addons: [AddonDirectory],
        from repositoryURL: URL,
        to addonsURL: URL,
        replacing currentDeployments: [Deployment],
        repositoryID: String,
        manifest: Manifest
    ) throws -> [Deployment] {
        let fileManager = FileManager.default
        let otherManagedNames = Set(manifest.repositories
            .filter { $0.id != repositoryID }
            .flatMap(\.deployments)
            .map { $0.name.lowercased() })
        if let conflict = addons.first(where: { otherManagedNames.contains($0.name.lowercased()) }) {
            throw AddonServiceError.installFailed("\(conflict.name) is already managed by another repository.")
        }

        let stagingURL = addonsURL.appendingPathComponent(".wowsilicon-staging-\(UUID().uuidString)", isDirectory: true)
        let rollbackURL = addonsURL.appendingPathComponent(".wowsilicon-rollback-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rollbackURL, withIntermediateDirectories: true)

        var deployments: [Deployment] = []
        var installedDestinations: [URL] = []
        var rolledBackDestinations: [(original: URL, saved: URL)] = []
        var displacedDestinations: [(original: URL, backup: URL)] = []

        do {
            for addon in addons {
                let stagedURL = stagingURL.appendingPathComponent(addon.name, isDirectory: true)
                let mode: Deployment.Mode
                do {
                    try fileManager.createSymbolicLink(at: stagedURL, withDestinationURL: addon.url)
                    mode = .symbolicLink
                } catch {
                    try? fileManager.removeItem(at: stagedURL)
                    try fileManager.copyItem(at: addon.url, to: stagedURL)
                    mode = .copy
                }
                let relativePath = relativePath(of: addon.url, from: repositoryURL)
                deployments.append(Deployment(name: addon.name, sourceRelativePath: relativePath, mode: mode))
            }

            for deployment in currentDeployments {
                let destination = addonsURL.appendingPathComponent(deployment.name, isDirectory: true)
                guard itemExists(at: destination) else { continue }
                let saved = rollbackURL.appendingPathComponent(deployment.name, isDirectory: true)
                try fileManager.moveItem(at: destination, to: saved)
                rolledBackDestinations.append((destination, saved))
            }

            let currentNames = Set(currentDeployments.map { $0.name.lowercased() })
            for deployment in deployments {
                let destination = addonsURL.appendingPathComponent(deployment.name, isDirectory: true)
                if itemExists(at: destination),
                   !currentNames.contains(deployment.name.lowercased()) {
                    let backup = nextBackupURL(for: destination)
                    try fileManager.moveItem(at: destination, to: backup)
                    displacedDestinations.append((destination, backup))
                }
                let staged = stagingURL.appendingPathComponent(deployment.name, isDirectory: true)
                try fileManager.moveItem(at: staged, to: destination)
                installedDestinations.append(destination)
            }

            try? fileManager.removeItem(at: stagingURL)
            try? fileManager.removeItem(at: rollbackURL)
            return deployments
        } catch {
            for destination in installedDestinations.reversed() {
                try? fileManager.removeItem(at: destination)
            }
            for item in rolledBackDestinations.reversed() {
                try? fileManager.moveItem(at: item.saved, to: item.original)
            }
            for item in displacedDestinations.reversed() {
                try? fileManager.moveItem(at: item.backup, to: item.original)
            }
            try? fileManager.removeItem(at: stagingURL)
            try? fileManager.removeItem(at: rollbackURL)
            throw error
        }
    }

    private static func removeDeployments(_ deployments: [Deployment], from addonsURL: URL) throws {
        for deployment in deployments {
            let destination = addonsURL.appendingPathComponent(deployment.name, isDirectory: true)
            if itemExists(at: destination) {
                try FileManager.default.removeItem(at: destination)
            }
        }
    }

    private static func nextBackupURL(for destination: URL) -> URL {
        var index = 0
        var candidate = destination.deletingLastPathComponent().appendingPathComponent("\(destination.lastPathComponent).bak", isDirectory: true)
        while itemExists(at: candidate) {
            index += 1
            candidate = destination.deletingLastPathComponent().appendingPathComponent("\(destination.lastPathComponent).bak.\(index)", isDirectory: true)
        }
        return candidate
    }

    private static func managedDescription(repository: ManagedRepository, repositoryURL: URL) -> String {
        let names = repository.deployments.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if names.count > 1 {
            return "Includes \(names.joined(separator: ", "))"
        }
        if let deployment = repository.deployments.first {
            let addonURL = repositoryURL.appendingPathComponent(deployment.sourceRelativePath, isDirectory: true)
            return addonDescription(at: addonURL.path)
        }
        return "No description available"
    }

    private static func paths(for gamePath: String?) throws -> Paths {
        guard let gamePath = gamePath?.trimmingCharacters(in: .whitespacesAndNewlines), !gamePath.isEmpty else {
            throw AddonServiceError.gamePathMissing
        }
        let url = URL(fileURLWithPath: gamePath)
        var isDir: ObjCBool = false
        let gameDirURL: URL
        if FileManager.default.fileExists(atPath: gamePath, isDirectory: &isDir) {
            gameDirURL = isDir.boolValue ? url : url.deletingLastPathComponent()
        } else if url.pathExtension.lowercased() == "exe" {
            gameDirURL = url.deletingLastPathComponent()
        } else {
            gameDirURL = url
        }
        let interfaceURL = gameDirURL.appendingPathComponent("Interface", isDirectory: true)
        let addonsURL = try addonsDirectory(in: interfaceURL)
        let repositoriesURL = interfaceURL.appendingPathComponent(repositoriesDirectoryName, isDirectory: true)
        return Paths(
            addons: addonsURL,
            repositories: repositoriesURL,
            manifest: repositoriesURL.appendingPathComponent(manifestFileName)
        )
    }

    private static func addonsDirectory(in interfaceURL: URL) throws -> URL {
        let expectedURL = interfaceURL.appendingPathComponent("AddOns", isDirectory: true)
        let entries = try? FileManager.default.contentsOfDirectory(
            at: interfaceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        if let match = entries?.first(where: { entry in
            guard entry.lastPathComponent.caseInsensitiveCompare("AddOns") == .orderedSame else { return false }
            return (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }) {
            return match
        }
        throw AddonServiceError.addonsDirectoryMissing(expectedURL.path)
    }

    private static func itemExists(at url: URL) -> Bool {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        return (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static func loadManifest(at url: URL) throws -> Manifest {
        guard FileManager.default.fileExists(atPath: url.path) else { return Manifest() }
        do {
            return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        } catch {
            throw AddonServiceError.installFailed("The addon repository manifest could not be read: \(error.localizedDescription)")
        }
    }

    private static func saveManifest(_ manifest: Manifest, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }

    private static func repositoryName(from url: URL) -> String {
        let component = url.deletingPathExtension().lastPathComponent
        return component.isEmpty ? "AddonRepository" : component
    }

    private static func uniqueRepositoryDirectoryName(_ name: String, in directory: URL) -> String {
        let safeName = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        var candidate = safeName
        var index = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            index += 1
            candidate = "\(safeName)-\(index)"
        }
        return candidate
    }

    private static func relativePath(of url: URL, from root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        return components.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private static func normalizedRemoteURL(_ url: String) -> String {
        var normalized = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.lowercased().hasSuffix(".git") {
            normalized.removeLast(4)
        }
        return normalized.lowercased()
    }

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
        let result = try? runGit(arguments: ["config", "--get", "remote.origin.url"], at: path)
        guard let result, result.exitStatus == 0 else { return nil }
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func gitCommit(at path: String, ref: String) -> String? {
        let result = try? runGit(arguments: ["rev-parse", ref], at: path)
        guard let output = result, output.exitStatus == 0 else { return nil }
        return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstAvailableRemoteCommit(at path: String) -> String? {
        _ = try? runGit(arguments: ["fetch", "origin"], at: path)
        return gitCommit(at: path, ref: "@{upstream}")
            ?? gitCommit(at: path, ref: "origin/HEAD")
            ?? gitCommit(at: path, ref: "origin/main")
            ?? gitCommit(at: path, ref: "origin/master")
    }

    private struct GitResult {
        let stdout: String
        let stderr: String
        let exitStatus: Int32
    }

    private static func runGit(arguments: [String], at directory: String?) throws -> GitResult {
        guard let gitURL = DependencyService.gitExecutableURL() else {
            throw AddonServiceError.gitFailed("Git is not installed.")
        }
        let result = try ProcessRunner.run(
            executablePath: gitURL.path,
            arguments: arguments,
            currentDirectory: directory.map { URL(fileURLWithPath: $0) },
            timeout: 120
        )
        return GitResult(stdout: result.stdout, stderr: result.stderr, exitStatus: result.exitCode)
    }
}
