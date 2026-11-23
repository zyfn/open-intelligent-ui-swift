import XCTest

/// Real app automation. Geometry/identity tests that need in-process UIKit
/// access remain in the SDK targets; this target observes the app's real AX.
class GalleryNativeUITestCase: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor func launch(scenario: String, typeSize: String = "large", width: Int = 320) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["OPENUI_UI_TEST_SCENARIO"] = scenario
        app.launchEnvironment["OPENUI_UI_TEST_SIZE"] = typeSize
        app.launchEnvironment["OPENUI_UI_TEST_WIDTH"] = String(width)
        app.launchEnvironment["OPENUI_RUNTIME_TELEMETRY_ENABLED"] = "0"
        app.launch()
        XCTAssertTrue(app.staticTexts["validation.ready"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.staticTexts["validation.failure"].exists, app.debugDescription)
        return app
    }

    @MainActor func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription)
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<10 {
            let viewport = scrollView.frame.intersection(app.windows.firstMatch.frame).insetBy(dx: 0, dy: 2)
            let frame = element.frame
            let fits = frame.height <= viewport.height
            if element.isHittable && (!fits || (frame.minY >= viewport.minY && frame.maxY <= viewport.maxY)) {
                return
            }
            let offset = frame.minY < viewport.minY
                ? viewport.minY - frame.minY + 8 : viewport.maxY - frame.maxY - 8
            let distance = max(-viewport.height * 0.6, min(viewport.height * 0.6, offset))
            let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)))
        }
        XCTAssertTrue(element.isHittable, "Element did not become hittable: \(element.debugDescription)")
        let viewport = scrollView.frame.intersection(app.windows.firstMatch.frame)
        if element.frame.height <= viewport.height {
            XCTAssertGreaterThanOrEqual(element.frame.minY, viewport.minY - 1)
            XCTAssertLessThanOrEqual(element.frame.maxY, viewport.maxY + 1)
        }
    }

    @MainActor func saveSnapshot(_ app: XCUIApplication, name: String) throws {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let root = ProcessInfo.processInfo.environment["OPENUI_SNAPSHOT_DIR"], !root.isEmpty else { return }
        let directory = URL(fileURLWithPath: root).appendingPathComponent("ios-ui", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"))
    }
}
