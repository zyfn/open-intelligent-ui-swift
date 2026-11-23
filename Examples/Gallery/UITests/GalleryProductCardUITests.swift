#if os(iOS)
import CoreGraphics
import UIKit
import XCTest

/// These assertions require an application's real accessibility tree. Package
/// framework XCTest can render pixels but cannot provide SwiftUI's AX nodes.
final class GalleryProductCardUITests: GalleryNativeUITestCase {
    @MainActor func testProductMediaUsesItsDeclaredLayoutAtPhoneWidth() throws {
        for layout in ["vertical", "horizontal", "compact"] {
            let app = launch(scenario: "product-\(layout)")
            let image = try require(app.buttons["Product front"])
            let title = try require(app.staticTexts["Camera"])
            scrollTo(image, in: app)
            let pixels = try XCTUnwrap(image.screenshot().image.cgImage)
            let media = try XCTUnwrap(markerBounds(pixels, channel: 0))
            let scale = CGFloat(pixels.width) / image.frame.width
            XCTAssertGreaterThan(media.width / scale, 60, "\(layout) must paint the supplied image")
            XCTAssertEqual(media.width / media.height, layout == "vertical" ? 1.5 : 1,
                           accuracy: 0.03, "The existing \(layout) media contract must survive app hosting")
            if layout == "vertical" {
                XCTAssertEqual(media.width / scale, 320, accuracy: 2)
                XCTAssertGreaterThanOrEqual(title.frame.minY, image.frame.maxY - 1)
            } else {
                XCTAssertLessThan(media.width / scale, 160, "A phone row must leave a readable information column")
                XCTAssertGreaterThanOrEqual(title.frame.minX, image.frame.maxX - 1)
            }
            XCTAssertEqual(try require(app.staticTexts["validation.product.errors"]).label, "none")
            try saveSnapshot(app, name: "product-\(layout)-large")
        }
    }

    @MainActor func testLongProductCopyReflowsWithinNarrowAccessibilityLayout() throws {
        let title = "Travel camera with a weather sealed body and a versatile lens for everyday photographs"
        let specification = "Includes the camera, lens, battery and charger. The full supplied specification stays visible."
        let conditions = "Returns within 30 days · Ships in 2 days"
        for layout in ["horizontal", "compact"] {
            let ordinary = launch(scenario: "product-\(layout)-long")
            let ordinaryTitleHeight = try require(ordinary.staticTexts[title]).frame.height
            let app = launch(scenario: "product-\(layout)-long", typeSize: "accessibility2")
            let image = try require(app.buttons["Product front"])
            scrollTo(image, in: app)
            let pixels = try XCTUnwrap(image.screenshot().image.cgImage)
            let media = try XCTUnwrap(markerBounds(pixels, channel: 0))
            XCTAssertEqual(media.width / media.height, 1.5, accuracy: 0.03,
                           "\(layout) must reflow to vertical media at accessibility sizes")
            let heading = try require(app.staticTexts[title])
            let details = try require(app.staticTexts[specification])
            let terms = try require(app.staticTexts[conditions])
            let action = try require(app.buttons["View offer"])
            let readingFrame = image.frame
            XCTAssertGreaterThan(heading.frame.height, ordinaryTitleHeight,
                                 "The long heading must gain real laid-out height with Dynamic Type")
            XCTAssertGreaterThanOrEqual(heading.frame.minY, image.frame.maxY - 1)
            XCTAssertGreaterThanOrEqual(details.frame.minY, heading.frame.maxY - 1)
            XCTAssertGreaterThanOrEqual(terms.frame.minY, details.frame.maxY - 1)
            XCTAssertGreaterThanOrEqual(action.frame.minY, terms.frame.maxY - 1)
            try saveSnapshot(app, name: "product-\(layout)-accessibility2")

            // The complete card is taller than a phone viewport. Actually
            // scroll every supplied text and the action into view, keeping the
            // original full-label and unclipped horizontal-frame assertions.
            for element in [heading, details, terms, try require(app.staticTexts["Tax included"]), action] {
                scrollTo(element, in: app)
                XCTAssertTrue(element.isHittable, element.label)
                XCTAssertGreaterThan(element.frame.height, 0, element.label)
                XCTAssertGreaterThanOrEqual(element.frame.minX, readingFrame.minX - 1, element.label)
                XCTAssertLessThanOrEqual(element.frame.maxX, readingFrame.maxX + 1, element.label)
                XCTAssertGreaterThanOrEqual(element.frame.minY, app.frame.minY - 1, element.label)
                XCTAssertLessThanOrEqual(element.frame.maxY, app.frame.maxY + 1, element.label)
            }
            XCTAssertEqual(try require(app.staticTexts["validation.product.errors"]).label, "none")
        }
    }

    @MainActor func testAlbumSelectionSurvivesDataUpdateAndPurchaseDispatchesExactURL() throws {
        let destination = "https://example.com/offer?variant=alpha%2Fbeta&opaque=A%3DB#details"
        let app = launch(scenario: "product-album")
        let front = try require(app.buttons["Product front"])
        _ = try require(app.staticTexts["Camera"])
        let revision = try require(app.staticTexts["validation.product.document"]).label
        let actionCount = try require(app.staticTexts["validation.product.action-count"])
        XCTAssertEqual(actionCount.label, "0")
        scrollTo(front, in: app)
        let firstBounds = try XCTUnwrap(markerBounds(try XCTUnwrap(front.screenshot().image.cgImage), channel: 0))
        try saveSnapshot(app, name: "product-album-front")
        let next = try require(app.buttons["Next product image"])
        XCTAssertTrue(next.isEnabled)
        next.tap()
        let rear = try require(app.buttons["Product rear"])
        let secondImage = try XCTUnwrap(rear.screenshot().image.cgImage)
        let secondBounds = try XCTUnwrap(markerBounds(secondImage, channel: 2))
        XCTAssertNil(markerBounds(secondImage, channel: 0), "The first photo must actually leave the rendered media area")
        assertSameBounds(firstBounds, secondBounds)
        XCTAssertFalse(next.isEnabled, "The last image disables forward navigation")
        try saveSnapshot(app, name: "product-album-rear")

        let update = try require(app.buttons["validation.product.update-title"])
        scrollTo(update, in: app)
        update.tap()
        _ = try require(app.staticTexts["Updated camera"])
        _ = try require(app.buttons["Product rear"])
        scrollTo(rear, in: app)
        let updated = try XCTUnwrap(rear.screenshot().image.cgImage)
        assertSameBounds(secondBounds, try XCTUnwrap(markerBounds(updated, channel: 2)))
        XCTAssertNil(markerBounds(updated, channel: 0), "Updating product copy must not reset the selected photograph")
        XCTAssertEqual(app.staticTexts["validation.product.document"].label, revision,
                       "Image selection and a reactive field update retain the mounted document")
        XCTAssertEqual(actionCount.label, "0", "Image navigation must not dispatch a host business action")
        try saveSnapshot(app, name: "product-album-updated")

        let purchase = try require(app.buttons["View offer"])
        scrollTo(purchase, in: app)
        purchase.tap()
        let delivered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "1"), object: actionCount)
        XCTAssertEqual(XCTWaiter.wait(for: [delivered], timeout: 5), .completed)
        XCTAssertEqual(app.staticTexts["validation.product.action-type"].label, "open_url")
        XCTAssertEqual(app.staticTexts["validation.product.action-url"].label, destination)
        XCTAssertEqual(actionCount.label, "1", "One real purchase button tap dispatches exactly one action")
        XCTAssertEqual(app.staticTexts["validation.product.errors"].label, "none")
    }

    @MainActor private func require(_ element: XCUIElement,
        file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("Missing real application element: \(element)", file: file, line: line)
            throw ObservationFailure.missingElement
        }
        return element
    }

    private func assertSameBounds(_ lhs: CGRect, _ rhs: CGRect,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.minX, rhs.minX, accuracy: 2, file: file, line: line)
        XCTAssertEqual(lhs.minY, rhs.minY, accuracy: 2, file: file, line: line)
        XCTAssertEqual(lhs.width, rhs.width, accuracy: 2, file: file, line: line)
        XCTAssertEqual(lhs.height, rhs.height, accuracy: 2, file: file, line: line)
    }

    private func markerBounds(_ image: CGImage, channel: Int) -> CGRect? {
        guard let bitmap = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
            let bytes = bitmap.data else { return nil }
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = bytes.assumingMemoryBound(to: UInt8.self)
        var bounds = CGRect.null
        let others = [0, 1, 2].filter { $0 != channel }
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * bitmap.bytesPerRow + x * 4
                if pixels[offset + channel] > 200 && others.allSatisfy({ pixels[offset + $0] < 60 }) {
                    bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return bounds.isNull ? nil : bounds
    }

    private enum ObservationFailure: Error { case missingElement }
}
#endif
