import XCTest
import SwiftUI
@testable import SwiftIntelligentUI

final class TableLayoutTests: XCTestCase {
    func testDescriptionFillsSpaceWhileAmountKeepsItsIntrinsicWidth() {
        let widths = TableColumnWidths.resolve(ideal: [600, 84], numeric: [false, true], viewport: 320, minimum: 80, maximum: 180)
        XCTAssertEqual(widths, [236, 84])
        XCTAssertEqual(widths.reduce(0, +), 320)
    }
    func testWideTablesKeepReadableColumnsAndAllNumericTablesFill() {
        let wide = TableColumnWidths.resolve(ideal: [500, 400, 150, 100], numeric: [false, false, true, true], viewport: 320, minimum: 80, maximum: 180)
        XCTAssertGreaterThan(wide.reduce(0, +), 320)
        XCTAssertEqual(wide[2], 150)
        let numeric = TableColumnWidths.resolve(ideal: [80, 80], numeric: [true, true], viewport: 320, minimum: 80, maximum: 180)
        XCTAssertEqual(numeric.reduce(0, +), 320, accuracy: 0.01)
    }
    @MainActor func testNativeMultilineTableRendersWithoutCollapsingRows() throws {
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        state.setSource(#"root=Table(["项目","两人预留"],[["住宿：1间房×4晚，每晚不超过¥800","¥3,200"],["市内及机场交通","¥600"],["餐饮","¥1,500"]])"#)
        let renderer = ImageRenderer(content: OpenIntelligentUIContentView(state: state, library: library).frame(width: 320))
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 320)
        XCTAssertGreaterThan(image.height, 120)
    }
}
