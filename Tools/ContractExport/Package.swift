// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenUIContractTools",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ContractExport", targets: ["ContractExport"])],
    dependencies: [.package(name: "openui-swift-sdk", path: "../..")],
    targets: [
        .executableTarget(
            name: "ContractExport",
            dependencies: [
                .product(name: "swift-lang", package: "openui-swift-sdk"),
                .product(name: "swift-intelligent-ui", package: "openui-swift-sdk")
            ],
            path: ".", exclude: ["README.md"],
            sources: ["Export.swift", "ProgramChecks.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
