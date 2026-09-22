import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

@main
struct WoWSiliconSwiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = MainDashboardViewModel()

    var body: some Scene {
        Window("WoWSilicon", id: "main") {
            MainDashboardView(viewModel: viewModel)
                .frame(width: windowWidth, height: windowHeight)
                .background(WindowConfigurator(
                    title: "WoWSilicon v\(appVersion)",
                    width: windowWidth,
                    height: windowHeight
                ))
                .registerEnvironmentValues(viewModel)
                .onAppear {
                    appDelegate.firstWindowDidAppear()
                    viewModel.startWineProfileMigrationIfNeeded()
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appLaunchInterval: LaunchPerformanceInterval? = LaunchPerformance.beginAppLaunch()

    func firstWindowDidAppear() {
        guard let appLaunchInterval else { return }
        LaunchPerformance.endAppLaunch(appLaunchInterval)
        self.appLaunchInterval = nil
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
    }
}

#Preview {
    MainDashboardView(viewModel: .preview)
        .fixedSize()
}
