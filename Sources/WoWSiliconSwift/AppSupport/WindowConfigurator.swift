import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let title: String
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window ?? NSApp.windows.first else { return }
        window.isMovableByWindowBackground = true
        window.title = title
        window.setContentSize(NSSize(width: width, height: height))
        window.minSize = NSSize(width: width, height: height)
        window.maxSize = NSSize(width: width, height: height)
        window.styleMask.remove(.resizable)
        window.center()
        window.delegate = QuitOnCloseWindowDelegate.shared
    }
}

@MainActor
final class QuitOnCloseWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = QuitOnCloseWindowDelegate()

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}
