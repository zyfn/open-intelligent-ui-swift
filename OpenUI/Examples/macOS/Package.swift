// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenUIDemo",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "OpenUIDemo", targets: ["OpenUIDemo"])],
    dependencies: [
        .package(name: "OpenUISwiftSDK", path: "../../.."),
    ],
    targets: [.executableTarget(name: "OpenUIDemo", dependencies: [
        .product(name: "OpenUILang", package: "OpenUISwiftSDK"),
        .product(name: "OpenSwiftUI", package: "OpenUISwiftSDK"),
    ], swiftSettings: [.swiftLanguageMode(.v5)])]
)
