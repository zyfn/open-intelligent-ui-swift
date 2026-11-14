// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenUIGallery",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.executable(name: "OpenUIGallery", targets: ["OpenUIGallery"])],
    dependencies: [.package(name: "OpenUISwiftSDK", path: "../..")],
    targets: [
        .executableTarget(
            name: "OpenUIGallery",
            dependencies: [
                .product(name: "OpenUILang", package: "OpenUISwiftSDK"),
                .product(name: "OpenUICore", package: "OpenUISwiftSDK"),
                .product(name: "OpenSwiftUI", package: "OpenUISwiftSDK"),
                .product(name: "OpenIntelligentSwiftUI", package: "OpenUISwiftSDK")
            ],
            path: ".",
            exclude: ["OpenUIGallery.xcodeproj", "Tests", "README.md", "build-app.sh", "verify.sh"],
            sources: ["Sources"],
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "OpenUIGalleryTests", dependencies: ["OpenUIGallery"],
                    path: "Tests", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
