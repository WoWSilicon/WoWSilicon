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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1")
    ],
    targets: [
        .executableTarget(
            name: "WoWSiliconSwift",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources",
            resources: [
                .copy("WoWSiliconSwift/Resources/Icons"),
                .copy("WoWSiliconSwift/Resources/Patching")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "WoWSiliconSwiftTests",
            dependencies: ["WoWSiliconSwift"],
            path: "Tests/WoWSiliconSwiftTests"
        )
    ]
)
