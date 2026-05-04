import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

@main
struct WoWSiliconSwiftApp: App {
    @StateObject private var viewModel = MainDashboardViewModel()

    init() {
        if let image = turtleIconImage() {
            NSApplication.shared.applicationIconImage = image
        }
        _ = UpdaterService.shared
    }

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
}

#Preview {
    MainDashboardView(viewModel: .preview)
        .fixedSize()
}
