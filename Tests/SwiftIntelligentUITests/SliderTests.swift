import XCTest
import OpenUILang
import OpenUISwiftUI
@testable import SwiftIntelligentUI

final class SliderTests: XCTestCase {
    func testInvalidRangesNeverReachNativeSlider() {
        for (low, high, step) in [(0.0, 0.0, 1.0), (2, 1, 1), (0, 10, 0), (0, 10, -1), (0, 10, 11), (0, .infinity, 1), (-Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, 1)] {
            XCTAssertNil(SliderRange(minimum: low, maximum: high, step: step))
        }
    }

    func testOutOfRangeValuesArePresentedWithinBounds() throws {
        let range = try XCTUnwrap(SliderRange(minimum: 1, maximum: 10, step: 0.5))
        XCTAssertEqual(range.clamped(-100), 1)
        XCTAssertEqual(range.clamped(100), 10)
        XCTAssertEqual(range.clamped(.nan), 1)
        XCTAssertEqual(range.clamped(4.5), 4.5)
    }

    @MainActor func testNumericBindingRecalculatesVisibleResult() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource("root = Col([Slider($n, 1, 10, 1, \"人数\", \"人\"), Text(\"合计 \" + ($n * 12))])\n$n = 2")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let root = try XCTUnwrap(state.root)
        let slider = try XCTUnwrap(PropValue.children(root).first)
        let context = OpenUIComponentContext(element: slider, registry: library.components.registry, state: state)
        try XCTUnwrap(context.binding("value")).wrappedValue = .number(4)
        let text = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).last)
        XCTAssertEqual(PropValue.string(text, "text"), "合计 48")
    }
}
