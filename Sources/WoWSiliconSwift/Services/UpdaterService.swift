import AppKit
import Darwin
import Sparkle

@MainActor
final class UpdaterService: NSObject {
    static let shared = UpdaterService()

    private var updaterController: SPUStandardUpdaterController?

    override private init() {
        super.init()

        if Self.isConfigured {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: self,
                userDriverDelegate: nil
            )
        } else {
            updaterController = nil
        }
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

extension UpdaterService: SPUUpdaterDelegate {
    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        return true
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        DispatchQueue.main.async {
            installHandler()
        }
        return false
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        NSApp.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            exit(0)
        }
    }
}
