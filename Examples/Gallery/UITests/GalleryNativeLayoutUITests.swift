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
        let first = app.buttons["openui.choice.choice.a"]
        let second = app.buttons["openui.choice.choice.b"]
        let third = app.buttons["openui.choice.choice.c"]
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
