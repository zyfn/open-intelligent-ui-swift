import XCTest
import SwiftUI
import OpenUILang
import OpenUISwiftUI
@testable import SwiftIntelligentUI

final class LayoutTests: XCTestCase {
    func testWrappingKeepsMultipleItemsOnEachLine() {
        let geometry = RowGeometry(sizes: Array(repeating: CGSize(width: 40, height: 20), count: 5),
                                   width: 100, gap: 10, alignment: "start", justification: "start", wraps: true)
        XCTAssertEqual(geometry.frames.map(\.minX), [0, 50, 0, 50, 0])
        XCTAssertEqual(geometry.frames.map(\.minY), [0, 0, 30, 30, 60])
        XCTAssertEqual(geometry.size, CGSize(width: 100, height: 80))
    }

    func testRowAlignmentAndJustification() {
        let sizes = [CGSize(width: 20, height: 10), CGSize(width: 30, height: 30)]
        let between = RowGeometry(sizes: sizes, width: 100, gap: 10, alignment: "end", justification: "between", wraps: true)
        XCTAssertEqual(between.frames[0], CGRect(x: 0, y: 20, width: 20, height: 10))
        XCTAssertEqual(between.frames[1].maxX, 100)
        let center = RowGeometry(sizes: sizes, width: 100, gap: 10, alignment: "stretch", justification: "center", wraps: false)
        XCTAssertEqual(center.frames[0].minX, 20)
        XCTAssertEqual(center.frames.map(\.height), [30, 30])
    }

    func testSingleBetweenItemAndEmptyRow() {
        let geometry = RowGeometry(sizes: [CGSize(width: 40, height: 20)], width: 100, gap: 12, alignment: "start", justification: "between", wraps: true)
        XCTAssertEqual(geometry.frames[0].minX, 0)
        XCTAssertEqual(RowGeometry(sizes: [], width: 100, gap: 12, alignment: "start", justification: "start", wraps: true).size, .zero)
    }

    func testAdaptiveGridHonorsMaximumColumnsAndNarrowWidth() {
        let grid = EqualGridLayout(columns: 3, minimumWidth: 120, gap: 12)
        XCTAssertEqual(grid.columnCount(width: 1000), 3)
        XCTAssertEqual(grid.columnCount(width: 260), 2)
        XCTAssertEqual(grid.columnCount(width: 120), 1)
        XCTAssertEqual(grid.columnCount(width: 20), 1)
        XCTAssertEqual(EqualGridLayout(columns: 2, minimumWidth: nil, gap: 12).columnCount(width: 1000), 2)
    }

    @MainActor func testLayoutProgramAndExpandedParametersRenderAtSeveralWidths() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource(Self.program)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        for width in [240.0, 390.0, 840.0] {
            for size in [DynamicTypeSize.large, .accessibility2] {
                let renderer = ImageRenderer(content: IntelligentUIView(state: state, library: library)
                    .environment(\.dynamicTypeSize, size).frame(width: width).padding(12))
                let image = try XCTUnwrap(renderer.cgImage)
                XCTAssertEqual(image.width, Int(width) + 24)
                XCTAssertGreaterThan(image.height, 100)
                XCTAssertLessThan(image.height, 10_000)
            }
        }
    }

    @MainActor func testExtendedSignaturesPreservePositionalArguments() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource("root = Col([Text(\"123\", \"sm\", \"muted\", \"medium\", false, true, true, 2), Image(\"\", \"缺图\", 1, 24, \"contain\"), Button(\"禁用\", @Set($n, 1), \"outline\", \"danger\", \"lg\", \"check\", true, true)])\n$n = 0")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let children = PropValue.children(try XCTUnwrap(state.root))
        XCTAssertEqual(children[0].props.first { $0.0 == "tabularNums" }?.1, .boolean(true))
        XCTAssertEqual(children[0].props.first { $0.0 == "maxLines" }?.1, .number(2))
        XCTAssertEqual(children[1].props.first { $0.0 == "radius" }?.1, .number(24))
        XCTAssertEqual(children[2].props.first { $0.0 == "disabled" }?.1, .boolean(true))
    }

    func testTextLineLimitHandlesUnboundedAndExtremeValues() {
        XCTAssertNil(TextLineLimit.resolve(nil))
        XCTAssertNil(TextLineLimit.resolve(0))
        XCTAssertNil(TextLineLimit.resolve(.infinity))
        XCTAssertEqual(TextLineLimit.resolve(2.6), 3)
        XCTAssertEqual(TextLineLimit.resolve(Double.greatestFiniteMagnitude), 1000)
    }

    @MainActor func testLegacyFieldAndContainerSignaturesRemainValid() throws {
        let state = try IntelligentUILibrary().makeState()
        state.setSource(#"""
        root = Col([Input($name,"名称","text","旧占位"),TextArea($note,"备注","可选",3),Select($choice,["A","B"],"尺寸","请选择"),Form([Button("提交",@Set($name,"示例"))]),Image("","缺图",1,"md","contain"),Chart("bar",[{x:"A",v:1}],"x",["v"],"number","USD",false,240)])
        $name = ""
        $note = ""
        $choice = "A"
        """#)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let children = PropValue.children(try XCTUnwrap(state.root))
        XCTAssertEqual(PropValue.string(children[0], "placeholder"), "旧占位")
        XCTAssertNil(children[0].props.first { $0.0 == "error" })
        XCTAssertEqual(PropValue.string(children[2], "placeholder"), "请选择")
        XCTAssertEqual(PropValue.children(children[3]).count, 1)
        XCTAssertNil(children[3].props.first { $0.0 == "status" })
        XCTAssertEqual(PropValue.string(children[4], "fit"), "contain")
        XCTAssertNil(children[5].props.first { $0.0 == "selected" })
    }

    private static let program = """
    root = Col([Title("布局与参数验证", "xl", "ink"), Row([Text("第一项"), Text("第二项长文字"), Icon("check"), Text("第三项")], 2, "center", "between", true), Grid([Card([Text("长标题可以自然换行，不裁切信息。")]), Card([Text("第二张卡")]), Card([Text("第三张卡")])], 3, 180, 3), Box([Text("表面与边框"), Image("", "缺少图片", 2, 12, "contain")], "col", 2, 3, "surface", "lg", true), Button("原生按钮", @Set($selected, true), "outline", "success", "lg", "check", false, true)])
    $selected = false
    """
}
