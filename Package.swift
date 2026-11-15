// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "openui-swift-sdk",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "swift-lang", targets: ["SwiftLang"]),
        .library(name: "swift-ui", targets: ["SwiftOpenUI"]),
        .library(name: "swift-intelligent-ui", targets: ["SwiftIntelligentUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1")
    ],
    targets: [
        .target(name: "COpenUIRegExp", path: "Sources/COpenUIRegExp",
            exclude: ["README.md", "VENDOR.json", "vendor/LICENSE"],
            sources: ["Bridge.c", "RegExpEngine.c", "UnicodeEngine.c"], publicHeadersPath: "include"),
        .target(name: "SwiftLang", dependencies: ["COpenUIRegExp"], path: "Sources/SwiftLang",
            resources: [.copy("Resources/lang-core.js"), .copy("Resources/core-manifest.json"), .copy("Resources/THIRD-PARTY-NOTICES.txt")],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "SwiftOpenUI", dependencies: ["SwiftLang", .product(name: "MarkdownUI", package: "swift-markdown-ui")],
            path: "Sources/SwiftOpenUI", resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "SwiftLangTests", dependencies: ["SwiftLang"], path: "Tests/SwiftLangTests",
            resources: [.copy("Fixtures")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "SwiftOpenUITests", dependencies: ["SwiftOpenUI"], path: "Tests/SwiftOpenUITests",
            resources: [.copy("Fixtures")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "SwiftIntelligentUI", dependencies: [
            "SwiftLang",
            .product(name: "MarkdownUI", package: "swift-markdown-ui")
        ], resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "SwiftIntelligentUITests", dependencies: ["SwiftIntelligentUI"],
                    resources: [.copy("Fixtures")], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
