import Foundation
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class TroubleshootingViewModel: ObservableObject, Identifiable {
    let id = UUID()

    enum Status {
        case idle
        case busy(String)
        case ready
    }

    @Published var status: Status = .idle
    @Published var wineRuntimeStatus: String = "Checking..."
    @Published var permissionChecks: [PermissionAccessCheck] = []
    @Published var debugLog: String = ""
    private var fullDebugLog: String = ""
    @Published var alert: ManagerAlert?
    
    @Published var hideMacUserName: Bool = true {
        didSet { if oldValue != hideMacUserName { refresh() } }
    }
    @Published var includeLatestErrorLog: Bool = false {
        didSet { if oldValue != includeLatestErrorLog { refresh() } }
    }

    private var context: TroubleshootingContext
    private let onGamePathSelected: ((URL) -> Void)?

    init(context: TroubleshootingContext, onGamePathSelected: ((URL) -> Void)? = nil) {
        self.context = context
        self.onGamePathSelected = onGamePathSelected
    }

    func refresh() {
        status = .busy("Collecting information…")
        let context = self.context
        Task.detached { [weak self] in
            guard let self else { return }
            
            // Capture current toggle states
            let hideName = await self.hideMacUserName
            let includeLog = await self.includeLatestErrorLog
            let permissionChecks = TroubleshootingService.checkPermissions(context: context)

            let result = TroubleshootingService.generateDebugLog(
                context: context,
                hideMacUserName: hideName,
                includeLatestErrorLog: includeLog,
                permissionChecks: permissionChecks
            )

            Task { @MainActor in
                self.wineRuntimeStatus = BundledWineRuntime.wineExecutableURL() == nil ? "Missing" : "Available"
                self.permissionChecks = permissionChecks
                self.debugLog = result.preview
                self.fullDebugLog = result.full
                self.status = .ready
            }
        }
    }

    func reselectGamePath() {
#if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.title = "Re-select Game Executable"
        panel.message = "Select the configured game executable to grant WoWSilicon access again."
        panel.prompt = "Grant Access"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "exe")].compactMap { $0 }
        panel.directoryURL = context.currentVersion?.gameDirectoryURL
        panel.level = .modalPanel

        guard panel.runModal() == .OK, let url = panel.url else { return }
        onGamePathSelected?(url)

        var updatedVersion = context.currentVersion
        updatedVersion?.gamePath = url.path
        updatedVersion?.executableName = url.lastPathComponent
        context = TroubleshootingContext(
            gamePath: url.path,
            currentVersion: updatedVersion,
            isGamePatched: context.isGamePatched
        )
        refresh()
#endif
    }

    func openPrivacySettings() {
#if canImport(AppKit)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") else { return }
        if !NSWorkspace.shared.open(url) {
            alert = ManagerAlert(message: "Open System Settings > Privacy & Security, then review Files & Folders and App Management for WoWSilicon.")
        }
#endif
    }

    func deleteWDB() {
        let gamePath = context.gamePath
        perform(action: "Deleting WDB directories…") {
            let deleted = try TroubleshootingService.deleteWDBDirectories(gamePath: gamePath)
            return "Deleted:\n" + deleted.joined(separator: "\n")
        }
    }

    func deleteDefaultWineBottle() {
        perform(action: "Deleting default Wine bottle…") {
            let deleted = try TroubleshootingService.deleteDefaultWineBottle()
            return "Deleted:\n" + deleted
        }
    }

    func deleteVanillaTweaks() {
        let gamePath = context.gamePath
        perform(action: "Deleting WoW_tweaked.exe…") {
            try TroubleshootingService.deleteVanillaTweaks(gamePath: gamePath)
            return "WoW_tweaked.exe deleted successfully."
        }
    }

    func resetApplicationSupport() {
        perform(action: "Resetting WoWSilicon…") {
            try TroubleshootingService.resetApplicationSupport()
            return "WoWSilicon configuration removed. Please restart the app."
        }
    }

    func copyDebugLog() {
#if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fullDebugLog, forType: .string)
#endif
        alert = ManagerAlert(message: "Debug log copied to clipboard.")
    }

    private func perform(action: String, work: @escaping @Sendable () throws -> String) {
        guard case .busy = status else {
            status = .busy(action)
            Task.detached { [weak self] in
                guard let self else { return }
                do {
                    let message = try work()
                    Task { @MainActor in
                        self.status = .ready
                        self.alert = ManagerAlert(message: message)
                        self.refresh()
                    }
                } catch {
                    Task { @MainActor in
                        self.status = .ready
                        if let svcError = error as? TroubleshootingServiceError {
                            switch svcError {
                            case .nothingToDelete:
                                self.alert = ManagerAlert(message: "Nothing to delete for this action.")
                            default:
                                self.alert = ManagerAlert(message: svcError.localizedDescription)
                            }
                        } else {
                            self.alert = ManagerAlert(message: error.localizedDescription)
                        }
                        self.refresh()
                    }
                }
            }
            return
        }
    }
}
