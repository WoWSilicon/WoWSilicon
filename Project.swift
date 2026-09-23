import ProjectDescription

let project = Project(
    name: "WoWSilicon",
    organizationName: "com.wowsilicon",
    packages: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1")
    ],
    options: .options(
        automaticSchemesOptions: .enabled(
            targetSchemesGrouping: .singleScheme,
            codeCoverageEnabled: false,
            testingOptions: []
        )
    ),
    settings: .settings(
        base: [
            "MARKETING_VERSION": "3.2.1",
            "CURRENT_PROJECT_VERSION": "30201",
            "SWIFT_VERSION": "6.0",
            "MACOSX_DEPLOYMENT_TARGET": "14.0",
            "DEVELOPMENT_TEAM": "",
            "CODE_SIGN_IDENTITY": "Apple Development",
            "CODE_SIGN_STYLE": "Automatic",
            "ENABLE_HARDENED_RUNTIME": "YES",
        ],
        configurations: [
            .debug(name: .debug),
            .release(name: .release)
        ]
    ),
    targets: [
        .target(
            name: "WoWSilicon",
            destinations: .macOS,
            product: .app,
            bundleId: "com.wowsilicon.swift",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .file(path: "Packaging/Info.plist"),
            sources: ["Sources/WoWSiliconSwift/**/*.swift"],
            resources: [
                "Sources/WoWSiliconSwift/Resources/**"
            ],
            dependencies: [
                .package(product: "Sparkle")
            ],
            settings: .settings(
                base: [
                    "INFOPLIST_FILE": "Packaging/Info.plist",
                    "PRODUCT_BUNDLE_IDENTIFIER": "com.wowsilicon.swift",
                    "PRODUCT_NAME": "WoWSilicon",
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "turtle",
                    "COMBINE_HIDPI_IMAGES": "YES",
                    "LD_RUNPATH_SEARCH_PATHS": [
                        "$(inherited)",
                        "@executable_path/../Frameworks"
                    ],
                    "SWIFT_EMIT_LOC_STRINGS": "YES",
                    "ENABLE_PREVIEWS": "YES"
                ],
                configurations: [
                    .debug(
                        name: .debug,
                        settings: [
                            "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
                            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"
                        ]
                    ),
                    .release(
                        name: .release,
                        settings: [
                            "SWIFT_OPTIMIZATION_LEVEL": "-O",
                            "SWIFT_COMPILATION_MODE": "wholemodule"
                        ]
                    )
                ]
            )
        )
    ],
    schemes: [
        .scheme(
            name: "WoWSilicon",
            shared: true,
            buildAction: .buildAction(targets: ["WoWSilicon"]),
            runAction: .runAction(
                configuration: .debug,
                executable: "WoWSilicon"
            ),
            archiveAction: .archiveAction(
                configuration: .release
            ),
            profileAction: .profileAction(
                configuration: .release,
                executable: "WoWSilicon"
            ),
            analyzeAction: .analyzeAction(
                configuration: .debug
            )
        )
    ]
)
