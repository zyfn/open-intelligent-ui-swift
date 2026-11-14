import XCTest
import SwiftUI
import OpenUILang
import OpenUICore
@testable import OpenIntelligentSwiftUI

final class InputTests: XCTestCase {
    func testNumericDraftsDoNotReplaceLastValidValue() {
        XCTAssertNil(InputEditing.numericValue("-"))
        XCTAssertNil(InputEditing.numericValue("1e"))
        XCTAssertNil(InputEditing.numericValue("nan"))
        XCTAssertNil(InputEditing.numericValue("1e9999"))
        XCTAssertEqual(InputEditing.numericValue(""), .null)
        XCTAssertEqual(InputEditing.numericValue("1."), .number(1))
        XCTAssertEqual(InputEditing.numericValue("-1,234.5"), .number(-1234.5))
        XCTAssertEqual(InputEditing.text(.number(12)), "12")
    }

    @MainActor func testInputAndTextAreaBindingsUpdateText() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource("root = Col([Input($name, \"名称\"), TextArea($note, \"备注\", \"请输入\", 3), Text($name + \" / \" + $note)])\n$name = \"初始\"\n$note = \"\"")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let children = PropValue.children(try XCTUnwrap(state.root))
        try XCTUnwrap(state.binding(for: children[0], prop: "value")).wrappedValue = .string("相机")
        try XCTUnwrap(state.binding(for: children[1], prop: "value")).wrappedValue = .string("第一行\n第二行")
        let text = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).last)
        XCTAssertEqual(PropValue.string(text, "text"), "相机 / 第一行\n第二行")
    }

    @MainActor func testChoiceSchemasBindingsAndDuplicateValues() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource("root = Col([Select($v, [\"a\", {value: \"b\", label: \"B\"}, {value: \"b\", label: \"Duplicate\"}], \"选择\", \"请选择\"), SegmentedControl($v, [\"a\", \"b\"], true), RadioGroup($v, [{value: \"a\", label: \"A\", description: \"说明\"}, \"b\"], \"模式\", \"cards\"), Text($v)])\n$v = \"unknown\"")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let children = PropValue.children(try XCTUnwrap(state.root))
        let context = OpenUIComponentContext(element: children[0], registry: library.components.registry, state: state)
        let options = ChoiceOption.decode(context.value("options"))
        XCTAssertEqual(options.map(\.id), ["a", "b"])
        XCTAssertEqual(options.last?.label, "B")
        XCTAssertEqual(state.stateValue("$v"), .string("unknown"))
        try XCTUnwrap(context.binding("value")).wrappedValue = .string("b")
        let updated = PropValue.children(try XCTUnwrap(state.root))
        for component in updated.prefix(3) {
            XCTAssertEqual(try XCTUnwrap(state.binding(for: component, prop: "value")).wrappedValue, .string("b"))
        }
        XCTAssertEqual(PropValue.string(updated[3], "text"), "b")
    }

    @MainActor func testAllNewControlsRenderAtAccessibilitySize() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource("root = Col([Caption(\"说明\"), Label(\"字段\"), Input($v, \"单行\"), TextArea($v, \"多行\"), Select($v, [\"a\", \"b\"]), SegmentedControl($v, [\"a\", \"b\"]), RadioGroup($v, [\"a\", \"b\"], \"单选\", \"pills\"), Link(\"来源\", \"/source\")])\n$v = \"a\"")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let renderer = ImageRenderer(content: IntelligentUIView(state: state, library: library)
            .environment(\.dynamicTypeSize, .accessibility2).frame(width: 320))
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertGreaterThan(image.height, 100)
    }

    func testSourceURLRejectsUnsafeSchemesAndKeepsRelativePaths() {
        XCTAssertTrue(SourceURL.isActionable("/products/a?offer=2"))
        XCTAssertTrue(SourceURL.isActionable("https://example.com/a"))
        XCTAssertFalse(SourceURL.isActionable(" javascript:alert(1)"))
        XCTAssertFalse(SourceURL.isActionable("file:///etc/passwd"))
        XCTAssertFalse(SourceURL.isActionable("data:text/html,test"))
        XCTAssertFalse(SourceURL.isActionable(""))
        XCTAssertFalse(SourceURL.isActionable("https://example.com\n/a"))
    }

    @MainActor func testExternalResetReachesInputBinding() async throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource("root = Col([Input($name), Input($amount, \"金额\", \"number\"), Button(\"重置\", Action([@Set($name, \"初始\"), @Set($amount, 12)]))])\n$name = \"修改\"\n$amount = 99")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let children = PropValue.children(try XCTUnwrap(state.root))
        _ = await state.perform(try XCTUnwrap(PropValue.actionPlan(children[2], "action")))
        XCTAssertEqual(state.stateValue("$name"), .string("初始"))
        XCTAssertEqual(state.stateValue("$amount"), .number(12))
    }
}
