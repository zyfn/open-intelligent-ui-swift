// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftIntelligentUI",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "OpenUILang", targets: ["OpenUILang"]),
        .library(name: "OpenUISwiftUI", targets: ["OpenUISwiftUI"]),
        .library(name: "SwiftIntelligentUI", targets: ["SwiftIntelligentUI"]),
        .executable(name: "IntelligentUIGallery", targets: ["IntelligentUIGallery"]),
        .executable(name: "ContractExport", targets: ["ContractExport"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1")
    ],
    targets: [
        .target(name: "COpenUIRegExp", path: "OpenUI/Sources/COpenUIRegExp",
            exclude: ["README.md", "VENDOR.json", "vendor/LICENSE"],
            sources: ["Bridge.c", "RegExpEngine.c", "UnicodeEngine.c"], publicHeadersPath: "include"),
        .target(name: "OpenUILang", dependencies: ["COpenUIRegExp"], path: "OpenUI/Sources/OpenUILang",
            resources: [.copy("Resources/lang-core.js"), .copy("Resources/core-manifest.json"), .copy("Resources/THIRD-PARTY-NOTICES.txt")],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "OpenUISwiftUI", dependencies: ["OpenUILang", .product(name: "MarkdownUI", package: "swift-markdown-ui")],
            path: "OpenUI/Sources/OpenUISwiftUI", resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "OpenUILangTests", dependencies: ["OpenUILang"], path: "OpenUI/Tests/OpenUILangTests",
            resources: [.copy("Fixtures")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "OpenUISwiftUITests", dependencies: ["OpenUISwiftUI"], path: "OpenUI/Tests/OpenUISwiftUITests",
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "SwiftIntelligentUI", dependencies: [
            "OpenUILang", "OpenUISwiftUI",
            .product(name: "MarkdownUI", package: "swift-markdown-ui")
        ], resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "IntelligentUIGallery", dependencies: ["SwiftIntelligentUI"],
                          path: "Examples/Gallery", exclude: ["IntelligentUIGallery.xcodeproj"], resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "ContractExport", dependencies: ["SwiftIntelligentUI"], path: "Tools/ContractExport", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "SwiftIntelligentUITests", dependencies: ["SwiftIntelligentUI"],
                    swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
