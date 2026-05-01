import AppKit
import Foundation

let windowWidth: CGFloat = 650
let windowHeight: CGFloat = 600
let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.5.0"

private let resourceBundle: Bundle? = {
    let bundleName = "WoWSilicon-swift_WoWSiliconSwift"
    if let url = Bundle.main.url(forResource: bundleName, withExtension: "bundle") {
        return Bundle(url: url)
    }
    return nil
}()

func turtleIconImage() -> NSImage? {
    if let url = Bundle.main.url(forResource: "turtle", withExtension: "icns"),
       let image = NSImage(contentsOf: url) {
        return image
    }
    if let url = Bundle.main.url(forResource: "turtlesilicon_icon", withExtension: "png", subdirectory: "Icons"),
       let image = NSImage(contentsOf: url) {
        return image
    }
    if let url = Bundle.main.url(forResource: "turtlesilicon_icon", withExtension: "png"),
       let image = NSImage(contentsOf: url) {
        return image
    }
    if let url = resourceBundle?.url(forResource: "turtlesilicon_icon", withExtension: "png", subdirectory: "Icons"),
       let image = NSImage(contentsOf: url) {
        return image
    }
    if let url = resourceBundle?.url(forResource: "turtlesilicon_icon", withExtension: "png"),
       let image = NSImage(contentsOf: url) {
        return image
    }
    if let image = NSImage(named: "turtlesilicon_icon") ?? NSImage(named: "turtle") {
        return image
    }
    if #available(macOS 11.0, *) {
        if let systemImage = NSImage(systemSymbolName: "tortoise.fill", accessibilityDescription: nil) {
            return systemImage
        }
    }
    return nil
}

func iconImage(for _: String) -> NSImage? {
    turtleIconImage()
}
