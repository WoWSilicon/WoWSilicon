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
    @Published private(set) var wineProcessCount: Int = 0
    @Published private(set) var isForceQuittingWine: Bool = false
    @Published private(set) var isCheckingWineProcesses: Bool = false
    @Published private(set) var shouldShowVanillaTweaksPrompt: Bool = false
    @Published private(set) var shouldShowVersionMismatchPrompt: Bool = false
    @Published private(set) var shouldShowExistingWinePrompt: Bool = false
    @Published private(set) var versionMismatchData: (base: String, tweaked: String)?
    @Published var shouldShowMigrationPrompt: Bool = false
    @Published var shouldShowWineBottleMigrationPrompt: Bool = false
    @Published var shouldShowTelemetryConsentPrompt: Bool = false
    @Published private(set) var wineBottlePath: String = ""
    @Published private(set) var audioOutputDevices: [WineAudioOutputDevice] = []
    @Published private(set) var audioInputDevices: [WineAudioOutputDevice] = []
    @Published private(set) var audioDetails: WineAudioDetails?
    @Published private(set) var isAudioOutputBusy: Bool = false
    @Published private(set) var isWineConfigurationLoading: Bool = false
    @Published private(set) var isWineTerminalLoading: Bool = false
    @Published private(set) var isShortcutExportInProgress: Bool = false
    @Published private(set) var shortcutExportFeedback: PatchFeedback?
    @Published private(set) var isApplyingVanillaTweaks: Bool = false
    @Published private(set) var isOptionAsAltBusy: Bool = false
    @Published private(set) var optionAsAltStatus: OptionAsAltStatus = .unknown
    @Published private(set) var isRetinaModeBusy: Bool = false
    @Published private(set) var retinaModeStatus: OptionAsAltStatus = .unknown
    @Published var shouldShowRosettaInstallPrompt: Bool = false
    @Published private(set) var currentVersion: GameVersion?
    @Published private(set) var supportsAddons: Bool = false
    @Published private(set) var supportsMods: Bool = false
    @Published private(set) var versions: [GameVersion] = []
    @Published private(set) var currentVersionID: String = VersionManager.defaultCurrentVersionID
    private let versionStore = VersionStore()
    private let prefsStore = UserPrefsStore()
    private let launchService = LaunchService.shared
    private let gameLaunchCoordinator = GameLaunchCoordinator()
    let dependencies = DependencyStatusViewModel()
    let wineMigration = WineMigrationViewModel()
    private var versionManager: VersionManager
    private var userPrefs: UserPrefs
    private var pendingVanillaTweaksLaunch = false
    private var launchTask: Task<Void, Never>?
    private var optionsSessionInitialVanillaTweaksParameters: String?
    private var optionsSessionInitialVersionID: String?
    private var hasActiveOptionsSession = false
    private var patchStatusRefreshID = 0
    private var optionAsAltStatusRefreshID = 0
    private var retinaModeStatusRefreshID = 0
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
        let telemetryPrefsChanged = normalizeTelemetryPrefs()
        wineBottlePath = WineBottleService.currentBottleURL(prefs: userPrefs).path
        let wineBottlePrefsChanged = updateWineBottleMigrationPromptState()
        if telemetryPrefsChanged || wineBottlePrefsChanged {
            persistUserPrefs()
        }
        TelemetryService.shared.setClientTelemetryEnabled(userPrefs.telemetryEnabled)

        if !shouldShowMigrationPrompt && !result.decodeFailed {
            if result.requiresLegacyPrefsMigration {
                migrateLegacyPrefsToCurrentVersion()
                persistVersionManager()
            }
        }

        refreshSnapshot()
        updateTelemetryConsentPromptState()
        recordLaunchTelemetryIfNeeded()
    }

    func selectVersion(id: String) {
        guard id != currentVersionID else { return }

        versionManager.setCurrentVersion(id: id)
        persistVersionManager()
        refreshSnapshot()
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
    }

    func removeVersion(id: String) {
        guard !VersionManager.defaultVersions.keys.contains(id) else { return }
        versionManager.versions.removeValue(forKey: id)
        if versionManager.currentVersionID == id {
            versionManager.currentVersionID = VersionManager.defaultCurrentVersionID
        }
        persistVersionManager()
        refreshSnapshot()
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
                    self.selectLauncherPath(showInstallationGuidance: true)
                case .failure(let error):
                    self.patchFeedback = PatchFeedback(title: "Installer Failed", message: error.localizedDescription, isError: true)
                }
            }
        }
    }

    func selectLauncherPath() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Choose an Installed Launcher"
        alert.informativeText = "Launcher Path is for the actual installed launcher .exe, not the installer file. If the launcher is not installed yet, use Install Launcher first."
        alert.addButton(withTitle: "Choose Installed Launcher…")
        alert.addButton(withTitle: "Install Launcher…")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            selectLauncherPath(showInstallationGuidance: false)
        case .alertSecondButtonReturn:
            installLauncher()
        default:
            break
        }
    }

    private func selectLauncherPath(showInstallationGuidance: Bool) {
        let panel = NSOpenPanel()
        panel.title = showInstallationGuidance
            ? "Select the Installed Launcher"
            : "Select Launcher Executable"
        panel.prompt = "Use Launcher"
        if showInstallationGuidance {
            panel.message = "The installation is finished. Select the launcher's .exe file to complete setup. It is usually inside Program Files or Program Files (x86)."
        }
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "exe")].compactMap { $0 }
        panel.directoryURL = WineRegistrySupport.winePrefixURL()
            .appendingPathComponent("drive_c", isDirectory: true)
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try AudioOutputService.applySavedDevices(
                    outputID: version.settings.audioOutputDeviceID,
                    inputID: version.settings.audioInputDeviceID,
                    customVariables: version.settings.environmentVariables
                )
                DispatchQueue.main.async {
                    self?.launchPreparedThirdPartyLauncher(version)
                }
            } catch {
                DispatchQueue.main.async {
                    debugPrint("Could not apply the saved Wine audio output: \(error.localizedDescription)")
                    self?.launchPreparedThirdPartyLauncher(version)
                }
            }
        }
    }

    private func launchPreparedThirdPartyLauncher(_ version: GameVersion) {
        launchService.launchThirdPartyLauncher(version: version) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if case .failure(let error) = result {
                    self.isLauncherLoading = false
                    self.patchFeedback = PatchFeedback(
                        title: "Launcher Failed",
                        message: error.localizedDescription,
                        isError: true
                    )
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                        self?.isLauncherLoading = false
                    }
                }
            }
        }
    }

    func forceQuitWine() {
        forceQuitWine(launchAfter: nil)
    }

    private func forceQuitWine(launchAfter version: GameVersion?) {
        guard !isForceQuittingWine else { return }
        isForceQuittingWine = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            LaunchService.forceQuitWine()
            let remainingProcessCount = WineProcessMonitor.waitForApplicationProcessExit()
            DispatchQueue.main.async {
                self?.isForceQuittingWine = false
                if let remainingProcessCount {
                    self?.wineProcessCount = remainingProcessCount
                }
                self?.refreshSnapshot()
                if let version {
                    self?.continueLaunch(version)
                }
            }
        }
    }

    func monitorWineProcesses() async {
        while !Task.isCancelled {
            let processCount = await Task.detached(priority: .utility) {
                WineProcessMonitor.currentApplicationProcessCount()
            }.value

            if !isForceQuittingWine, !isAudioOutputBusy, let processCount {
                wineProcessCount = processCount
                TelemetryService.shared.updateGameRunning(processCount > 0)
            }

            let interval = Self.wineProcessPollingIntervalSeconds(
                processCount: processCount ?? wineProcessCount,
                isLaunchOrShutdownActive: isWineProcessPollingActive
            )
            for _ in 0..<interval {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                if isWineProcessPollingActive && interval > 1 {
                    break
                }
            }
        }
    }

    static func wineProcessPollingIntervalSeconds(
        processCount: Int,
        isLaunchOrShutdownActive: Bool
    ) -> Int {
        if isLaunchOrShutdownActive {
            return 1
        }
        return processCount > 0 ? 2 : 10
    }

    private var isWineProcessPollingActive: Bool {
        isGameOperationInProgress
            || isCheckingWineProcesses
            || isForceQuittingWine
            || isLauncherLoading
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
            setGamePath(url)
        }
    }

    func setGamePath(_ url: URL) {
        updateCurrentVersion { version in
            version.gamePath = url.path
            version.executableName = url.lastPathComponent
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
        guard !hasActiveOptionsSession else { return }

        optionsSessionInitialVersionID = versionManager.currentVersionID
        optionsSessionInitialVanillaTweaksParameters = versionManager.currentVersion?.settings.vanillaTweaksParameters
        hasActiveOptionsSession = true

        refreshOptionAsAltStatus()
        refreshRetinaModeStatus()
        refreshGraphicsSettings()
        refreshVisualCppRuntimeStatus()
        refreshWineMonoStatus()
        refreshGitStatus()
        refreshRosettaStatus(promptIfMissing: true)
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
        wineBottlePath = WineBottleService.currentBottleURL(prefs: userPrefs).path
        TelemetryService.shared.setClientTelemetryEnabled(userPrefs.telemetryEnabled)
        migrateLegacyPrefsToCurrentVersion()
        persistVersionManager()
        refreshSnapshot()
        updateTelemetryConsentPromptState()
        recordLaunchTelemetryIfNeeded()
        refreshOptionAsAltStatus()
        refreshRetinaModeStatus()
        updateWineBottleMigrationPromptState()
        persistUserPrefs()
        updateTelemetryConsentPromptState()
        startWineProfileMigrationIfNeeded()
    }

    func startWineProfileMigrationIfNeeded() {
        let bottleURL = WineBottleService.currentBottleURL(prefs: userPrefs)
        let blocked = shouldShowMigrationPrompt || shouldShowWineBottleMigrationPrompt
        let task = wineMigration.startProfileMigration(
            bottleURL: bottleURL,
            blocked: blocked,
            completion: handleWineProfileMigrationOutcome
        )
        if task != nil {
            shouldShowTelemetryConsentPrompt = false
        }
    }

    func retryWineProfileMigration() {
        let bottleURL = WineBottleService.currentBottleURL(prefs: userPrefs)
        let blocked = shouldShowMigrationPrompt || shouldShowWineBottleMigrationPrompt
        let task = wineMigration.retryProfileMigration(
            bottleURL: bottleURL,
            blocked: blocked,
            completion: handleWineProfileMigrationOutcome
        )
        if task != nil {
            shouldShowTelemetryConsentPrompt = false
        }
    }

    func handleWineBottleMigration(copyLegacyBottle: Bool) {
        shouldShowWineBottleMigrationPrompt = false
        guard copyLegacyBottle else {
            userPrefs.wineBottleMigrationAsked = true
            persistUserPrefs()
            updateTelemetryConsentPromptState()
            startWineProfileMigrationIfNeeded()
            return
        }

        wineMigration.copyLegacyBottle { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let destination):
                self.userPrefs.wineBottlePath = ""
                self.userPrefs.wineBottleMigrationAsked = true
                self.persistUserPrefs()
                self.wineBottlePath = destination.path
                self.patchFeedback = PatchFeedback(
                    title: "Wine Bottle Copied",
                    message: "Your legacy bottle was copied to \(destination.path). The original ~/.wine bottle was kept.",
                    isError: false
                )
                self.refreshWineBottleDependentStatuses()
                self.updateTelemetryConsentPromptState()
                self.startWineProfileMigrationIfNeeded()
            case .failure(let error):
                self.patchFeedback = PatchFeedback(
                    title: "Wine Bottle Migration Failed",
                    message: error.message,
                    isError: true
                )
            }
        }
    }

    var usesDefaultWineBottleLocation: Bool {
        userPrefs.wineBottlePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canChangeWineBottleLocation: Bool {
        !wineMigration.isMigrationInProgress
    }

    func selectWineBottleLocation() {
        guard canChangeWineBottleLocation else { return }
        let currentURL = WineBottleService.currentBottleURL(prefs: userPrefs)
        let panel = NSOpenPanel()
        panel.title = "Select Wine Bottle Folder"
        panel.message = "Choose an empty folder or an existing Wine bottle. This folder will be used directly as WINEPREFIX."
        panel.prompt = "Use Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.fileExists(atPath: currentURL.path)
            ? currentURL
            : currentURL.deletingLastPathComponent()
        panel.level = .modalPanel

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        do {
            let validated = try WineBottleService.validateSelectedBottleURL(selectedURL)
            userPrefs.wineBottlePath = validated.path
            userPrefs.wineBottleMigrationAsked = true
            persistUserPrefs()
            wineBottlePath = validated.path
            refreshWineBottleDependentStatuses()
            refreshAudioOutputs()
            wineMigration.resetProfileMigrationRequest()
            startWineProfileMigrationIfNeeded()
        } catch {
            presentWineBottleAlert(error.localizedDescription)
        }
    }

    func useDefaultWineBottleLocation() {
        guard canChangeWineBottleLocation else { return }
        userPrefs.wineBottlePath = ""
        userPrefs.wineBottleMigrationAsked = true
        persistUserPrefs()
        wineBottlePath = WineBottleService.defaultBottleURL().path
        refreshWineBottleDependentStatuses()
        refreshAudioOutputs()
        wineMigration.resetProfileMigrationRequest()
        startWineProfileMigrationIfNeeded()
    }

    func openWineBottleLocation() {
        let bottleURL = WineBottleService.currentBottleURL(prefs: userPrefs)
        do {
            try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(bottleURL)
        } catch {
            presentWineBottleAlert("Could not open the Wine bottle: \(error.localizedDescription)")
        }
    }

    func openWineConfiguration() {
        guard !isWineConfigurationLoading else { return }
        isWineConfigurationLoading = true
        patchFeedback = nil
        let customVariables = versionManager.currentVersion?.settings.environmentVariables ?? ""

        launchService.launchWineConfiguration(customVariables: customVariables) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isWineConfigurationLoading = false
                if case .failure(let error) = result {
                    self.patchFeedback = PatchFeedback(
                        title: "Wine Configuration",
                        message: error.localizedDescription,
                        isError: true
                    )
                }
            }
        }
    }

    func openWineTerminal() {
        guard !isWineTerminalLoading else { return }
        isWineTerminalLoading = true
        patchFeedback = nil
        let customVariables = versionManager.currentVersion?.settings.environmentVariables ?? ""

        launchService.launchWineTerminal(customVariables: customVariables) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isWineTerminalLoading = false
                if case .failure(let error) = result {
                    self.patchFeedback = PatchFeedback(
                        title: "Wine Terminal",
                        message: error.localizedDescription,
                        isError: true
                    )
                }
            }
        }
    }

    func createLaunchShortcut() {
        guard !isShortcutExportInProgress, let version = versionManager.currentVersion else { return }
        isShortcutExportInProgress = true
        shortcutExportFeedback = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let script = try self.launchService.shortcutShellScript(for: version)
                let shortcutURL = try ShortcutExportService.createSignedShortcut(
                    name: "Launch \(version.displayName)",
                    shellScript: script
                )
                DispatchQueue.main.async {
                    do {
                        try ShortcutExportService.openForImport(shortcutURL)
                        self.isShortcutExportInProgress = false
                        self.shortcutExportFeedback = PatchFeedback(
                            title: "Shortcut Created",
                            message: "The shortcut is ready to add in Shortcuts.",
                            isError: false
                        )
                    } catch {
                        self.isShortcutExportInProgress = false
                        self.shortcutExportFeedback = PatchFeedback(
                            title: "Shortcut Export Failed",
                            message: error.localizedDescription,
                            isError: true
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isShortcutExportInProgress = false
                    self.shortcutExportFeedback = PatchFeedback(
                        title: "Shortcut Export Failed",
                        message: error.localizedDescription,
                        isError: true
                    )
                }
            }
        }
    }

    func launchGame() {
        guard canLaunch, let currentVersion = versionManager.currentVersion else {
            patchFeedback = PatchFeedback(title: "Cannot Launch", message: "Ensure the game path is set and the game patch is applied.", isError: true)
            return
        }
        guard !isGameOperationInProgress, !isCheckingWineProcesses, launchTask == nil else { return }

        patchFeedback = nil
        isCheckingWineProcesses = true
        isGameOperationInProgress = true

        launchTask = Task { [weak self] in
            guard let self else { return }
            let preflight = await self.gameLaunchCoordinator.prepareLaunch(
                version: currentVersion,
                isAudioBusy: { [weak self] in self?.isAudioOutputBusy == true }
            )
            self.isCheckingWineProcesses = false

            switch preflight {
            case .ready(let processCount):
                if let processCount {
                    self.wineProcessCount = processCount
                }
                await self.completePreparedLaunch(currentVersion)
            case .existingWine(let processCount):
                self.wineProcessCount = processCount
                self.isGameOperationInProgress = false
                self.launchTask = nil
                self.shouldShowExistingWinePrompt = true
            case .cancelled:
                self.isGameOperationInProgress = false
                self.launchTask = nil
            }
        }
    }

    func handleExistingWineBeforeLaunch(cleanUp: Bool?) {
        shouldShowExistingWinePrompt = false
        guard let pendingLaunch = gameLaunchCoordinator.resolvePendingLaunch(cleanUp: cleanUp) else { return }
        isGameOperationInProgress = true
        if pendingLaunch.shouldCleanUpWine {
            forceQuitWine(launchAfter: pendingLaunch.version)
        } else {
            continueLaunch(pendingLaunch.version)
        }
    }

    private func continueLaunch(_ currentVersion: GameVersion) {
        launchTask = Task { [weak self] in
            await self?.completePreparedLaunch(currentVersion)
        }
    }

    private func installLaunchTerminationHandler() {
        launchService.processDidTerminate = { [weak self] in
            guard let self else { return }
            self.refreshSnapshot()
        }
    }

    private func completePreparedLaunch(_ currentVersion: GameVersion) async {
        installLaunchTerminationHandler()
        let outcome = await gameLaunchCoordinator.launchPrepared(currentVersion)
        handleLaunchOutcome(outcome, version: currentVersion)
        isGameOperationInProgress = false
        launchTask = nil
    }

    private func handleLaunchOutcome(_ outcome: GameLaunchOutcome, version: GameVersion) {
        switch outcome {
        case .started:
            recordWowStartTelemetry(for: version)
        case .versionMismatch(let base, let tweaked):
            versionMismatchData = (base, tweaked)
            shouldShowVersionMismatchPrompt = true
        case .vanillaTweaksMissing:
            pendingVanillaTweaksLaunch = true
            shouldShowVanillaTweaksPrompt = true
        case .failed(let error):
            patchFeedback = PatchFeedback(title: "Launch Failed", message: error.localizedDescription, isError: true)
            refreshSnapshot()
        case .cancelled:
            break
        }
    }

    func audioOutputBinding() -> Binding<String> {
        Binding(
            get: { self.versionManager.currentVersion?.settings.audioOutputDeviceID ?? "" },
            set: { self.selectAudioOutput(id: $0) }
        )
    }

    func audioInputBinding() -> Binding<String> {
        Binding(
            get: { self.versionManager.currentVersion?.settings.audioInputDeviceID ?? "" },
            set: { self.selectAudioInput(id: $0) }
        )
    }

    func spatializeStereoBinding() -> Binding<Bool> {
        Binding(
            get: { self.versionManager.currentVersion?.settings.spatializeStereo ?? false },
            set: { enabled in
                do {
                    try SpatialAudioService.setEnabled(enabled)
                    self.updateCurrentVersion { $0.settings.spatializeStereo = enabled }
                } catch {
                    self.patchFeedback = PatchFeedback(
                        title: "Spatial Audio",
                        message: error.localizedDescription,
                        isError: true
                    )
                }
            }
        )
    }

    func normalizeAudioBinding() -> Binding<Bool> {
        Binding(
            get: { self.versionManager.currentVersion?.settings.normalizeAudio ?? false },
            set: { enabled in
                do {
                    try SpatialAudioService.setNormalizeAudio(enabled)
                    self.updateCurrentVersion { $0.settings.normalizeAudio = enabled }
                } catch {
                    self.patchFeedback = PatchFeedback(
                        title: "Normalize Audio",
                        message: error.localizedDescription,
                        isError: true
                    )
                }
            }
        )
    }

    var selectedAudioOutputIsUnavailable: Bool {
        guard let id = versionManager.currentVersion?.settings.audioOutputDeviceID, !id.isEmpty else {
            return false
        }
        return !audioOutputDevices.contains { $0.id == id }
    }

    var selectedAudioInputIsUnavailable: Bool {
        guard let id = versionManager.currentVersion?.settings.audioInputDeviceID, !id.isEmpty else {
            return false
        }
        return !audioInputDevices.contains { $0.id == id }
    }

    func refreshAudioOutputs() {
        guard !isAudioOutputBusy else { return }
        isAudioOutputBusy = true
        patchFeedback = nil
        let customVariables = versionManager.currentVersion?.settings.environmentVariables ?? ""

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let snapshot = try AudioOutputService.snapshot(customVariables: customVariables)
                DispatchQueue.main.async {
                    self?.audioOutputDevices = snapshot.outputs
                    self?.audioInputDevices = snapshot.inputs
                    self?.audioDetails = snapshot.details
                    self?.isAudioOutputBusy = false
                }
            } catch {
                DispatchQueue.main.async {
                    self?.audioOutputDevices = []
                    self?.audioInputDevices = []
                    self?.audioDetails = nil
                    self?.isAudioOutputBusy = false
                    self?.patchFeedback = PatchFeedback(
                        title: "Audio Outputs",
                        message: error.localizedDescription,
                        isError: true
                    )
                }
            }
        }
    }

    private func selectAudioOutput(id: String) {
        guard versionManager.currentVersion?.settings.audioOutputDeviceID != id else { return }
        guard !isAudioOutputBusy else { return }
        isAudioOutputBusy = true
        patchFeedback = nil
        let customVariables = versionManager.currentVersion?.settings.environmentVariables ?? ""

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try AudioOutputService.selectOutput(id: id, customVariables: customVariables)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.updateCurrentVersion { $0.settings.audioOutputDeviceID = id }
                    self.audioDetails = nil
                    self.isAudioOutputBusy = false
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isAudioOutputBusy = false
                    self?.patchFeedback = PatchFeedback(
                        title: "Audio Output",
                        message: error.localizedDescription,
                        isError: true
                    )
                }
            }
        }
    }

    private func selectAudioInput(id: String) {
        guard versionManager.currentVersion?.settings.audioInputDeviceID != id else { return }
        guard !isAudioOutputBusy else { return }
        isAudioOutputBusy = true
        patchFeedback = nil
        let customVariables = versionManager.currentVersion?.settings.environmentVariables ?? ""

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try AudioOutputService.selectInput(id: id, customVariables: customVariables)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.updateCurrentVersion { $0.settings.audioInputDeviceID = id }
                    self.isAudioOutputBusy = false
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isAudioOutputBusy = false
                    self?.patchFeedback = PatchFeedback(
                        title: "Audio Input",
                        message: error.localizedDescription,
                        isError: true
                    )
                }
            }
        }
    }

    func testAudioOutput() {
        guard !isAudioOutputBusy else { return }
        isAudioOutputBusy = true
        patchFeedback = nil
        let settings = versionManager.currentVersion?.settings

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try AudioOutputService.testOutput(
                    spatializeStereo: settings?.spatializeStereo ?? false,
                    normalizeAudio: settings?.normalizeAudio ?? false,
                    customVariables: settings?.environmentVariables ?? ""
                )
                DispatchQueue.main.async { self?.isAudioOutputBusy = false }
            } catch {
                DispatchQueue.main.async {
                    self?.isAudioOutputBusy = false
                    self?.patchFeedback = PatchFeedback(
                        title: "Test Sound",
                        message: error.localizedDescription,
                        isError: true
                    )
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
                let previousValue = version.settings.graphicsSettings
                var normalizedValue = newValue
                if normalizedValue.backend != .mtld3d {
                    normalizedValue.hdrEnabled = false
                }
                let d3d9SelectionChanged = normalizedValue.backend == .d9vk
                    && (previousValue.backend != normalizedValue.backend
                        || previousValue.vulkanDriver != normalizedValue.vulkanDriver)
                let shouldInstallD3D9 = d3d9SelectionChanged
                    && PatchingStatusChecker.evaluateGamePatch(for: version).applied
                version.settings.graphicsSettings = normalizedValue
                self.updateCurrentVersion { current in current = version }
                guard version.supportsCustomGraphicsSettings || shouldInstallD3D9 else { return }
                let versionForWork = version
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        if shouldInstallD3D9 {
                            try PatchService.installD3D9DLL(for: versionForWork)
                        }
                        if versionForWork.supportsCustomGraphicsSettings {
                            try ConfigService.applyGraphicsSettings(for: versionForWork)
                        }
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

    func installVisualCppRuntime() {
        let customVariables = versionManager.currentVersion?.settings.environmentVariables ?? ""
        let task = dependencies.installVisualCppRuntime(customVariables: customVariables) { [weak self] feedback in
            self?.patchFeedback = feedback
        }
        if task != nil {
            patchFeedback = nil
        }
    }

    func refreshVisualCppRuntimeStatus() {
        dependencies.refreshVisualCppRuntimeStatus()
    }

    func installWineMono() {
        let customVariables = versionManager.currentVersion?.settings.environmentVariables ?? ""
        let task = dependencies.installWineMono(customVariables: customVariables) { [weak self] feedback in
            self?.patchFeedback = feedback
        }
        if task != nil {
            patchFeedback = nil
        }
    }

    func refreshWineMonoStatus() {
        dependencies.refreshWineMonoStatus()
    }

    func installGit() {
        let task = dependencies.installGit { [weak self] feedback in
            self?.patchFeedback = feedback
        }
        if task != nil {
            patchFeedback = nil
        }
    }

    func refreshGitStatus() {
        dependencies.refreshGitStatus()
    }

    func installRosetta() {
        let task = dependencies.installRosetta { [weak self] feedback in
            self?.patchFeedback = feedback
        }
        if task != nil {
            patchFeedback = nil
        }
    }

    func refreshRosettaStatus(promptIfMissing: Bool = false) {
        dependencies.refreshRosettaStatus { [weak self] in
            if promptIfMissing {
                self?.shouldShowRosettaInstallPrompt = true
            }
        }
    }

    func handleRosettaInstallPrompt(install: Bool) {
        shouldShowRosettaInstallPrompt = false
        if install {
            installRosetta()
        }
    }

    private func setOptionAsAlt(_ enabled: Bool) {
        guard !isOptionAsAltBusy else { return }

        optionAsAltStatusRefreshID += 1
        isOptionAsAltBusy = true
        optionAsAltStatus = .inProgress(enabled ? "Enabling…" : "Disabling…")
        let customVariables = versionManager.currentVersion?.settings.environmentVariables ?? ""

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try OptionAsAltService.setOptionAsAlt(
                    enabled: enabled,
                    customVariables: customVariables
                )
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
        optionAsAltStatusRefreshID += 1
        let refreshID = optionAsAltStatusRefreshID
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
                guard self.optionAsAltStatusRefreshID == refreshID else { return }
                self.optionAsAltStatus = enabled ? .enabled : .disabled
                self.applyOptionAsAltState(enabled: enabled, persist: false)
            }
        }
    }

    private func setRetinaMode(_ enabled: Bool) {
        guard !isRetinaModeBusy else { return }

        retinaModeStatusRefreshID += 1
        isRetinaModeBusy = true
        retinaModeStatus = .inProgress(enabled ? "Enabling…" : "Disabling…")
        let customVariables = versionManager.currentVersion?.settings.environmentVariables ?? ""

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try RetinaModeService.setRetinaMode(
                    enabled: enabled,
                    customVariables: customVariables
                )
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
        retinaModeStatusRefreshID += 1
        let refreshID = retinaModeStatusRefreshID
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
                guard self.retinaModeStatusRefreshID == refreshID else { return }
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

    private func migrateLegacyPrefsToCurrentVersion() {
        versionManager.updateCurrentVersion { version in
            version.settings.showTerminalNormally = userPrefs.showTerminalNormally
            version.settings.enableMetalHud = userPrefs.enableMetalHud
            if version.supportsVanillaTweaks {
                version.settings.enableVanillaTweaks = userPrefs.enableVanillaTweaks
            } else {
                version.settings.enableVanillaTweaks = false
            }
            version.settings.autoDeleteWdb = userPrefs.autoDeleteWdb
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

    @discardableResult
    private func normalizeTelemetryPrefs() -> Bool {
        let trimmedID = userPrefs.telemetryInstallID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedID.isEmpty {
            userPrefs.telemetryInstallID = UUID().uuidString
            return true
        }
        return false
    }

    private func updateTelemetryConsentPromptState() {
        shouldShowTelemetryConsentPrompt = !shouldShowMigrationPrompt
            && !shouldShowWineBottleMigrationPrompt
            && !wineMigration.isMigrationInProgress
            && !userPrefs.telemetryConsentAsked
    }

    @discardableResult
    private func updateWineBottleMigrationPromptState() -> Bool {
        guard !shouldShowMigrationPrompt, !userPrefs.wineBottleMigrationAsked else {
            shouldShowWineBottleMigrationPrompt = false
            return false
        }

        if !userPrefs.wineBottlePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userPrefs.wineBottleMigrationAsked = true
            shouldShowWineBottleMigrationPrompt = false
            return true
        }

        let destination = WineBottleService.currentBottleURL(prefs: userPrefs)
        if WineBottleService.isWineBottle(at: destination) {
            userPrefs.wineBottleMigrationAsked = true
            shouldShowWineBottleMigrationPrompt = false
            return true
        }

        shouldShowWineBottleMigrationPrompt = WineBottleService.shouldOfferLegacyMigration(prefs: userPrefs)
        return false
    }

    private func refreshWineBottleDependentStatuses() {
        refreshOptionAsAltStatus()
        refreshRetinaModeStatus()
        refreshVisualCppRuntimeStatus()
        refreshWineMonoStatus()
    }

    private func handleWineProfileMigrationOutcome(_ outcome: WineProfileMigrationOutcome) {
        switch outcome {
        case .succeeded(let migrated):
            if migrated {
                debugPrint("Copied the Wine user profile into the configured WoWSilicon bottle; ~/Wine was kept as a backup.")
            }
        case .failed(let message):
            debugPrint("Wine user profile migration failed: \(message)")
            patchFeedback = PatchFeedback(
                title: "Wine Profile Migration Failed",
                message: "WoWSilicon could not copy the Windows user profile into the selected bottle. Your existing ~/Wine folder was not removed. You can retry from Options. \(message)",
                isError: true
            )
        }
        updateTelemetryConsentPromptState()
    }

    private func presentWineBottleAlert(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Wine Bottle"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
