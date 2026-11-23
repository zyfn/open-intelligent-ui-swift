// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenUIGallery",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.executable(name: "OpenUIGallery", targets: ["OpenUIGallery"])],
    dependencies: [.package(name: "openui-swift-sdk", path: "../..")],
    targets: [
        .executableTarget(
            name: "OpenUIGallery",
            dependencies: [
                .product(name: "swift-lang", package: "openui-swift-sdk"),
                .product(name: "swift-ui", package: "openui-swift-sdk"),
                .product(name: "swift-intelligent-ui", package: "openui-swift-sdk")
            ],
            path: ".",
            exclude: ["OpenUIGallery.xcodeproj", "Tests", "UITests", "README.md", "build-app.sh", "verify.sh"],
            sources: ["Sources"],
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "OpenUIGalleryTests", dependencies: ["OpenUIGallery"],
                    path: "Tests", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
