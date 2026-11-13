// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftIntelligentUI",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "SwiftIntelligentUI", targets: ["SwiftIntelligentUI"]),
        .executable(name: "IntelligentUIGallery", targets: ["IntelligentUIGallery"]),
        .executable(name: "ContractExport", targets: ["ContractExport"])
    ],
    dependencies: [
        .package(url: "https://github.com/zyfn/openui.git", revision: "b8ea283916b9630ce8590338c8f8dc5b71fd75e4"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1")
    ],
    targets: [
        .target(name: "SwiftIntelligentUI", dependencies: [
            .product(name: "OpenUILang", package: "openui"),
            .product(name: "OpenUISwiftUI", package: "openui"),
            .product(name: "MarkdownUI", package: "swift-markdown-ui")
        ], resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "IntelligentUIGallery", dependencies: ["SwiftIntelligentUI"],
                          path: "Examples/Gallery", exclude: ["IntelligentUIGallery.xcodeproj"], resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "ContractExport", dependencies: ["SwiftIntelligentUI"], path: "Tools/ContractExport", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "SwiftIntelligentUITests", dependencies: ["SwiftIntelligentUI"],
                    swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
