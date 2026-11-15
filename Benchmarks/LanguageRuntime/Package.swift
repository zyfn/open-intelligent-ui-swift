// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftLangBenchmark",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LanguageBenchmark", targets: ["LanguageBenchmark"])],
    dependencies: [.package(name: "openui-swift-sdk", path: "../..")],
    targets: [
        .executableTarget(name: "LanguageBenchmark", dependencies: [
            .product(name: "swift-lang", package: "openui-swift-sdk")
        ], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
