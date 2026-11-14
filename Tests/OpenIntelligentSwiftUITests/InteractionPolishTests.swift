import XCTest
import SwiftUI
import OpenUILang
import OpenSwiftUI
@testable import OpenIntelligentSwiftUI

final class InteractionPolishTests: XCTestCase {
    @MainActor func testUndeclaredProductFieldsAreReportedInsteadOfDropped() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource(#"root=ProductCard({id:"old",title:"商品",images:[],offers:[{id:"a",priceText:"¥1"}]})"#)
        let root = try XCTUnwrap(state.root)
        XCTAssertTrue(library.undeclaredFieldIssues(in: root).contains { $0.contains("product.offers") })
        let context = OpenUIComponentContext(element: root, registry: library.components.registry, state: state)
        XCTAssertNil(ProductCardData(context.value("product")))
        state.setSource(#"root=ProductCard({id:"new",title:"商品",images:[{url:"https://example.com/a.jpg",alt:"图片",extra:"not declared"}],priceText:"¥1"})"#)
        XCTAssertTrue(library.undeclaredFieldIssues(in: try XCTUnwrap(state.root)).contains { $0.contains("images[0].extra") })
        state.setSource(#"root=ProductCard({id:"new",title:"商品",images:[],priceText:"¥1"})"#)
        XCTAssertTrue(library.undeclaredFieldIssues(in: try XCTUnwrap(state.root)).isEmpty)
    }

    func testCarouselFitsNarrowAndAccessibilityWidths() {
        XCTAssertEqual(CarouselMetrics.width(preferred: 288, available: 320, accessibility: false), 272)
        XCTAssertEqual(CarouselMetrics.width(preferred: 288, available: 240, accessibility: false), 204)
        XCTAssertEqual(CarouselMetrics.width(preferred: 288, available: 100, accessibility: false), 85)
        XCTAssertEqual(CarouselMetrics.width(preferred: 288, available: 360, accessibility: true), 360)
    }

    func testCodeColoringPreservesLiteralURLsAndUnicode() throws {
        let source = "let url = \"https://example.com/中文\" // comment\nlet n = 12"
        let theme = IntelligentUITheme()
        let output = CodeColoring.highlight(source, language: "swift", theme: theme)
        XCTAssertEqual(String(output.characters), source)
        let url = try XCTUnwrap(output.range(of: "https://example.com/中文"))
        XCTAssertEqual(output[url].foregroundColor, theme.codeLiteral)
        let comment = try XCTUnwrap(output.range(of: "// comment"))
        XCTAssertEqual(output[comment].foregroundColor, theme.secondaryText)
        let plain = CodeColoring.highlight(source, language: "unrecognized", theme: theme)
        XCTAssertEqual(plain.runs.count, 1)
    }

    @MainActor func testCodeCopyDispatchesExactOriginalText() async throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource(#"root = Code("示例")"#)
        let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.components.registry, state: state)
        var events: [ActionEvent] = []
        state.onAction = { events.append($0) }
        let source = "let 中文 = \"a\"\n  // 保留缩进\n"
        _ = await context.perform(CodeComponent.copyAction(source))
        XCTAssertEqual(events.first?.type, "CopyToClipboard")
        XCTAssertEqual(events.first?.params.first?.1, .string(OpenUIString(source)))
    }

    func testChartAxisAbbreviationDoesNotReplacePreciseInspectionValues() {
        let chinese = Locale(identifier: "zh_CN")
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(ChartData.axisLabel(20000, kind: "number", currency: nil, locale: chinese), "2万")
        XCTAssertEqual(ChartData.axisLabel(20000, kind: "number", currency: nil, locale: english), "20K")
        XCTAssertEqual(ChartData.axisLabel(25, kind: "percent", currency: nil, locale: english), "25%")
        let exact = ChartData.formatted(12345.67, kind: "number", currency: nil)
        XCTAssertTrue(exact.contains("12"))
        XCTAssertTrue(exact.contains("345"))
        XCTAssertTrue(exact.contains("67"))
    }

    func testChartSelectionAndDonutHole() {
        let points = [ChartData.Point(id: "a", label: "A", x: 1, series: "v", value: 1), ChartData.Point(id: "b", label: "B", x: 5, series: "v", value: 1)]
        XCTAssertEqual(ChartInspection.nearest(to: 4.8, points: points), "B")
        XCTAssertNil(ChartInspection.nearest(to: 0, points: []))
        XCTAssertNil(ChartInspection.sector(at: .init(x: 50, y: 50), size: .init(width: 100, height: 100), points: points, donut: true))
        XCTAssertEqual(ChartInspection.sector(at: .init(x: 90, y: 50), size: .init(width: 100, height: 100), points: points, donut: false), "A")
        XCTAssertEqual(ChartInspection.sector(at: .init(x: 10, y: 50), size: .init(width: 100, height: 100), points: points, donut: false), "B")
    }

    @MainActor func testFormFeedbackUsesOrdinaryTextAndChartHasNoPrivateBinding() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource(#"""
        root = Col([Form([Input($name,"名称","text","")]),$error == "" ? null : Text($error,"sm","danger"),Chart("line",[{x:"A",v:1},{x:"B",v:2}],"x",["v"],"number",null,false,240)])
        $name = ""
        $error = "必填"
        """#)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let children = PropValue.children(try XCTUnwrap(state.root))
        XCTAssertNil(PropValue.value(try XCTUnwrap(children.first), "status"))
        XCTAssertEqual(PropValue.string(children[1], "text"), "必填")
        let chart = try XCTUnwrap(children.last)
        let context = OpenUIComponentContext(element: chart, registry: library.components.registry, state: state)
        XCTAssertNil(context.binding("selected"))
        XCTAssertNil(PropValue.value(chart, "selected"))
    }

    @MainActor func testLongStreamPreservesFirstChildIdentity() throws {
        let state = try IntelligentUILibrary().makeState()
        let source = "root = Col([" + (0..<80).map { "Text(\"第 \($0) 段逐步生成的内容。\")" }.joined(separator: ",") + "])"
        let characters = Array(source)
        var firstID: String?
        for start in stride(from: 0, to: characters.count, by: 113) {
            state.push(String(characters[start..<min(start + 113, characters.count)]))
            if let root = state.root, let first = OpenUIRenderChild.children(of: .array(PropValue.children(root).map(Value.element))).first {
                let identity = String(describing: first.id)
                if let firstID { XCTAssertEqual(identity, firstID) } else { firstID = identity }
            }
        }
        state.complete()
        XCTAssertTrue(state.errors.isEmpty)
        XCTAssertEqual(PropValue.children(try XCTUnwrap(state.root)).count, 80)
        XCTAssertNotNil(firstID)
    }
}
