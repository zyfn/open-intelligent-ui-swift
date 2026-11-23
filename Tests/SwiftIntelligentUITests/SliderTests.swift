import XCTest
import SwiftUI
import CoreGraphics
import SwiftLang
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
        let library = try OpenIntelligentUIComponents()
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

    @MainActor func testRegisteredMarksMirrorInTheRenderedLayoutWithoutChangingTheValue() throws {
        let library = try OpenIntelligentUIComponents()
        var theme = OpenIntelligentUITheme()
        theme.secondaryText = Color(red: 1, green: 0, blue: 0)
        theme.actionAccent = .blue

        func markCenter(_ mark: Int, direction: LayoutDirection) throws -> CGFloat {
            let state = library.makeState()
            defer { state.reset() }
            state.setSource("root = Slider($n, 0, 100, 1, null, null, [{value:\(mark),label:\"●\"}])\n$n = 40")
            XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
            let renderer = ImageRenderer(content: OpenIntelligentUIContentView(state: state, library: library)
                .openIntelligentUITheme(theme).environment(\.layoutDirection, direction)
                .environment(\.dynamicTypeSize, .large).environment(\.colorScheme, .light)
                .frame(width: 320).background(.white))
            renderer.scale = 1
            let rendered = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(rendered.width, 320)
            XCTAssertEqual(state.stateValue("$n"), .number(40))
            let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            let output = try XCTUnwrap(CGContext(data: nil, width: rendered.width, height: rendered.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo))
            output.draw(rendered, in: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
            let pixels = try XCTUnwrap(output.data).assumingMemoryBound(to: UInt8.self)
            var minimumX = rendered.width, maximumX = -1
            for y in 0..<rendered.height {
                for x in 0..<rendered.width {
                    let offset = y * output.bytesPerRow + x * 4
                    if pixels[offset] > 200 && pixels[offset + 1] < 60 && pixels[offset + 2] < 60 {
                        minimumX = min(minimumX, x); maximumX = max(maximumX, x)
                    }
                }
            }
            return try XCTUnwrap(maximumX >= minimumX ? CGFloat(minimumX + maximumX) / 2 : nil,
                                 "The reference mark must be visible in \(direction)")
        }

        let lowLTR = try markCenter(20, direction: .leftToRight)
        let highLTR = try markCenter(80, direction: .leftToRight)
        let lowRTL = try markCenter(20, direction: .rightToLeft)
        let highRTL = try markCenter(80, direction: .rightToLeft)
        XCTAssertLessThan(lowLTR, highLTR)
        XCTAssertGreaterThan(lowRTL, highRTL)
        XCTAssertEqual(lowLTR + lowRTL, 319, accuracy: 2)
        XCTAssertEqual(highLTR + highRTL, 319, accuracy: 2)
    }
}
