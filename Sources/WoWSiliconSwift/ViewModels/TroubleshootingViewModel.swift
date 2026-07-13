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
    @Published var debugLog: String = ""
    private var fullDebugLog: String = ""
    @Published var alert: ManagerAlert?
    
    @Published var hideMacUserName: Bool = true {
        didSet { if oldValue != hideMacUserName { refresh() } }
    }
    @Published var includeLatestErrorLog: Bool = false {
        didSet { if oldValue != includeLatestErrorLog { refresh() } }
    }

    private let context: TroubleshootingContext

    init(context: TroubleshootingContext) {
        self.context = context
    }

    func refresh() {
        status = .busy("Collecting information…")
        let context = self.context
        Task.detached { [weak self] in
            guard let self else { return }
            
            // Capture current toggle states
            let hideName = await self.hideMacUserName
            let includeLog = await self.includeLatestErrorLog
            
            
            let result = TroubleshootingService.generateDebugLog(
                context: context,
                hideMacUserName: hideName,
                includeLatestErrorLog: includeLog
            )

            Task { @MainActor in
                self.wineRuntimeStatus = BundledWineRuntime.wineExecutableURL() == nil ? "Missing" : "Available"
                self.debugLog = result.preview
                self.fullDebugLog = result.full
                self.status = .ready
            }
        }
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
