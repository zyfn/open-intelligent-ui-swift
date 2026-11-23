#if os(iOS)
import Foundation
import UIKit
import XCTest
@testable import OpenUIGallery

final class GalleryBundleTests: XCTestCase {
    @MainActor func testApplicationBundleLoadsBothLibrariesAndLocalResources() throws {
        let application = Bundle.main
        XCTAssertEqual(application.bundleIdentifier, "dev.openui.gallery.ios",
            "Foundation must recognize the installed Gallery application bundle")
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            application.bundleURL.appendingPathComponent("Resources").path),
            "An iOS application must not contain a custom Resources directory at its root")

        let resources = try GalleryResources.root()
        let expected = application.bundleURL.appendingPathComponent("GalleryResources/Resources", isDirectory: true)
        XCTAssertEqual(resources.resolvingSymlinksInPath().standardizedFileURL.path,
            expected.resolvingSymlinksInPath().standardizedFileURL.path,
            "The normal Gallery resource resolver must use the installed app's copied resources")

        // The production catalog reads every referenced source. Reuse that
        // validation instead of implementing another manifest parser here.
        let catalog = try GalleryCatalog(resourceRoot: resources)
        for library in GalleryLibrary.allCases {
            for section in GallerySection.allCases {
                XCTAssertTrue(catalog.entries.contains { $0.section == section && $0.supports(library) },
                    "The installed app needs \(section.rawValue) resources for \(library.rawValue)")
            }
            let components = try GalleryComponent.load(library, resourceRoot: resources)
            XCTAssertFalse(components.isEmpty, "Missing bundled component examples for \(library.rawValue)")
        }

        // Initializing the real loader validates its complete local image map.
        // Decode a bundled image directly so even a broken map cannot cause
        // this packaging regression to fall through to a network request.
        _ = try GalleryImageLoader(resourceRoot: resources)
        let bytes = try Data(contentsOf: resources.appendingPathComponent("Images/nikon-front.jpg"))
        let image = try XCTUnwrap(UIImage(data: bytes)?.cgImage,
            "The installed image resource must contain decodable image bytes")
        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
    }
}
#endif
