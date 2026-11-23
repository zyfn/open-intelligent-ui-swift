// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftLangPerformanceValidation",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LanguagePerformanceValidation", targets: ["LanguagePerformanceValidation"])],
    dependencies: [.package(name: "openui-swift-sdk", path: "../..")],
    targets: [
        .executableTarget(name: "LanguagePerformanceValidation", dependencies: [
            .product(name: "swift-lang", package: "openui-swift-sdk")
        ], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
