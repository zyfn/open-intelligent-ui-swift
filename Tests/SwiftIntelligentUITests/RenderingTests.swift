import XCTest
import SwiftUI
import OpenUILang
import OpenUISwiftUI
@testable import SwiftIntelligentUI

final class RenderingTests: XCTestCase {
    @MainActor func testCheckboxActionUpdatesDerivedStateAndRejectsOldOrLiteralContexts() throws {
        let library = try IntelligentUILibrary(), state = library.makeState()
        state.setSource(source)
        let context = OpenUIComponentContext(element: try children(state)[0], registry: library.components.registry, state: state)
        CheckboxComponent.toggle(context)
        XCTAssertEqual(state.stateValue("$selected"), .boolean(true))
        XCTAssertEqual(PropValue.string(try children(state)[1], "text"), "已选")
        CheckboxComponent.toggle(context)
        XCTAssertEqual(state.stateValue("$selected"), .boolean(false))
        state.setSource(source)
        CheckboxComponent.toggle(context)
        XCTAssertEqual(state.stateValue("$selected"), .boolean(false))
        state.setSource("root=Col([Checkbox(true,\"只读\")])")
        let literal = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
        let readOnly = OpenUIComponentContext(element: literal, registry: library.components.registry, state: state)
        CheckboxComponent.toggle(readOnly)
        XCTAssertNil(readOnly.binding("checked"))
        XCTAssertEqual(readOnly.value("checked"), .boolean(true))
    }

    private let source = """
    root = Col([Title("组件验证"), Card([Checkbox($selected, "选中", true), Text($selected ? "已选" : "未选"), Button("重置", @Set($selected, false))], "soft")])
    $selected = false
    """

    @MainActor private func children(_ state: OpenUIState) throws -> [EvaluatedElement] {
        let root = try XCTUnwrap(state.root)
        let card = try XCTUnwrap(PropValue.children(root).last)
        return PropValue.children(card)
    }

    @MainActor func testBindingUpdatesDerivedContent() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource(source)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let checkbox = try XCTUnwrap(children(state).first)
        let context = OpenUIComponentContext(element: checkbox, registry: library.components.registry, state: state)
        XCTAssertTrue(context.canInteract)
        let binding = try XCTUnwrap(context.binding("checked"))
        binding.wrappedValue = .boolean(true)
        XCTAssertEqual(PropValue.string(try children(state)[1], "text"), "已选")
    }

    @MainActor func testChunkedInputMatchesCompleteInput() throws {
        let library = try IntelligentUILibrary()
        let complete = library.makeState()
        complete.setSource(source)
        let chunked = library.makeState()
        for character in source { chunked.push(String(character)) }
        chunked.complete()
        XCTAssertTrue(chunked.errors.isEmpty, "\(chunked.errors)")
        XCTAssertEqual(try children(complete).map(\.typeName), try children(chunked).map(\.typeName))
        XCTAssertEqual(PropValue.string(try children(complete)[1], "text"), PropValue.string(try children(chunked)[1], "text"))
        for state in [complete, chunked] {
            let checkbox = try XCTUnwrap(children(state).first)
            try XCTUnwrap(state.binding(for: checkbox, prop: "checked")).wrappedValue = .boolean(true)
        }
        XCTAssertEqual(PropValue.string(try children(complete)[1], "text"), "已选")
        XCTAssertEqual(PropValue.string(try children(chunked)[1], "text"), "已选")
    }

    @MainActor func testReplacedSourceRejectsOldBinding() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource(source)
        let context = OpenUIComponentContext(element: try children(state)[0], registry: library.components.registry, state: state)
        let binding = try XCTUnwrap(context.binding("checked"))
        state.setSource(source)
        XCTAssertFalse(context.canInteract)
        binding.wrappedValue = .boolean(true)
        XCTAssertEqual(state.stateValue("$selected"), .boolean(false))
    }

    @MainActor func testButtonActionUsesSDKState() async throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource(source)
        state.setState("$selected", value: .boolean(true))
        let context = OpenUIComponentContext(element: try children(state)[2], registry: library.components.registry, state: state)
        _ = await context.perform(try XCTUnwrap(context.action()))
        XCTAssertEqual(state.stateValue("$selected"), .boolean(false))
        XCTAssertEqual(PropValue.string(try children(state)[1], "text"), "未选")
    }

    @MainActor func testOriginalURLReachesExternalActionHandler() async throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        let url = "/products/a?sku=2&source=fixture"
        state.setSource("root = Col([Button(\"查看来源\", @OpenUrl(\"\(url)\"))])")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        var received: [ActionEvent] = []
        state.onAction = { received.append($0) }
        let button = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
        let context = OpenUIComponentContext(element: button, registry: library.components.registry, state: state)
        _ = await context.perform(try XCTUnwrap(context.action()))
        XCTAssertEqual(received.count, 1)
        let event = try XCTUnwrap(received.first)
        XCTAssertEqual(event.type, "open_url")
        XCTAssertEqual(event.params.first { $0.0 == "url" }?.1, .string(OpenUIString(url)))
    }

    @MainActor func testLiteralCheckboxHasNoWritableBinding() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource("root = Col([Checkbox(true, \"只读\")])")
        let checkbox = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
        let context = OpenUIComponentContext(element: checkbox, registry: library.components.registry, state: state)
        XCTAssertNil(context.binding("checked"))
    }

    @MainActor func testAppendingSourcePreservesUserInput() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.push("$selected = false\nroot = Col([Checkbox($selected, \"选择\"), Text($selected ? \"已选\" : \"未选\")])\n")
        let checkbox = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
        let context = OpenUIComponentContext(element: checkbox, registry: library.components.registry, state: state)
        XCTAssertTrue(context.canInteract)
        try XCTUnwrap(context.binding("checked")).wrappedValue = .boolean(true)
        state.push("detail = Text(\"后续内容\")\n")
        state.complete()
        XCTAssertEqual(state.stateValue("$selected"), .boolean(true))
        let text = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).last)
        XCTAssertEqual(PropValue.string(text, "text"), "已选")
    }

    @MainActor func testIncompleteActionIsVisibleButCannotDispatch() async throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        var received: [ActionEvent] = []
        state.onAction = { received.append($0) }
        state.push("root = Col([Button(\"打开\", @OpenUrl(\"https://example.com")
        let incomplete = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
        let preview = OpenUIComponentContext(element: incomplete, registry: library.components.registry, state: state)
        XCTAssertFalse(preview.canInteract)
        if let action = preview.action() { _ = await preview.perform(action) }
        XCTAssertTrue(received.isEmpty)
        state.push("\"))])\n")
        state.complete()
        let button = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
        let context = OpenUIComponentContext(element: button, registry: library.components.registry, state: state)
        XCTAssertTrue(context.canInteract)
        if let action = context.action() { _ = await context.perform(action) }
        XCTAssertEqual(received.count, 1)
    }

    @MainActor func testNativeRenderProducesNonemptyImageInBothSchemes() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource(source)
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: IntelligentUIView(state: state, library: library)
                .environment(\.colorScheme, scheme).frame(width: 360).padding(16))
            let image = try XCTUnwrap(renderer.cgImage)
            XCTAssertGreaterThan(image.width, 0)
            XCTAssertGreaterThan(image.height, 100)
        }
    }
}
