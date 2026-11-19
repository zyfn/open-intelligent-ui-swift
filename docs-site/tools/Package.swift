// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GuideExport",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(name: "GuideExport", dependencies: [
            .product(name: "swift-ui", package: "openui-swift-sdk"),
            .product(name: "swift-intelligent-ui", package: "openui-swift-sdk")
        ], path: "Sources", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
