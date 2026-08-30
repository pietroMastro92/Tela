import ProjectDescription

let sharedSettings: Settings = .settings(
    base: [
        "SWIFT_VERSION": "6.0",
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "MACOSX_DEPLOYMENT_TARGET": "14.0",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "CLANG_ENABLE_MODULES": "YES"
    ],
    configurations: [
        // The accelerated walkthrough is a local development aid. Keeping its
        // compilation flag on Debug removes Demo entry points from Release.
        .debug(
            name: "Debug",
            settings: [
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) TELA_DEMO"
            ]
        ),
        .release(
            name: "Release",
            settings: [
                "ENABLE_HARDENED_RUNTIME": "YES",
                "CODE_SIGN_INJECT_BASE_ENTITLEMENTS": "NO",
                "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym"
            ]
        )
    ],
    defaultSettings: .recommended
)

let project = Project(
    name: "Tela",
    organizationName: "Pietro Mastro",
    settings: sharedSettings,
    targets: [
        .target(
            name: "Tela",
            destinations: [.mac],
            product: .app,
            bundleId: "com.pietromastro.Tela",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .dictionary([
                "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
                "CFBundleDisplayName": "Tela",
                "CFBundleExecutable": "$(EXECUTABLE_NAME)",
                "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundleName": "Tela",
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "1.0.1",
                "CFBundleVersion": "2",
                "LSApplicationCategoryType": "public.app-category.productivity",
                "LSMinimumSystemVersion": "14.0",
                "NSHighResolutionCapable": true,
                "NSPrincipalClass": "NSApplication",
                "NSHumanReadableCopyright": "Public-domain artwork credits are included in the app."
            ]),
            sources: ["Tela/Sources/**"],
            resources: ["Tela/Resources/**", "Scripts/public_domain_artworks.json"],
            entitlements: .file(path: "Tela/Tela.entitlements"),
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "CODE_SIGN_STYLE": "Automatic",
                "ENABLE_HARDENED_RUNTIME": "YES",
                "PRODUCT_NAME": "Tela"
            ])
        ),
        .target(
            name: "TelaTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.pietromastro.TelaTests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["Tests/TelaTests/**"],
            dependencies: [.target(name: "Tela")]
        ),
        .target(
            name: "TelaUITests",
            destinations: [.mac],
            product: .uiTests,
            bundleId: "com.pietromastro.TelaUITests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["Tests/TelaUITests/**"],
            dependencies: [.target(name: "Tela")]
        )
    ],
    schemes: [
        .scheme(
            name: "Tela",
            shared: true,
            buildAction: .buildAction(targets: ["Tela"]),
            testAction: .targets(["TelaTests", "TelaUITests"], configuration: "Debug"),
            runAction: .runAction(configuration: "Debug"),
            archiveAction: .archiveAction(configuration: "Release"),
            profileAction: .profileAction(configuration: "Release"),
            analyzeAction: .analyzeAction(configuration: "Debug")
        )
    ]
)
