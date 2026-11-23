import XCTest

final class GalleryNativeControlUITests: GalleryNativeUITestCase {
    @MainActor func testRadioCheckboxSelectAndSwitchUseTheRealSelectionControls() throws {
        let app = launch(scenario: "controls-selection")
        let state = app.staticTexts["validation.controls.state"]
        expectLabel(state, equals: "pace=easy;quiet=false;route=;reminders=false")
        let easy = app.buttons["Easy"], full = app.buttons["Full"]
        // The checkbox retains Toggle's native Switch accessibility semantics.
        let quiet = app.switches["openui.field.preferences"]
        XCTAssertTrue(easy.isSelected)
        XCTAssertFalse(full.isSelected)
        XCTAssertEqual(quiet.label, "Quiet")
        XCTAssertEqual(quiet.value as? String, "0")

        full.tap()
        quiet.tap()
        expectLabel(state, equals: "pace=full;quiet=true;route=;reminders=false")
        XCTAssertTrue(full.isSelected)
        XCTAssertFalse(easy.isSelected)
        XCTAssertEqual(quiet.value as? String, "1")
        try saveSnapshot(app, name: "radio-and-checkbox-selection")

        let route = app.buttons["openui.field.route"]
        scrollTo(route, in: app)
        XCTAssertEqual(route.value as? String, "Choose route")
        route.tap()
        let bike = app.buttons["Bike"]
        XCTAssertTrue(bike.waitForExistence(timeout: 5), app.debugDescription)
        bike.tap()
        expectLabel(state, equals: "pace=full;quiet=true;route=bike;reminders=false")
        XCTAssertEqual(route.value as? String, "Bike")

        let external = app.buttons["validation.controls.external"]
        scrollTo(external, in: app)
        external.tap()
        expectLabel(state, equals: "pace=easy;quiet=true;route=walk;reminders=true")
        XCTAssertTrue(easy.isSelected)
        XCTAssertFalse(full.isSelected)
        XCTAssertEqual(quiet.value as? String, "1")
        XCTAssertEqual(route.value as? String, "Walk")
        XCTAssertEqual(app.switches["Reminders"].value as? String, "1")
        expectLabel(app.staticTexts["validation.controls.identity"], equals: "root=true;revision=true")
        expectLabel(app.staticTexts["validation.controls.action"], equals: "count=0")
        try saveSnapshot(app, name: "switch-and-select-store-update")
    }

    @MainActor func testFormFocusesItsInvalidInputAndSubmitsTheEditedPayloadOnce() throws {
        let app = launch(scenario: "controls-form")
        let input = app.textFields["openui.field.email"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), app.debugDescription)
        let native = app.staticTexts["validation.controls.native"]
        expectLabel(native, containing: "input=true;same=true;")
        expectLabel(native, containing: "keyboard=email")
        app.buttons["Send"].tap()
        let error = app.descendants(matching: .any).matching(identifier: "openui.error.email").firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5), app.debugDescription)
        expectLabel(app.staticTexts["validation.controls.action"], equals: "count=0")
        expectLabel(native, containing: "focused=true")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        try saveSnapshot(app, name: "form-invalid-focused")

        // Do not tap the input: typing must use the focus requested by validation.
        input.typeText("native@example.invalid")
        expectLabel(app.staticTexts["validation.controls.state"], equals: "email=native@example.invalid")
        expectExistence(error, false)
        expectLabel(native, containing: "input=true;same=true;")
        app.buttons["Send"].tap()
        expectLabel(app.staticTexts["validation.controls.action"],
            equals: "count=1;type=continue_conversation;form=contact;message=Contact details;value=native@example.invalid")
        XCTAssertEqual(input.value as? String, "native@example.invalid")
        expectLabel(native, containing: "input=true;same=true;")
        try saveSnapshot(app, name: "form-valid-submitted")
    }

    @MainActor func testSliderBlocksInvalidDraftAndSubmitsTheCorrectedNativeValue() throws {
        let app = launch(scenario: "controls-slider")
        // NativeFieldView supplies the field identifier to the mounted editor.
        let input = app.textFields["openui.field.amount"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), app.debugDescription)
        expectLabel(app.staticTexts["validation.controls.native"], containing: "input=true;same=true;")
        XCTAssertEqual(input.value as? String, "10")
        replaceText(in: input, with: "-")
        app.buttons["Send amount"].tap()
        let error = app.descendants(matching: .any).matching(identifier: "openui.error.amount").firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(input.value as? String, "-")
        expectLabel(app.staticTexts["validation.controls.state"], equals: "amount=[10]")
        expectLabel(app.staticTexts["validation.controls.action"], equals: "count=0")
        try saveSnapshot(app, name: "slider-invalid-draft")

        replaceText(in: input, with: "37")
        app.buttons["Send amount"].tap()
        expectLabel(app.staticTexts["validation.controls.action"],
            equals: "count=1;type=continue_conversation;form=quote;message=Amount details;value=[37]")
        expectLabel(app.staticTexts["validation.controls.state"], equals: "amount=[37]")
        expectLabel(app.staticTexts["validation.controls.native"], containing: "input=true;same=true;")
        expectExistence(error, false)
        try saveSnapshot(app, name: "slider-valid-submitted")
    }

    @MainActor func testSmallModalPresentsNativeDetentsAndCloseWritesItsBinding() throws {
        try assertModal(size: "sm", detents: 2)
    }

    @MainActor func testLargeModalPresentsTheLargeDetentAndCloseWritesItsBinding() throws {
        try assertModal(size: "lg", detents: 1)
    }

    @MainActor private func assertModal(size: String, detents: Int) throws {
        let app = launch(scenario: "controls-modal-\(size)", width: 390)
        expectLabel(app.staticTexts["validation.controls.state"], equals: "modal-open=false")
        app.buttons["Open details"].tap()
        XCTAssertTrue(app.staticTexts["Inside the modal"].waitForExistence(timeout: 5), app.debugDescription)
        let inspection = app.staticTexts.matching(NSPredicate(format: "label == %@",
            "native detents=\(detents);large=true;grabber=true")).firstMatch
        XCTAssertTrue(inspection.waitForExistence(timeout: 8), app.debugDescription)
        let close = app.buttons["Close"]
        XCTAssertTrue(close.isHittable)
        XCTAssertGreaterThan(close.frame.width, 0)
        XCTAssertGreaterThan(close.frame.height, 0)
        XCTAssertTrue(app.windows.firstMatch.frame.intersects(close.frame))
        try saveSnapshot(app, name: "modal-\(size)-presented")
        close.tap()
        expectExistence(close, false)
        expectLabel(app.staticTexts["validation.controls.state"], equals: "modal-open=false")
        expectLabel(app.staticTexts["validation.controls.action"], equals: "count=0")
        XCTAssertTrue(app.staticTexts["Underlying page"].exists)
    }

    @MainActor private func replaceText(in input: XCUIElement, with text: String) {
        let current = input.value as? String ?? ""
        // The endpoint is right aligned. Tap after its final glyph so deletion
        // begins at the end, then type through the real keyboard input path.
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }

    @MainActor private func expectLabel(_ element: XCUIElement, equals value: String,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed,
            "Expected \(value); observed \(element.label)", file: file, line: line)
    }

    @MainActor private func expectLabel(_ element: XCUIElement, containing value: String,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed,
            "Expected \(value); observed \(element.label)", file: file, line: line)
    }

    @MainActor private func expectExistence(_ element: XCUIElement, _ exists: Bool,
        file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == %@", NSNumber(value: exists)), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed, file: file, line: line)
    }
}
