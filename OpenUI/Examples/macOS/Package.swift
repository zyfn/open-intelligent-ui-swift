// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenUIDemo",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "OpenUIDemo", targets: ["OpenUIDemo"])],
    dependencies: [
        .package(name: "NativeWorkspace", path: "../../.."),
    ],
    targets: [.executableTarget(name: "OpenUIDemo", dependencies: [
        .product(name: "OpenUILang", package: "NativeWorkspace"),
        .product(name: "OpenSwiftUI", package: "NativeWorkspace"),
    ], swiftSettings: [.swiftLanguageMode(.v5)])]
)
