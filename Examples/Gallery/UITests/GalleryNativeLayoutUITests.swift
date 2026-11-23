import UIKit
import Vision
import XCTest

final class GalleryNativeLayoutUITests: GalleryNativeUITestCase {
    @MainActor func testCompositeCardCopyAndActionsRemainReadableAtPhoneWidth() throws {
        for typeSize in ["large", "accessibility2"] {
            let app = launch(scenario: "layout-composite", typeSize: typeSize)
            defer { app.terminate() }
            let firstTitle = app.staticTexts["A quiet room by the lake"].firstMatch
            let firstCopy = app.staticTexts["A complete explanation remains visible."].firstMatch
            let firstAction = app.buttons["Book first room"].firstMatch
            let secondTitle = app.staticTexts["Another room close to the station"].firstMatch
            let secondCopy = app.staticTexts["The second offer keeps its own action."].firstMatch
            let secondAction = app.buttons["Book second room"].firstMatch
            for element in [firstTitle, firstCopy, firstAction, secondTitle, secondCopy, secondAction] {
                scrollTo(element, in: app)
                XCTAssertGreaterThan(element.frame.height, 0)
                XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX - 1)
                XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX + 1)
            }
            // Geometry is asserted while each element is on screen. Reading
            // order is independently observed from the real automation tree;
            // it must not depend on a clipped offscreen element's frame.
            try assertReadingOrder([
                "A quiet room by the lake", "A complete explanation remains visible.", "Book first room",
                "Another room close to the station", "The second offer keeps its own action.", "Book second room",
            ], in: app)
            XCTAssertTrue(secondAction.isHittable)
            XCTAssertGreaterThanOrEqual(secondAction.frame.height, 44)
            try saveSnapshot(app, name: "layout-composite-\(typeSize)")
        }
    }

    @MainActor func testActualButtonLabelsRemainReachableAfterRowReflow() throws {
        let app = launch(scenario: "layout-buttons")
        defer { app.terminate() }
        let first = app.buttons["One"].firstMatch
        let second = app.buttons["Two"].firstMatch
        let third = app.buttons["A substantially longer third action"].firstMatch
        for element in [first, second, third] {
            scrollTo(element, in: app)
            XCTAssertTrue(element.isHittable)
        }
        let arrange = app.buttons["layout.arrange-row"]
        scrollTo(arrange, in: app)
        arrange.tap()
        XCTAssertTrue(app.staticTexts["row"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 1)
        XCTAssertGreaterThan(second.frame.minX, first.frame.maxX)
        XCTAssertGreaterThanOrEqual(third.frame.minY, first.frame.maxY + 11)
        for element in [first, second, third] {
            XCTAssertTrue(element.isHittable)
            XCTAssertGreaterThanOrEqual(element.frame.height, 44)
            XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX + 1)
        }
        try saveSnapshot(app, name: "layout-buttons-reflow")
    }

    @MainActor func testOptionLabelsAndTheirVisibleDescriptionRemainReadable() throws {
        let app = launch(scenario: "layout-options")
        defer { app.terminate() }
        let options = app.buttons.matching(identifier: "openui.field.choice")
        let first = options.matching(NSPredicate(format: "label == %@", "First")).firstMatch
        let second = options.matching(NSPredicate(format: "label == %@", "Second")).firstMatch
        let third = options.matching(NSPredicate(format: "label == %@", "Third")).firstMatch
        scrollTo(first, in: app)
        XCTAssertEqual(first.label, "First")

        // OptionCards intentionally expose the subtitle as an accessibility
        // hint, not a second label. XCUIElement has no public hint accessor.
        // Observe the actual screenshot text rather than synthesizing AX nodes
        // or reading the source value as evidence that the copy was displayed.
        let bitmap = try XCTUnwrap(first.screenshot().image.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: bitmap, options: [:]).perform([request])
        let visibleText = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
        XCTAssertTrue(visibleText.contains("A complete recommendation with a useful reason."),
            "The actual option screenshot must contain its explanation: \(visibleText)")
        try saveSnapshot(app, name: "layout-options-reading")

        for (element, title) in [(second, "Second"), (third, "Third")] {
            scrollTo(element, in: app)
            XCTAssertEqual(element.label, title)
            XCTAssertTrue(element.isHittable)
            XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX - 1)
            XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX + 1)
        }
        try assertReadingOrder(["First", "Second", "Third"], in: app)
    }

    @MainActor func testCarouselRespondsToHorizontalDragsAndPreservesVerticalReading() throws {
        let app = launch(scenario: "layout-pager")
        defer { app.terminate() }
        let pager = app.descendants(matching: .any).matching(identifier: "openui.carousel.pager").firstMatch
        let first = app.staticTexts["First carousel page"].firstMatch
        let second = app.staticTexts["Second carousel page"].firstMatch
        scrollTo(pager, in: app)
        expectPagerValue("1 / 3", on: pager)
        assertCurrentPageTitle(first, pager: pager)
        let initialY = first.frame.minY

        // These are real touches inside the SDK carousel, not accessibility
        // adjustment actions or writes to a test-host selection variable.
        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            .press(forDuration: 0.05,
                thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)),
                withVelocity: .slow, thenHoldForDuration: 0.15)
        expectPagerValue("2 / 3", on: pager)
        assertCurrentPageTitle(second, pager: pager)
        assertNotFullyInsidePager(first, pager: pager)
        XCTAssertEqual(second.frame.minY, initialY, accuracy: 2,
            "Horizontal paging must not scroll the surrounding document")
        try saveSnapshot(app, name: "layout-pager-next-page")

        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .press(forDuration: 0.05,
                thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)),
                withVelocity: .slow, thenHoldForDuration: 0.15)
        expectPagerValue("1 / 3", on: pager)
        assertCurrentPageTitle(first, pager: pager)
        assertNotFullyInsidePager(second, pager: pager)
        XCTAssertEqual(first.frame.minY, initialY, accuracy: 2)

        let before = first.frame
        let start = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -100)),
            withVelocity: .slow, thenHoldForDuration: 0.2)
        // Inspect the real element after the gesture has ended. No scrollTo
        // helper or expected-geometry polling may move the viewport for us.
        XCTAssertEqual(pager.value as? String, "1 / 3")
        assertCurrentPageTitle(first, pager: pager)
        assertNotFullyInsidePager(second, pager: pager)
        XCTAssertLessThan(first.frame.minY, before.minY - 40,
            "A vertical drag starting inside the pager must scroll the surrounding document")
        XCTAssertEqual(first.frame.minX, before.minX, accuracy: 2,
            "The vertical reading gesture must not displace the horizontal track")
        try saveSnapshot(app, name: "layout-pager-vertical-reading")
    }

    @MainActor private func assertCurrentPageTitle(_ element: XCUIElement, pager: XCUIElement,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.exists, file: file, line: line)
        XCTAssertTrue(element.isHittable, file: file, line: line)
        let frame = element.frame
        let viewport = pager.frame
        XCTAssertFalse(frame.isEmpty, file: file, line: line)
        XCTAssertTrue(viewport.contains(frame),
            "The current page title must fit completely inside the pager: title=\(frame), viewport=\(viewport)",
            file: file, line: line)
    }

    @MainActor private func assertNotFullyInsidePager(_ element: XCUIElement, pager: XCUIElement,
        file: StaticString = #filePath, line: UInt = #line) {
        // Carousel intentionally shows a trailing peek. Its off-page automation
        // nodes can remain in the tree, and isHittable can fail while computing
        // their activation points. Observe actual geometry without requiring
        // those nodes to disappear or forbidding the SDK's partial preview.
        guard element.exists else { return }
        let frame = element.frame
        let viewport = pager.frame
        XCTAssertTrue(frame.isEmpty || !viewport.contains(frame),
            "A neighboring page title must not be fully inside the pager: title=\(frame), viewport=\(viewport)",
            file: file, line: line)
    }

    @MainActor private func expectPagerValue(_ value: String, on pager: XCUIElement,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(pager.waitForExistence(timeout: 5), file: file, line: line)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: pager)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
            "Expected real pager value \(value); observed \(String(describing: pager.value))", file: file, line: line)
    }

    @MainActor private func assertReadingOrder(_ labels: [String], in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = app.descendants(matching: .any).allElementsBoundByIndex.map(\.label)
        let positions = try labels.map { label in
            try XCTUnwrap(actual.firstIndex(of: label), "Missing accessible copy: \(label); tree: \(actual)",
                file: file, line: line)
        }
        for (first, second) in zip(positions, positions.dropFirst()) {
            XCTAssertLessThan(first, second, "The semantic reading order must follow the supplied content",
                file: file, line: line)
        }
    }
}
