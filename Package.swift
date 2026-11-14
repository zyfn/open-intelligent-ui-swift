// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenUISwiftSDK",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "OpenUILang", targets: ["OpenUILang"]),
        .library(name: "OpenUICore", targets: ["OpenUICore"]),
        .library(name: "OpenSwiftUI", targets: ["OpenSwiftUI"]),
        .library(name: "OpenIntelligentSwiftUI", targets: ["OpenIntelligentSwiftUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1")
    ],
    targets: [
        .target(name: "COpenUIRegExp", path: "Sources/COpenUIRegExp",
            exclude: ["README.md", "VENDOR.json", "vendor/LICENSE"],
            sources: ["Bridge.c", "RegExpEngine.c", "UnicodeEngine.c"], publicHeadersPath: "include"),
        .target(name: "OpenUILang", dependencies: ["COpenUIRegExp"], path: "Sources/OpenUILang",
            resources: [.copy("Resources/lang-core.js"), .copy("Resources/core-manifest.json"), .copy("Resources/THIRD-PARTY-NOTICES.txt")],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "OpenUICore", dependencies: ["OpenUILang"], path: "Sources/OpenUICore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "OpenSwiftUI", dependencies: ["OpenUILang", "OpenUICore", .product(name: "MarkdownUI", package: "swift-markdown-ui")],
            path: "Sources/OpenSwiftUI", resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "OpenUICoreTests", dependencies: ["OpenUICore"], path: "Tests/OpenUICoreTests", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "OpenUILangTests", dependencies: ["OpenUILang"], path: "Tests/OpenUILangTests",
            resources: [.copy("Fixtures")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "OpenSwiftUITests", dependencies: ["OpenSwiftUI"], path: "Tests/OpenSwiftUITests",
            resources: [.copy("Fixtures")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "OpenIntelligentSwiftUI", dependencies: [
            "OpenUILang", "OpenUICore",
            .product(name: "MarkdownUI", package: "swift-markdown-ui")
        ], resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "OpenIntelligentSwiftUITests", dependencies: ["OpenIntelligentSwiftUI"],
                    resources: [.copy("Fixtures")], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
