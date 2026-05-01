// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WoWSilicon-swift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "WoWSilicon",
            targets: ["WoWSiliconSwift"]
        )
    ],
    targets: [
        .executableTarget(
            name: "WoWSiliconSwift",
            path: "Sources",
            resources: [
                .copy("WoWSiliconSwift/Resources/Icons"),
                .copy("WoWSiliconSwift/Resources/Patching")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "WoWSiliconSwiftTests",
            dependencies: ["WoWSiliconSwift"],
            path: "Tests/WoWSiliconSwiftTests"
        )
    ]
)
