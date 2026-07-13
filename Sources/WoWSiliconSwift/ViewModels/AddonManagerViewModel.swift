import Foundation
import AppKit

@MainActor
final class AddonManagerViewModel: ObservableObject, Identifiable {
    let id = UUID()

    enum Status {
        case idle
        case loading(String)
        case ready
        case error(String)
    }

    struct InstallProgress {
        let current: Int
        let total: Int
    }

    @Published var addons: [AddonInfo] = []
    @Published var status: Status = .idle
    @Published var showOnlyGit = false
    @Published var isPerformingAction = false
    @Published var multiInstallProgress: InstallProgress?
    @Published var alert: ManagerAlert?

    private let gamePath: String?
    private var didPromptForGit = false

    init(gamePath: String?) {
        self.gamePath = gamePath
    }

    var canOpenAddonsDirectory: Bool {
        guard let directory = addonsDirectoryURL else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    func openAddonsDirectory() {
        guard canOpenAddonsDirectory, let directory = addonsDirectoryURL else { return }
        NSWorkspace.shared.open(directory)
    }

    private var addonsDirectoryURL: URL? {
        guard let path = gamePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("Interface", isDirectory: true)
            .appendingPathComponent("AddOns", isDirectory: true)
    }

    func promptToInstallGitIfMissing() {
        _ = ensureGitAvailableOrPrompt(force: false)
    }

    private func ensureGitAvailableOrPrompt(force: Bool) -> Bool {
        if DependencyService.isGitInstalled() {
            return true
        }
        if !force && didPromptForGit {
            return false
        }
        didPromptForGit = true

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Git is required for addon management"
        alert.informativeText = "WoWSilicon uses Git to install, check, and update addon repositories. Install Apple's Command Line Tools to add Git to this Mac."
        alert.addButton(withTitle: "Install Git")
        alert.addButton(withTitle: "Not Now")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }

        launchGitInstaller()
        return false
    }

    private func launchGitInstaller() {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        Task.detached { [weak self] in
            do {
                try DependencyService.installGit()
                await MainActor.run { [weak self] in
                    self?.isPerformingAction = false
                    self?.alert = ManagerAlert(message: "Apple's Git installer has been opened. Finish the installation, then reopen or refresh the Addon Manager.")
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isPerformingAction = false
                    self?.alert = ManagerAlert(message: error.localizedDescription)
                }
            }
        }
    }

    func refresh(checkUpdates: Bool = false) {
        status = .loading("Scanning addons…")
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let addons = try AddonService.scanAddons(gamePath: self.gamePath, checkUpdates: checkUpdates) { message in
                    Task { @MainActor in
                        self.status = .loading(message)
                    }
                }
                Task { @MainActor in
                    self.addons = addons
                    self.status = .ready
                }
            } catch {
                Task { @MainActor in
                    self.addons = []
                    self.status = .error(error.localizedDescription)
                }
            }
        }
    }

    func install(from url: String) {
        guard ensureGitAvailableOrPrompt(force: true) else { return }

        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingURLs = Set(addons.compactMap { $0.gitRemoteURL })
        if existingURLs.contains(trimmedURL) {
            alert = ManagerAlert(message: "Addon is already installed.")
            return
        }

        guard !isPerformingAction else { return }
        isPerformingAction = true
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                try AddonService.install(from: url, gamePath: self.gamePath)
                Task { @MainActor in
                    self.isPerformingAction = false
                    self.alert = ManagerAlert(message: "Addon installed successfully.")
                    self.refresh()
                }
            } catch {
                Task { @MainActor in
                    self.isPerformingAction = false
                    self.alert = ManagerAlert(message: error.localizedDescription)
                }
            }
        }
    }

    func installMultiple(from text: String) {
        guard ensureGitAvailableOrPrompt(force: true) else { return }

        let rawUrls = text
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rawUrls.isEmpty else {
            alert = ManagerAlert(message: "Enter at least one repository URL.")
            return
        }

        let existingURLs = Set(addons.compactMap { $0.gitRemoteURL })
        let urlsToInstall = rawUrls.filter { !existingURLs.contains($0) }

        guard !urlsToInstall.isEmpty else {
            alert = ManagerAlert(message: "All provided addons are already installed.")
            return
        }

        guard !isPerformingAction else { return }
        isPerformingAction = true
        self.multiInstallProgress = InstallProgress(current: 0, total: urlsToInstall.count)

        Task.detached { [weak self] in
            guard let self else { return }
            var successes = 0
            var failures: [String] = []
            var current = 0

            for url in urlsToInstall {
                do {
                    try AddonService.install(from: url, gamePath: self.gamePath)
                    successes += 1
                } catch {
                    failures.append("\(url): \(error.localizedDescription)")
                }
                current += 1
                let updatedCurrent = current
                Task { @MainActor in
                    self.multiInstallProgress = InstallProgress(current: updatedCurrent, total: urlsToInstall.count)
                }
            }

            Task { @MainActor in
                self.isPerformingAction = false
                self.multiInstallProgress = nil
                if successes > 0 {
                    self.refresh()
                }

                if !failures.isEmpty {
                    let message = """
                    Installed \(successes) addon\(successes == 1 ? "" : "s").
                    Failed: \(failures.count)
                    \(failures.joined(separator: "\n"))
                    """
                    self.alert = ManagerAlert(message: message)
                } else {
                    self.alert = ManagerAlert(message: "Installed \(successes) addon\(successes == 1 ? "" : "s").")
                }
            }
        }
    }

    func update(addon: AddonInfo) {
        guard ensureGitAvailableOrPrompt(force: true) else { return }
        guard !isPerformingAction else { return }
        isPerformingAction = true
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let updated = try AddonService.update(addon: addon)
                Task { @MainActor in
                    if let index = self.addons.firstIndex(of: addon) {
                        self.addons[index] = updated
                    }
                    self.isPerformingAction = false
                    self.alert = ManagerAlert(message: "\(addon.name) updated.")
                    self.refresh(checkUpdates: true)
                }
            } catch {
                Task { @MainActor in
                    self.isPerformingAction = false
                    self.alert = ManagerAlert(message: error.localizedDescription)
                }
            }
        }
    }

    func delete(addon: AddonInfo) {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                try AddonService.delete(addon: addon)
                Task { @MainActor in
                    self.addons.removeAll { $0 == addon }
                    self.isPerformingAction = false
                }
            } catch {
                Task { @MainActor in
                    self.isPerformingAction = false
                    self.alert = ManagerAlert(message: error.localizedDescription)
                }
            }
        }
    }

    var filteredAddons: [AddonInfo] {
        let list = showOnlyGit ? addons.filter { $0.hasGitRepo } : addons
        return list.sorted { a, b in
            if a.needsUpdate != b.needsUpdate {
                return a.needsUpdate
            }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    var installedAddonCount: Int {
        addons.reduce(0) { count, addon in
            count + (addon.isManagedRepository ? addon.installedAddonNames.count : 1)
        }
    }

    var gitRepositoryCount: Int {
        addons.filter(\.hasGitRepo).count
    }

    func updateAll() {
        guard ensureGitAvailableOrPrompt(force: true) else { return }
        let gitAddons = filteredAddons.filter { $0.hasGitRepo && $0.needsUpdate }
        guard !gitAddons.isEmpty else {
            alert = ManagerAlert(message: "No git addons need updates.")
            return
        }
        guard !isPerformingAction else { return }
        isPerformingAction = true
        Task.detached { [weak self, gitAddons] in
            guard let self else { return }
            var updated = 0
            var failed = 0
            for addon in gitAddons {
                do {
                    _ = try AddonService.update(addon: addon)
                    updated += 1
                } catch {
                    failed += 1
                }
            }

            Task { @MainActor in
                self.isPerformingAction = false
                self.refresh(checkUpdates: true)
                if updated == 0 && failed == 0 {
                    self.alert = ManagerAlert(message: "No git addons need updates.")
                } else if failed == 0 {
                    self.alert = ManagerAlert(message: "Updated \(updated) addon\(updated == 1 ? "" : "s").")
                } else {
                    self.alert = ManagerAlert(message: "Updated \(updated) addon\(updated == 1 ? "" : "s"), \(failed) failed.")
                }
            }
        }
    }
}
