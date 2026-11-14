// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenUIContractTools",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ContractExport", targets: ["ContractExport"])],
    dependencies: [.package(name: "OpenUISwiftSDK", path: "../..")],
    targets: [
        .executableTarget(
            name: "ContractExport",
            dependencies: [
                .product(name: "OpenUILang", package: "OpenUISwiftSDK"),
                .product(name: "OpenUICore", package: "OpenUISwiftSDK"),
                .product(name: "OpenIntelligentSwiftUI", package: "OpenUISwiftSDK")
            ],
            path: ".", exclude: ["README.md"],
            sources: ["Export.swift", "ProgramChecks.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
