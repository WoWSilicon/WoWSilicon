import AppKit
import Sparkle

@MainActor
final class UpdaterService: NSObject {
    static let shared = UpdaterService()

    private let updaterController: SPUStandardUpdaterController?

    override private init() {
        if Self.isConfigured {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            updaterController = nil
        }
        super.init()
    }

    func checkForUpdates() {
        guard let updaterController else {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Updates Not Configured"
            alert.informativeText = "Sparkle is wired in, but the appcast feed and public update key still need to be configured before update checks can run."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        updaterController.checkForUpdates(nil)
    }

    private static var isConfigured: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        let feedURL = (info["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let publicKey = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !feedURL.isEmpty && !publicKey.isEmpty && !publicKey.hasPrefix("TODO_")
    }
}
