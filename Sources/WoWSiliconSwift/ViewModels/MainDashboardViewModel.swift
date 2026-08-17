import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class MainDashboardViewModel: ObservableObject {
    @Published private(set) var versionDisplayName: String = "WoWSilicon"
    @Published private(set) var subtitleText: String = "Launch World Of Warcraft from 2006-2010 on Apple Silicon Macs"

    @Published private(set) var gamePathStatus = StatusValue(text: "Not set", level: .error)

    @Published private(set) var gamePatchStatus = StatusValue(text: "Not Applied", level: .error)
    @Published private(set) var isGamePatched: Bool = false
    @Published private(set) var isGamePatchActionable: Bool = false
    @Published private(set) var isGameOperationInProgress: Bool = false
    @Published private(set) var isUnpatchingOperation: Bool = false
    @Published private(set) var patchFeedback: PatchFeedback?
    @Published private(set) var canLaunch: Bool = false
    @Published private(set) var currentVersionHasLauncher: Bool = false
    @Published private(set) var currentVersionWantsLauncher: Bool = false
    @Published private(set) var launcherPathStatus: StatusValue = StatusValue(text: "Not set", level: .error)
    @Published private(set) var currentVersionLauncherName: String = "Open Launcher"
    @Published private(set) var isLauncherLoading: Bool = false
    @Published private(set) var shouldShowVanillaTweaksPrompt: Bool = false
    @Published private(set) var shouldShowVersionMismatchPrompt: Bool = false
    @Published private(set) var versionMismatchData: (base: String, tweaked: String)?
    @Published var shouldShowMigrationPrompt: Bool = false
    @Published var shouldShowTelemetryConsentPrompt: Bool = false
    @Published private(set) var isApplyingVanillaTweaks: Bool = false
    @Published private(set) var isOptionAsAltBusy: Bool = false
    @Published private(set) var optionAsAltStatus: OptionAsAltStatus = .unknown
    @Published private(set) var isRetinaModeBusy: Bool = false
    @Published private(set) var retinaModeStatus: OptionAsAltStatus = .unknown
    @Published private(set) var isDependencyInstallInProgress: Bool = false
    @Published private(set) var visualCppRuntimeStatus: DependencyInstallStatus = .unknown
    @Published private(set) var isWineMonoInstallInProgress: Bool = false
    @Published private(set) var wineMonoStatus: DependencyInstallStatus = .unknown
    @Published private(set) var isGitInstallInProgress: Bool = false
    @Published private(set) var gitStatus: DependencyInstallStatus = .unknown
    @Published private(set) var currentVersion: GameVersion?
    @Published private(set) var supportsAddons: Bool = false
    @Published private(set) var supportsMods: Bool = false
    @Published private(set) var versions: [GameVersion] = []
    @Published private(set) var currentVersionID: String = VersionManager.defaultCurrentVersionID
    private let versionStore = VersionStore()
    private let prefsStore = UserPrefsStore()
    private let launchService = LaunchService.shared
    private var versionManager: VersionManager
    private var userPrefs: UserPrefs
    private var pendingVanillaTweaksLaunch = false
    private var optionsSessionInitialVanillaTweaksParameters: String?
    private var optionsSessionInitialVersionID: String?
    private var hasActiveOptionsSession = false
    private var patchStatusRefreshID = 0
    private var didRecordLaunchTelemetry = false
    static let allowedCursorSizeMultipliers = [1, 2, 4]

    private static func normalizedCursorSizeMultiplier(_ value: Int) -> Int {
        allowedCursorSizeMultipliers.contains(value) ? value : 1
    }
    
    static let preview = MainDashboardViewModel()

    init() {
        if MigrationService.legacyDirectoryExists() {
            shouldShowMigrationPrompt = true
        }

        let result = versionStore.loadVersionManager()
        versionManager = result.manager

        if !result.warnings.isEmpty {
            result.warnings.forEach { debugPrint("VersionStore warning: \($0)") }
        }

        userPrefs = prefsStore.load()
        normalizeTelemetryPrefs()
        TelemetryService.shared.setClientTelemetryEnabled(userPrefs.telemetryEnabled)

        // Don't persist defaults into WoWSilicon before the user decides whether to migrate,
        // as that would cause the destination files to already exist and block the file move.
        // Also don't persist if the decode failed — writing defaults would overwrite the real data.
        if !shouldShowMigrationPrompt && !result.decodeFailed {
            if userPrefs.autoDeleteWdb == false {
                userPrefs.autoDeleteWdb = true
                persistUserPrefs()
            }
            applyLegacyPrefsToVersion()
            persistVersionManager()
        }

        refreshSnapshot()
        updateTelemetryConsentPromptState()
        recordLaunchTelemetryIfNeeded()
        refreshOptionAsAltStatus()
        refreshRetinaModeStatus()
        refreshVisualCppRuntimeStatus()
        refreshWineMonoStatus()
        refreshGitStatus()
    }

    func selectVersion(id: String) {
        guard id != currentVersionID else { return }

        versionManager.setCurrentVersion(id: id)
        applyLegacyPrefsToVersion()
        persistVersionManager()
        refreshSnapshot()
        refreshOptionAsAltStatus()
        refreshRetinaModeStatus()
        refreshVisualCppRuntimeStatus()
        refreshWineMonoStatus()
        refreshGitStatus()
    }

    func addVersion(name: String, baseID: String, wantsLauncher: Bool) {
        guard let base = VersionManager.profileTemplates[baseID] else { return }
        let newID = UUID().uuidString
        var newVersion = base
        newVersion.id = newID
        newVersion.displayName = name
        newVersion.gamePath = ""
        newVersion.wantsLauncher = newVersion.isWorldOfWarcraft && wantsLauncher
        newVersion.launcherExePath = ""
        versionManager.versions[newID] = newVersion
        versionManager.setCurrentVersion(id: newID)
        persistVersionManager()
        refreshSnapshot()
        refreshOptionAsAltStatus()
        refreshRetinaModeStatus()
        refreshVisualCppRuntimeStatus()
        refreshGitStatus()
    }

    func removeVersion(id: String) {
        guard !VersionManager.defaultVersions.keys.contains(id) else { return }
        versionManager.versions.removeValue(forKey: id)
        if versionManager.currentVersionID == id {
            versionManager.currentVersionID = VersionManager.defaultCurrentVersionID
        }
        persistVersionManager()
        refreshSnapshot()
        refreshOptionAsAltStatus()
        refreshRetinaModeStatus()
        refreshVisualCppRuntimeStatus()
        refreshGitStatus()
    }


    func installLauncher() {
        guard let version = versionManager.currentVersion else { return }
        let panel = NSOpenPanel()
        panel.title = "Select Launcher Installer"
        panel.prompt = "Select"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "exe")].compactMap { $0 }
        panel.level = .modalPanel
        guard panel.runModal() == .OK, let installerURL = panel.url else { return }
        patchFeedback = nil
        launchService.launchInstaller(installerURL: installerURL, version: version) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success:
                    self.selectLauncherPath()
                case .failure(let error):
                    self.patchFeedback = PatchFeedback(title: "Installer Failed", message: error.localizedDescription, isError: true)
                }
            }
        }
    }

    func selectLauncherPath() {
        let panel = NSOpenPanel()
        panel.title = "Select Launcher Executable"
        panel.prompt = "Select"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "exe")].compactMap { $0 }
        panel.directoryURL = URL(fileURLWithPath: "\(NSHomeDirectory())/.wine/drive_c")
        panel.level = .modalPanel

        if panel.runModal() == .OK, let exeURL = panel.url {
            updateCurrentVersion { version in
                version.launcherExePath = exeURL.path
            }
        }
    }

    var canOpenLauncherDirectory: Bool {
        guard let path = versionManager.currentVersion?.launcherExePath
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return false
        }
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    var canClearLauncherPath: Bool {
        !(versionManager.currentVersion?.launcherExePath
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }

    func openLauncherDirectory() {
        guard canOpenLauncherDirectory,
              let path = versionManager.currentVersion?.launcherExePath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path).deletingLastPathComponent())
    }

    func clearLauncherPath() {
        guard canClearLauncherPath else { return }
        updateCurrentVersion { $0.launcherExePath = "" }
    }

    func launchThirdPartyLauncher() {
        guard let version = versionManager.currentVersion, version.hasLauncher else { return }
        patchFeedback = nil
        isLauncherLoading = true
        launchService.launchThirdPartyLauncher(version: version) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if case .failure(let error) = result {
                    self.isLauncherLoading = false
                    self.patchFeedback = PatchFeedback(title: "Launcher Failed", message: error.localizedDescription, isError: true)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                        self?.isLauncherLoading = false
                    }
                }
            }
        }
    }

    func forceQuitWine() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            LaunchService.forceQuitWine()
            DispatchQueue.main.async { self?.refreshSnapshot() }
        }
    }

    func selectGamePath() {
        let panel = NSOpenPanel()
        panel.title = "Select Game Executable"
        panel.prompt = "Choose"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "exe")].compactMap { $0 }
        panel.level = .modalPanel

        if panel.runModal() == .OK, let url = panel.url {
            updateCurrentVersion { version in
                version.gamePath = url.path
                version.executableName = url.lastPathComponent
            }
        }
    }

    var canOpenGameDirectory: Bool {
        guard let dirPath = versionManager.currentVersion?.gameDirectoryPath else {
            return false
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: dirPath, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    var canClearGamePath: Bool {
        !(versionManager.currentVersion?.gamePath
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }

    func openGameDirectory() {
        guard canOpenGameDirectory,
              let dirPath = versionManager.currentVersion?.gameDirectoryPath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: dirPath, isDirectory: true))
    }

    func clearGamePath() {
        guard canClearGamePath else { return }
        updateCurrentVersion { $0.gamePath = "" }
    }

    func beginOptionsSession() {
        optionsSessionInitialVersionID = versionManager.currentVersionID
        optionsSessionInitialVanillaTweaksParameters = versionManager.currentVersion?.settings.vanillaTweaksParameters
        hasActiveOptionsSession = true
    }

    func completeOptionsSession() {
        guard hasActiveOptionsSession else { return }
        hasActiveOptionsSession = false

        let initialVersionID = optionsSessionInitialVersionID
        let initialParameters = optionsSessionInitialVanillaTweaksParameters
        optionsSessionInitialVersionID = nil
        optionsSessionInitialVanillaTweaksParameters = nil

        guard let versionID = initialVersionID,
              versionManager.currentVersionID == versionID,
              let currentVersion = versionManager.currentVersion else {
            return
        }

        handleVanillaTweaksParametersChange(
            previousValue: initialParameters ?? "",
            currentValue: currentVersion.settings.vanillaTweaksParameters,
            version: currentVersion
        )
    }

    func handleMigration(migrate: Bool) {
        shouldShowMigrationPrompt = false
        if migrate {
            do {
                try MigrationService.migrate()
            } catch {
                debugPrint("Migration failed: \(error.localizedDescription)")
                patchFeedback = PatchFeedback(title: "Migration Failed", message: error.localizedDescription, isError: true)
            }
        }
        // Reload and persist regardless — either migrated data or defaults
        let result = versionStore.loadVersionManager()
        versionManager = result.manager
        userPrefs = prefsStore.load()
        normalizeTelemetryPrefs()
        TelemetryService.shared.setClientTelemetryEnabled(userPrefs.telemetryEnabled)
        if userPrefs.autoDeleteWdb == false {
            userPrefs.autoDeleteWdb = true
        }
        applyLegacyPrefsToVersion()
        persistVersionManager()
        persistUserPrefs()
        refreshSnapshot()
        updateTelemetryConsentPromptState()
        recordLaunchTelemetryIfNeeded()
        refreshOptionAsAltStatus()
        refreshRetinaModeStatus()
    }

    func launchGame() {
        guard canLaunch, let currentVersion = versionManager.currentVersion else {
            patchFeedback = PatchFeedback(title: "Cannot Launch", message: "Ensure the game path is set and the game patch is applied.", isError: true)
            return
        }

        patchFeedback = nil

        // Check for version mismatch if using vanilla tweaks
        if currentVersion.settings.enableVanillaTweaks {
            if let mismatch = launchService.checkVersionMismatch(for: currentVersion) {
                self.versionMismatchData = mismatch
                self.shouldShowVersionMismatchPrompt = true
                return
            }
        }

        launchService.processDidTerminate = { [weak self] in
            guard let self else { return }
            self.refreshSnapshot()
        }

        launchService.launch(version: currentVersion) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success:
                    self.recordWowStartTelemetry(for: currentVersion)
                    break
                case .failure(let error):
                    switch error {
                    case .vanillaTweaksMissing:
                        self.pendingVanillaTweaksLaunch = true
                        self.shouldShowVanillaTweaksPrompt = true
                    default:
                        self.patchFeedback = PatchFeedback(title: "Launch Failed", message: error.localizedDescription, isError: true)
                        self.refreshSnapshot()
                    }
                }
            }
        }
    }

    func handleVanillaTweaksConfirmation(apply: Bool) {
        shouldShowVanillaTweaksPrompt = false
        guard apply, pendingVanillaTweaksLaunch, let currentVersion = versionManager.currentVersion else {
            pendingVanillaTweaksLaunch = false
            return
        }

        isGameOperationInProgress = true
        isApplyingVanillaTweaks = true
        patchFeedback = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try VanillaTweaksService.applyTweaks(version: currentVersion)
                DispatchQueue.main.async {
                    self.pendingVanillaTweaksLaunch = false
                    self.isApplyingVanillaTweaks = false
                    self.isGameOperationInProgress = false
                    self.launchGame()
                }
            } catch {
                DispatchQueue.main.async {
                    self.pendingVanillaTweaksLaunch = false
                    self.isApplyingVanillaTweaks = false
                    self.isGameOperationInProgress = false
                    self.patchFeedback = PatchFeedback(title: "Vanilla Tweaks Failed", message: error.localizedDescription, isError: true)
                    self.refreshSnapshot()
                }
            }
        }
    }

    func handleVersionMismatchConfirmation(regenerate: Bool) {
        shouldShowVersionMismatchPrompt = false
        guard regenerate, let currentVersion = versionManager.currentVersion else {
            versionMismatchData = nil
            return
        }

        isGameOperationInProgress = true
        isApplyingVanillaTweaks = true
        patchFeedback = nil

        let gameURL = URL(fileURLWithPath: currentVersion.gamePath, isDirectory: true)
        let tweakedURL = gameURL.appendingPathComponent("WoW_tweaked.exe")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                if FileManager.default.fileExists(atPath: tweakedURL.path) {
                    try FileManager.default.removeItem(at: tweakedURL)
                }
                
                try VanillaTweaksService.applyTweaks(version: currentVersion)
                
                DispatchQueue.main.async {
                    self.isApplyingVanillaTweaks = false
                    self.isGameOperationInProgress = false
                    self.versionMismatchData = nil
                    self.launchGame()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isApplyingVanillaTweaks = false
                    self.isGameOperationInProgress = false
                    self.patchFeedback = PatchFeedback(title: "Re-generation Failed", message: error.localizedDescription, isError: true)
                    self.refreshSnapshot()
                    self.versionMismatchData = nil
                }
            }
        }
    }

    func boolBinding(_ keyPath: WritableKeyPath<VersionSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: {
                if let value = self.versionManager.currentVersion?.settings[keyPath: keyPath] {
                    return value
                }
                let fallback = VersionSettings()
                return fallback[keyPath: keyPath]
            },
            set: { newValue in
                self.updateCurrentVersion { version in
                    version.settings[keyPath: keyPath] = newValue
                }
            }
        )
    }

    func x87BackendBinding() -> Binding<X87Backend> {
        Binding(
            get: {
                self.versionManager.currentVersion?.settings.x87Backend ?? .rosettaX87
            },
            set: { newValue in
                self.updateCurrentVersion { version in
                    version.settings.x87Backend = newValue
                }
            }
        )
    }

    func graphicsSettingsBinding() -> Binding<GraphicsSettings> {
        Binding(
            get: {
                self.versionManager.currentVersion?.settings.graphicsSettings ?? GraphicsSettings()
            },
            set: { newValue in
                guard var version = self.versionManager.currentVersion else { return }
                var normalizedValue = newValue
                if normalizedValue.backend != .mtld3d {
                    normalizedValue.hdrEnabled = false
                }
                version.settings.graphicsSettings = normalizedValue
                self.updateCurrentVersion { current in current = version }
                guard version.supportsCustomGraphicsSettings else { return }
                let versionForWork = version
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try ConfigService.applyGraphicsSettings(for: versionForWork)
                    } catch {
                        DispatchQueue.main.async {
                            self.patchFeedback = PatchFeedback(title: "Graphics Settings", message: error.localizedDescription, isError: true)
                            self.refreshSnapshot()
                        }
                    }
                }
            }
        )
    }

    func enableOptionAsAlt() { setOptionAsAlt(true) }

    func disableOptionAsAlt() { setOptionAsAlt(false) }

    func enableRetinaMode() { setRetinaMode(true) }

    func disableRetinaMode() { setRetinaMode(false) }

    var canInstallDependencies: Bool {
        BundledWineRuntime.wineExecutableURL() != nil && !isDependencyInstallInProgress
    }

    func installVisualCppRuntime() {
        guard canInstallDependencies else { return }
        isDependencyInstallInProgress = true
        visualCppRuntimeStatus = .inProgress("Installing...")
        patchFeedback = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try DependencyService.installVisualCppRuntime()
                DispatchQueue.main.async {
                    self?.isDependencyInstallInProgress = false
                    self?.visualCppRuntimeStatus = DependencyService.isVisualCppRuntimeInstalled() ? .installed : .missing
                    self?.patchFeedback = PatchFeedback(title: "Dependencies", message: "Microsoft Visual C++ Runtime 2022 installed successfully.", isError: false)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isDependencyInstallInProgress = false
                    self?.visualCppRuntimeStatus = .error(error.localizedDescription)
                    self?.patchFeedback = PatchFeedback(title: "Dependencies Failed", message: error.localizedDescription, isError: true)
                    self?.refreshVisualCppRuntimeStatus()
                }
            }
        }
    }

    func refreshVisualCppRuntimeStatus() {
        guard !isDependencyInstallInProgress else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let installed = DependencyService.isVisualCppRuntimeInstalled()
            DispatchQueue.main.async {
                self?.visualCppRuntimeStatus = installed ? .installed : .missing
            }
        }
    }

    var canInstallWineMono: Bool {
        BundledWineRuntime.wineExecutableURL() != nil && !isWineMonoInstallInProgress
    }

    func installWineMono() {
        guard canInstallWineMono else { return }
        isWineMonoInstallInProgress = true
        wineMonoStatus = .inProgress("Waiting for installer...")
        patchFeedback = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try DependencyService.installWineMono()
                DispatchQueue.main.async {
                    self?.isWineMonoInstallInProgress = false
                    self?.wineMonoStatus = .installed
                    self?.patchFeedback = PatchFeedback(title: "Dependencies", message: "Wine Mono installed successfully.", isError: false)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isWineMonoInstallInProgress = false
                    self?.wineMonoStatus = .error(error.localizedDescription)
                    self?.patchFeedback = PatchFeedback(title: "Wine Mono Install Failed", message: error.localizedDescription, isError: true)
                    self?.refreshWineMonoStatus()
                }
            }
        }
    }

    func refreshWineMonoStatus() {
        guard !isWineMonoInstallInProgress else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let installed = DependencyService.isWineMonoInstalled()
            DispatchQueue.main.async {
                self?.wineMonoStatus = installed ? .installed : .missing
            }
        }
    }

    func installGit() {
        guard !isGitInstallInProgress else { return }

        isGitInstallInProgress = true
        gitStatus = .inProgress("Opening installer...")
        patchFeedback = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try DependencyService.installGit()
                DispatchQueue.main.async {
                    self?.isGitInstallInProgress = false
                    self?.gitStatus = DependencyService.isGitInstalled() ? .installed : .inProgress("Installer opened")
                    self?.patchFeedback = PatchFeedback(title: "Git", message: "Apple's Git installer has been opened. Finish the installation, then refresh the status.", isError: false)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isGitInstallInProgress = false
                    self?.gitStatus = .error(error.localizedDescription)
                    self?.patchFeedback = PatchFeedback(title: "Git Install Failed", message: error.localizedDescription, isError: true)
                    self?.refreshGitStatus()
                }
            }
        }
    }

    func refreshGitStatus() {
        guard !isGitInstallInProgress else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let installed = DependencyService.isGitInstalled()
            DispatchQueue.main.async {
                self?.gitStatus = installed ? .installed : .missing
            }
        }
    }

    private func setOptionAsAlt(_ enabled: Bool) {
        guard !isOptionAsAltBusy else { return }

        isOptionAsAltBusy = true
        optionAsAltStatus = .inProgress(enabled ? "Enabling…" : "Disabling…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try OptionAsAltService.setOptionAsAlt(enabled: enabled)
                let actual = OptionAsAltService.isOptionAsAltEnabled()
                DispatchQueue.main.async {
                    self.isOptionAsAltBusy = false
                    self.optionAsAltStatus = actual ? .enabled : .disabled
                    self.applyOptionAsAltState(enabled: actual)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isOptionAsAltBusy = false
                    self.optionAsAltStatus = .error(error.localizedDescription)
                    self.presentOptionAsAltDebugAlert(error: error)
                    self.patchFeedback = PatchFeedback(title: "Option-as-Alt", message: error.localizedDescription, isError: true)
                    self.refreshOptionAsAltStatus()
                }
            }
        }
    }

    func refreshOptionAsAltStatus() {
        guard !isOptionAsAltBusy else { return }
        let currentVersion = versionManager.currentVersion
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let enabled: Bool
            if currentVersion != nil {
                enabled = OptionAsAltService.isOptionAsAltEnabled()
            } else {
                enabled = OptionAsAltService.isOptionAsAltEnabledFast()
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.optionAsAltStatus = enabled ? .enabled : .disabled
                self.applyOptionAsAltState(enabled: enabled, persist: false)
            }
        }
    }

    private func setRetinaMode(_ enabled: Bool) {
        guard !isRetinaModeBusy else { return }

        isRetinaModeBusy = true
        retinaModeStatus = .inProgress(enabled ? "Enabling…" : "Disabling…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try RetinaModeService.setRetinaMode(enabled: enabled)
                let actual = RetinaModeService.isRetinaModeEnabled()
                DispatchQueue.main.async {
                    self.isRetinaModeBusy = false
                    self.retinaModeStatus = actual ? .enabled : .disabled
                }
            } catch {
                DispatchQueue.main.async {
                    self.isRetinaModeBusy = false
                    self.retinaModeStatus = .error(error.localizedDescription)
                    self.patchFeedback = PatchFeedback(title: "High Resolution Mode", message: error.localizedDescription, isError: true)
                    self.refreshRetinaModeStatus()
                }
            }
        }
    }

    func refreshRetinaModeStatus() {
        guard !isRetinaModeBusy else { return }
        let currentVersion = versionManager.currentVersion
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let enabled: Bool
            if currentVersion != nil {
                enabled = RetinaModeService.isRetinaModeEnabled()
            } else {
                enabled = RetinaModeService.isRetinaModeEnabledFast()
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.retinaModeStatus = enabled ? .enabled : .disabled
            }
        }
    }

    func refreshGraphicsSettings() {
        guard let version = versionManager.currentVersion,
              version.supportsCustomGraphicsSettings else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let gs = ConfigService.readGraphicsSettings(for: version)
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateCurrentVersion { current in
                    current.settings.graphicsSettings = gs
                }
            }
        }
    }

    func cursorSizeBinding() -> Binding<Int> {
        Binding(
            get: {
                if let value = self.versionManager.currentVersion?.settings.cursorSizeMultiplier {
                    return MainDashboardViewModel.normalizedCursorSizeMultiplier(value)
                }
                return MainDashboardViewModel.allowedCursorSizeMultipliers.first ?? 1
            },
            set: { newValue in
                let normalized = MainDashboardViewModel.normalizedCursorSizeMultiplier(newValue)
                guard let existing = self.versionManager.currentVersion else { return }
                var version = existing
                version.settings.cursorSizeMultiplier = normalized

                self.versionManager.updateCurrentVersion { current in
                    current.settings.cursorSizeMultiplier = normalized
                }

                self.currentVersion = version
                self.versions = self.versionManager.orderedVersions()
                self.persistVersionManager()

                self.applyCursorSizeMultiplier(for: version)
            }
        )
    }


    func stringBinding(_ keyPath: WritableKeyPath<VersionSettings, String>) -> Binding<String> {
        Binding(
            get: {
                if let value = self.versionManager.currentVersion?.settings[keyPath: keyPath] {
                    return value
                }
                let fallback = VersionSettings()
                return fallback[keyPath: keyPath]
            },
            set: { newValue in
                self.updateCurrentVersion { version in
                    version.settings[keyPath: keyPath] = newValue
                }
            }
        )
    }

    func telemetryEnabledBinding() -> Binding<Bool> {
        Binding(
            get: { self.userPrefs.telemetryEnabled },
            set: { enabled in
                self.setTelemetryEnabled(enabled, markConsentAsked: true)
            }
        )
    }

    func handleTelemetryConsent(accepted: Bool) {
        shouldShowTelemetryConsentPrompt = false
        setTelemetryEnabled(accepted, markConsentAsked: true)
    }

    var optionAsAltStatusText: String {
        switch optionAsAltStatus {
        case .unknown:
            return "Status: Unknown"
        case .enabled:
            return "Status: Enabled"
        case .disabled:
            return "Status: Disabled"
        case .inProgress(let message):
            return message
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var optionAsAltStatusColor: Color {
        switch optionAsAltStatus {
        case .enabled:
            return .green
        case .disabled, .unknown:
            return .secondary
        case .inProgress:
            return .accentColor
        case .error:
            return .red
        }
    }

    var retinaModeStatusText: String {
        switch retinaModeStatus {
        case .unknown:
            return "Status: Unknown"
        case .enabled:
            return "Status: Enabled"
        case .disabled:
            return "Status: Disabled"
        case .inProgress(let message):
            return message
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var retinaModeStatusColor: Color {
        switch retinaModeStatus {
        case .enabled:
            return .green
        case .disabled, .unknown:
            return .secondary
        case .inProgress:
            return .accentColor
        case .error:
            return .red
        }
    }

    var isVanillaTweaksSupported: Bool {
        versionManager.currentVersion?.supportsVanillaTweaks ?? false
    }

    func patchGame() {
        guard !isGameOperationInProgress, let version = versionManager.currentVersion else {
            return
        }

        isGameOperationInProgress = true
        isUnpatchingOperation = false
        var versionSnapshot = version

        let desiredLibState = versionSnapshot.libSiliconPatchSubdirectory != nil && !versionSnapshot.settings.userDisabledLibSiliconPatch
        if versionSnapshot.settings.enableLibSiliconPatch != desiredLibState {
            versionSnapshot.settings.enableLibSiliconPatch = desiredLibState
            updateCurrentVersion { current in
                current.settings.enableLibSiliconPatch = desiredLibState
            }
        }

        Task.detached { [weak self] in
            do {
                try PatchService.applyGamePatch(for: versionSnapshot)
                await self?.handlePatchCompletion(successTitle: "Game Patch", message: "Game patch applied successfully.")
            } catch {
                await self?.handlePatchError(error, title: "Game Patch Failed")
            }
        }
    }

    func unpatchGame() {
        guard !isGameOperationInProgress, let version = versionManager.currentVersion else {
            return
        }

        isGameOperationInProgress = true
        isUnpatchingOperation = true
        let versionSnapshot = version

        Task.detached { [weak self] in
            do {
                try PatchService.removeGamePatch(for: versionSnapshot)
                await self?.handlePatchCompletion(successTitle: "Game Unpatch", message: "Game unpatched successfully.")
            } catch {
                await self?.handlePatchError(error, title: "Game Unpatch Failed")
            }
        }
    }


    func clearPatchFeedback() {
        patchFeedback = nil
    }

    private func handlePatchCompletion(successTitle: String, message: String) async {
        await MainActor.run {
            isGameOperationInProgress = false
            isUnpatchingOperation = false
            refreshSnapshot()
            patchFeedback = PatchFeedback(title: successTitle, message: message, isError: false)
        }
    }

    private func handlePatchError(_ error: Error, title: String) async {
        await MainActor.run {
            isGameOperationInProgress = false
            isUnpatchingOperation = false
            refreshSnapshot()
            patchFeedback = PatchFeedback(title: title, message: error.localizedDescription, isError: true)
        }
    }

    private func refreshSnapshot() {
        guard var currentVersion = versionManager.currentVersion else {
            versionDisplayName = "WoWSilicon"
            subtitleText = "Launch World Of Warcraft from 2006-2010 on Apple Silicon Macs"
            supportsAddons = false
            supportsMods = false
            self.currentVersion = nil
            gamePathStatus = StatusValue(text: "Not set", level: .error)
            gamePatchStatus = StatusValue(text: "Not Applied", level: .error)
            versions = versionManager.orderedVersions()
            currentVersionID = versionManager.currentVersionID
            patchStatusRefreshID += 1
            isGamePatched = false
            isGamePatchActionable = false
            canLaunch = false
            currentVersionHasLauncher = false
            currentVersionWantsLauncher = false
            launcherPathStatus = StatusValue(text: "Not set", level: .error)
            currentVersionLauncherName = "Open Launcher"
            return
        }

        currentVersion = syncCursorSizeMultiplierFromConfig(for: currentVersion)

        versionDisplayName = currentVersion.displayName
        subtitleText = currentVersion.isWorldOfWarcraft
            ? "Launch World Of Warcraft from 2006-2010 on Apple Silicon Macs"
            : "Launch a 32-bit Direct3D 9 game on Apple Silicon"
        self.currentVersion = currentVersion
        supportsAddons = currentVersion.supportsAddons
        supportsMods = currentVersion.isWorldOfWarcraft && currentVersion.supportsDLLLoading
        versions = versionManager.orderedVersions()
        currentVersionID = versionManager.currentVersionID
        gamePathStatus = makePathStatus(for: currentVersion.gamePath)

        gamePatchStatus = StatusValue(text: "Checking...", level: .info)
        isGamePatched = false
        isGamePatchActionable = false
        canLaunch = false
        refreshPatchStatuses(for: currentVersion)

        if currentVersion.hasLauncher && !FileManager.default.fileExists(atPath: currentVersion.launcherExePath) {
            versionManager.updateCurrentVersion { $0.launcherExePath = "" }
            persistVersionManager()
            currentVersion.launcherExePath = ""
        }
        currentVersionHasLauncher = currentVersion.hasLauncher
        currentVersionWantsLauncher = currentVersion.wantsLauncher
        launcherPathStatus = makePathStatus(for: currentVersion.launcherExePath)
        currentVersionLauncherName = "Open Launcher"

        syncLegacyPrefs(from: currentVersion.settings)

        if !isOptionAsAltBusy {
            refreshOptionAsAltStatus()
        }
    }

    private func refreshPatchStatuses(for version: GameVersion) {
        patchStatusRefreshID += 1
        let refreshID = patchStatusRefreshID

        Task.detached { [version] in
            let gamePatchDescriptor = PatchingStatusChecker.evaluateGamePatch(for: version)

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.patchStatusRefreshID == refreshID else { return }
                guard self.currentVersion?.id == version.id else { return }

                self.gamePatchStatus = StatusValue(text: gamePatchDescriptor.text, level: gamePatchDescriptor.level)
                self.isGamePatched = gamePatchDescriptor.applied
                self.isGamePatchActionable = gamePatchDescriptor.actionable

                let gamePathReady = !version.gamePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                self.canLaunch = gamePathReady && gamePatchDescriptor.applied
            }
        }
    }

    private func updateCurrentVersion(_ perform: (inout GameVersion) -> Void) {
        versionManager.updateCurrentVersion(perform)
        persistVersionManager()
        refreshSnapshot()
    }

    private func applyLegacyPrefsToVersion() {
        versionManager.updateCurrentVersion { version in
            version.settings.showTerminalNormally = userPrefs.showTerminalNormally
            version.settings.enableMetalHud = userPrefs.enableMetalHud
            if version.supportsVanillaTweaks {
                version.settings.enableVanillaTweaks = userPrefs.enableVanillaTweaks
            } else {
                version.settings.enableVanillaTweaks = false
            }
            version.settings.autoDeleteWdb = version.isWorldOfWarcraft
            version.settings.remapOptionAsAlt = userPrefs.remapOptionAsAlt
            if !userPrefs.environmentVariables.isEmpty {
                version.settings.environmentVariables = userPrefs.environmentVariables
            }
            version.settings.vanillaTweaksParameters = userPrefs.vanillaTweaksParameters
            version.settings.x87Backend = userPrefs.x87Backend
            if version.libSiliconPatchSubdirectory != nil {
                if !version.settings.userDisabledLibSiliconPatch {
                    version.settings.enableLibSiliconPatch = true
                }
            } else {
                version.settings.enableLibSiliconPatch = false
            }
        }
    }

    private func applyOptionAsAltState(enabled: Bool, persist: Bool = true) {
        if let current = versionManager.currentVersion {
            var updated = current
            updated.settings.remapOptionAsAlt = enabled
            versionManager.versions[current.id] = updated
            currentVersion = updated
        }

        if userPrefs.remapOptionAsAlt != enabled {
            userPrefs.remapOptionAsAlt = enabled
            persistUserPrefs()
        }

        if persist {
            persistVersionManager()
        }
    }

    private func presentOptionAsAltDebugAlert(error: Error) {
        let detail: String
        if let optionError = error as? OptionAsAltServiceError {
            switch optionError {
            case .commandFailed(let output),
                 .registryWriteFailed(let output):
                detail = output
            case .wineMissing:
                detail = "Wine is not installed"
            }
        } else {
            detail = error.localizedDescription
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Option-as-Alt Debug"
        alert.informativeText = """
        \(detail)
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func applyCursorSizeMultiplier(for version: GameVersion) {
        guard version.supportsCustomGraphicsSettings else { return }
        let trimmedPath = version.gamePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }
        let multiplier = version.settings.cursorSizeMultiplier

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try DXVKConfigService.setCursorSizeMultiplier(gamePath: trimmedPath, multiplier: multiplier)
            } catch {
                DispatchQueue.main.async {
                    self?.patchFeedback = PatchFeedback(title: "Cursor Size", message: error.localizedDescription, isError: true)
                }
            }
        }
    }

    private func syncCursorSizeMultiplierFromConfig(for version: GameVersion) -> GameVersion {
        guard version.supportsCustomGraphicsSettings else { return version }
        var updated = version
        let trimmedPath = version.gamePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return version }

        let rawValue = DXVKConfigService.cursorSizeMultiplier(gamePath: trimmedPath) ?? 1
        let normalized = MainDashboardViewModel.normalizedCursorSizeMultiplier(rawValue)
        if updated.settings.cursorSizeMultiplier != normalized {
            updated.settings.cursorSizeMultiplier = normalized
            versionManager.versions[version.id] = updated
            persistVersionManager()
        }
        return updated
    }

    private func syncLegacyPrefs(from settings: VersionSettings) {
        var updated = userPrefs
        updated.showTerminalNormally = settings.showTerminalNormally
        updated.enableMetalHud = settings.enableMetalHud
        updated.enableVanillaTweaks = settings.enableVanillaTweaks
        updated.autoDeleteWdb = true
        updated.remapOptionAsAlt = settings.remapOptionAsAlt
        updated.telemetryEnabled = userPrefs.telemetryEnabled
        updated.telemetryConsentAsked = userPrefs.telemetryConsentAsked
        updated.telemetryInstallID = userPrefs.telemetryInstallID
        updated.environmentVariables = settings.environmentVariables
        updated.vanillaTweaksParameters = settings.vanillaTweaksParameters
        updated.x87Backend = settings.x87Backend

        if updated != userPrefs {
            userPrefs = updated
            persistUserPrefs()
        }
    }


    private func persistVersionManager() {
        do {
            try versionStore.save(manager: versionManager)
        } catch {
            debugPrint("Failed to save versions.json: \(error)")
        }
    }

    private func persistUserPrefs() {
        prefsStore.save(userPrefs)
    }

    private func normalizeTelemetryPrefs() {
        let trimmedID = userPrefs.telemetryInstallID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedID.isEmpty {
            userPrefs.telemetryInstallID = UUID().uuidString
        }
    }

    private func updateTelemetryConsentPromptState() {
        shouldShowTelemetryConsentPrompt = !shouldShowMigrationPrompt && !userPrefs.telemetryConsentAsked
    }

    private func setTelemetryEnabled(_ enabled: Bool, markConsentAsked: Bool) {
        userPrefs.telemetryEnabled = enabled
        TelemetryService.shared.setClientTelemetryEnabled(enabled)
        if markConsentAsked {
            userPrefs.telemetryConsentAsked = true
            shouldShowTelemetryConsentPrompt = false
        }
        normalizeTelemetryPrefs()
        persistUserPrefs()
        if enabled {
            recordLaunchTelemetryIfNeeded()
        }
    }

    private func recordLaunchTelemetryIfNeeded() {
        guard userPrefs.telemetryEnabled, !didRecordLaunchTelemetry else { return }
        didRecordLaunchTelemetry = true
        TelemetryService.shared.recordLaunch(
            prefs: userPrefs,
            context: TelemetryEventContext(version: versionManager.currentVersion)
        )
    }

    private func recordWowStartTelemetry(for version: GameVersion) {
        guard userPrefs.telemetryEnabled else { return }
        TelemetryService.shared.recordWowStart(
            prefs: userPrefs,
            context: TelemetryEventContext(version: version)
        )
    }

    private func handleVanillaTweaksParametersChange(previousValue: String, currentValue: String, version: GameVersion) {
        let trimmedPrevious = previousValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCurrent = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrevious != trimmedCurrent else { return }
        guard version.settings.enableVanillaTweaks else { return }

        let trimmedPath = version.gamePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        let tweakedURL = URL(fileURLWithPath: trimmedPath, isDirectory: true).appendingPathComponent("WoW_tweaked.exe")
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: tweakedURL.path) else { return }

        do {
            try fileManager.removeItem(at: tweakedURL)
        } catch {
            debugPrint("Failed to remove WoW_tweaked.exe after vanilla-tweaks parameters changed: \(error)")
        }
    }

    private func makePathStatus(for path: String) -> StatusValue {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return StatusValue(text: "Not set", level: .error)
        }
        let home = NSHomeDirectory()
        let display = trimmed.hasPrefix(home) ? "~" + trimmed.dropFirst(home.count) : trimmed
        return StatusValue(text: display, level: .success)
    }

    func makeTroubleshootingContext() -> TroubleshootingContext {
        let version = versionManager.currentVersion
        let trimmedGame = version?.gamePath.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return TroubleshootingContext(
            gamePath: trimmedGame.isEmpty ? nil : trimmedGame,
            currentVersion: version,
            isGamePatched: isGamePatched
        )
    }
}
