// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenUILanguageBenchmark",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LanguageBenchmark", targets: ["LanguageBenchmark"])],
    dependencies: [.package(name: "OpenUISwiftSDK", path: "../..")],
    targets: [
        .executableTarget(name: "LanguageBenchmark", dependencies: [
            .product(name: "OpenUILang", package: "OpenUISwiftSDK")
        ], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
