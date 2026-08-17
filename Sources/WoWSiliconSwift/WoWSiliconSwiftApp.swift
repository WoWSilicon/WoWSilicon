import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

@main
struct WoWSiliconSwiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = MainDashboardViewModel()

    var body: some Scene {
        WindowGroup {
            MainDashboardView(viewModel: viewModel)
                .frame(width: windowWidth, height: windowHeight)
                .background(WindowConfigurator(
                    title: "WoWSilicon v\(appVersion)",
                    width: windowWidth,
                    height: windowHeight
                ))
                .registerEnvironmentValues(viewModel)
                .onAppear {
                    configureApplication()
                }
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    UpdaterService.shared.checkForUpdates()
                }
            }
        }
    }

    private func configureApplication() {
        if let image = turtleIconImage() {
            NSApplication.shared.applicationIconImage = image
        }
        _ = UpdaterService.shared
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Clean up residual wine processes left behind by game sessions (winedevice,
        // wineserver, Synaptics watchdog, etc.). Doing this when the app quits avoids
        // killing the game while it is running and avoids racing with a new launch.
        LaunchService.forceQuitWine(crossOverPath: nil)
        return .terminateNow
    }
}

#Preview {
    MainDashboardView(viewModel: .preview)
        .fixedSize()
}
