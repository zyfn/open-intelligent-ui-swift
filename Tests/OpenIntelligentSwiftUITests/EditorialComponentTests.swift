import XCTest
import OpenUILang
import OpenUICore
@testable import OpenIntelligentSwiftUI

final class EditorialComponentTests: XCTestCase {
    func testLeadingEditorialColumnsRemainSideBySideOnPhoneWidths() {
        for width in [280.0, 320.0, 353.0, 680.0] {
            let columns = EditorialRowMetrics.columns(width: width, preferred: 116, gap: 16)
            XCTAssertLessThanOrEqual(columns.image, width * 0.34 + 0.01)
            XCTAssertGreaterThan(columns.text, columns.image)
            XCTAssertEqual(columns.image + columns.text + 16, width, accuracy: 0.01)
        }
    }
    @MainActor func testEditorialContentAndSourcesKeepOriginalData() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource(#"root=ImageText({image:{url:"https://example.com/photo.jpg",alt:"原始图片"},title:"1. 标题",body:"正文",subtitle:"说明",caption:"补充",url:"/details/a"},"leading",[Citation([{title:"来源A",url:"/source/a"},{title:"来源B",url:"https://example.com/b"}])])"#)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertTrue(library.validationIssues(in: try XCTUnwrap(state.root)).isEmpty)
        let footer = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root), "footer").first)
        let context = OpenUIComponentContext(element: footer, registry: library.components.registry, state: state)
        XCTAssertEqual(CitationSource.decode(context.value("sources")).map(\.url), ["/source/a", "https://example.com/b"])
    }
    func testSourcesDeduplicateWithoutInventingReferences() {
        let source: Value = .object([.init(key: "title", value: .string("原始来源")), .init(key: "url", value: .string("/source"))])
        XCTAssertEqual(CitationSource.decode(.array([source, source])).count, 1)
        XCTAssertTrue(CitationSource.decode(.array([])).isEmpty)
        XCTAssertEqual(CitationSource(title: "site", url: "https://notwww.example/path").domain, "notwww.example")
    }
    func testProgressIsBoundedAndUnknownRemainsIndeterminate() {
        XCTAssertEqual(ProgressReading.fraction(value: 45, maximum: 100), 0.45)
        XCTAssertEqual(ProgressReading.fraction(value: 200, maximum: 100), 1)
        XCTAssertNil(ProgressReading.fraction(value: nil, maximum: 100))
        XCTAssertNil(ProgressReading.fraction(value: 1, maximum: 0))
    }
    @MainActor func testDisclosureCanBeControlledByHostState() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource(#"""
        root=Disclosure("行程详情",[Text("详情")],$open)
        $open=false
        """#)
        XCTAssertTrue(state.errors.isEmpty)
        let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.components.registry, state: state)
        try XCTUnwrap(context.binding("expanded")).wrappedValue = .boolean(true)
        XCTAssertEqual(state.stateValue("$open"), .boolean(true))
    }
}
