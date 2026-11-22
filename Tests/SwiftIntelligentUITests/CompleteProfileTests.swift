import XCTest
import SwiftUI
import SwiftLang
@testable import SwiftIntelligentUI

final class CompleteProfileTests: XCTestCase {
    @MainActor func testSearchCapabilityRequiresExplicitProvider() throws {
        let provider = OpenIntelligentUIImageSearch { _ in .init(url: "https://example.com/photo.jpg", alt: "来源") }
        let enabled = try OpenIntelligentUIComponents(imageSearch: provider)
        XCTAssertEqual(enabled.specification.components.count, 60)
        XCTAssertEqual(enabled.readerSpecification.components.count, 60)
        XCTAssertEqual(Set(enabled.readerSpecification.components.map(\.name)), Set(enabled.specification.components.map(\.name)))
        XCTAssertNotNil(enabled.components.registry["SearchImage"])
        XCTAssertNil(try OpenIntelligentUIComponents().components.registry["SearchImage"])
        XCTAssertEqual(enabled.specification.functions.count, 59)
        XCTAssertEqual(enabled.specification.actions.map(\.name), ["CopyToClipboard"])
    }
    @MainActor func testReadingDataAndDrawingContracts() throws {
        let library = try OpenIntelligentUIComponents()
        let programs = [
            #"root = Col([Markdown("**原生**阅读"), Quote("引用", "出处"), Badge("完成","success","check"), List([ListItem("第一项","说明"),"第二项"],"number",true), Code("let x = 1","swift"), Math("E=mc^2"),Image("https://example.com/photo.jpg","示例",1,"md","cover")])"#,
            #"root = Col([Table(["名称","价格"],[["A",12],["B",24]]),Chart("bar",[{name:"A",value:12},{name:"B",value:24}],"name",["value"])])"#,
            #"root = Col([Svg([Circle(20,20,10,"info"),Ellipse(50,20,10,5),Rect(0,50,20,10),Line(0,0,10,10),Path("M0 0 L10 10"),Polyline("0,0 10,5"),Polygon("0,0 10,0 5,10"),G([SvgText("字",20,60)],"translate(1 2)")],"0 0 100 100"),HtmlView("<p>内容</p>"),YouTube("invalid")])"#,
            #"""
            root = Col([Map([MapMarker("A",30,120),MapMarker("B",31,121)],true,$selected), DatePicker($date),Timer($seconds),Flashcard("正面","背面"),Popover("说明","详情"),Celebration(true),Form([Input($name)]),IconButton("check",@Set($seconds,3),"设置"),Pressable([Text("选择")],@Set($seconds,4)),Divider(),Row([Text("左"),Spacer(),Text("右")]),Carousel([Text("一"),Text("二")])
            $selected="A"
            $date="2026-11-03"
            $seconds=5
            $name="名称"
            """#
        ]
        for program in programs {
            let state = library.makeState(); state.setSource(program)
            XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
            XCTAssertNotNil(state.root)
        }
    }
    func testSVGDoesNotAllowMarkupOrResourceAttributes() {
        let node = EvaluatedElement(typeName: "SvgText", props: [("text", .string("<script>alert(1)</script>")), ("x", .number(0)), ("y", .number(0)), ("fill", .string("url(https://example.com/a)"))])
        let output = SVGMarkup.render(node)
        XCTAssertFalse(output.contains("<script>"))
        XCTAssertFalse(output.contains("https://"))
        XCTAssertTrue(output.contains("&lt;script&gt;"))
    }
    func testInvalidCoordinatesDatesAndVideoIDs() {
        XCTAssertNil(CalendarDate.parse("2026-02-30"))
        XCTAssertEqual(CalendarDate.parse("2026-11-03").map(CalendarDate.string), "2026-11-03")
        XCTAssertNil(YouTubeVideo.id("https://not-youtube.example/watch?v=abcdefghijk"))
        XCTAssertEqual(YouTubeVideo.id("https://youtu.be/abcdefghijk"), "abcdefghijk")
        // 53df45b map.tsx consumes marker elements; map-utils.ts rejects
        // latitude outside [-90, 90] during rendering, not through the schema.
        let invalid: Value = .array([.element(EvaluatedElement(typeName: "MapMarker", props: [
            ("label", .string("A")), ("lat", .number(91)), ("lng", .number(120))
        ]))])
        XCTAssertTrue(MapPoint.decode(invalid).isEmpty)
    }
    func testChartOmitsUnknownValuesRatherThanInventingZero() {
        let data: Value = .array([
            .object([.init(key: "x", value: .string("A")), .init(key: "v", value: .number(12))]),
            .object([.init(key: "x", value: .string("B")), .init(key: "v", value: .null)])
        ])
        let chart = ChartData(rows: data, x: "x", series: .array([.string("v")]))
        XCTAssertEqual(chart.points.count, 1); XCTAssertEqual(chart.omitted, 1)
        XCTAssertEqual(chart.points.first?.value, 12)
    }
    @MainActor func testQuotedChineseChartKeysResolveToData() throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource(#"""
        root=Col([Chart("bar",rows,"月份",["收入","成本"])])
        rows=[{"月份":"一月","收入":12000,"成本":7200},{"月份":"二月","收入":15600,"成本":8100}]
        """#)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let chart = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
        let context = OpenUIComponentContext(element: chart, registry: library.components.registry, state: state)
        let data = ChartData(rows: context.value("data"), x: context.string("x"), series: context.value("series"))
        XCTAssertEqual(data.points.count, 4)
        XCTAssertEqual(data.points.first?.label, "一月")
        XCTAssertEqual(data.points.first?.value, 12000)
    }
    func testMathProducesMathMLRatherThanLiteralDelimiters() throws {
        let typesetter = try MathTypesetter()
        let output = try typesetter.render("E=mc^2", inline: false)
        XCTAssertTrue(output.contains("<math"))
        XCTAssertTrue(output.contains("<msup>"))
        XCTAssertFalse(output.contains("$$"))
        let fraction = try typesetter.render("\\frac{a}{b}", inline: true)
        XCTAssertTrue(fraction.contains("<mfrac>"))
        XCTAssertThrowsError(try typesetter.render("\\badcommand{", inline: false))
    }
    func testTableRowSlotsSurviveReevaluatedArrayInstances() {
        let identities = TableRowIdentities()
        let columns: Value = .array([.string("名称")])
        let old = TableData(columns: columns, rows: .array([.array([.string("A")])]), identity: identities.id)
        let updated = TableData(columns: columns, rows: .array([.array([.string("B")])]), identity: identities.id)
        XCTAssertEqual(old.rows.first?.id, updated.rows.first?.id)
    }
    @MainActor func testNativeChartsRenderEveryKind() throws {
        let library = try OpenIntelligentUIComponents()
        for kind in ["bar", "line", "area", "pie", "donut", "scatter"] {
            let state = library.makeState()
            let data = kind == "scatter" ? "[{x:1,v:2},{x:2,v:4}]" : "[{x:\"A\",v:2},{x:\"B\",v:4}]"
            state.setSource("root=Col([Chart(\"\(kind)\",\(data),\"x\",[\"v\"])])")
            XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
            let renderer = ImageRenderer(content: OpenIntelligentUIContentView(state: state, library: library).frame(width: 360))
            XCTAssertNotNil(renderer.cgImage, kind)
        }
    }
}
