import Combine
import SwiftLang
import SwiftUI
import XCTest

final class LibraryFacadeTests: XCTestCase {
    private func components(functions: [DefinedFunction] = []) throws -> OpenUIComponentLibrary {
        try OpenUIComponentLibrary(components: [
            OpenUIComponent(name: "ProbeText", description: "Display the supplied text.",
                            params: [OpenUIParameter.string("text")]) { context in
                Text(context.string("text") ?? "")
            }
        ], functions: functions, root: "ProbeText")
    }

    @MainActor func testCustomFunctionsUseRestoredNativeStringStateAndKeepDocumentsIndependent() throws {
        let uppercase = DefinedFunction(name: "FacadeUpper", description: "Uppercase text.",
                                        params: [OpenUIParameter.string("text")],
                                        returns: .object([.init(key: "type", value: .string("string"))])) { arguments in
            guard case .string(let text) = arguments["text"] ?? .null else { return .null }
            return .string(OpenUIString(text.displayString.uppercased()))
        }
        let library = OpenUILibrary(components: try components(functions: [uppercase]))
        let persisted: [String: Value] = ["$title": .string("restored")]
        let state = library.makeState(persistedState: persisted)
        let source = "$title = \"default\"\nroot = ProbeText(@FacadeUpper($title))"
        state.setSource(source)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertEqual(PropValue.string(try XCTUnwrap(state.root), "text"), "RESTORED")

        state.setState("$title", value: .string("edited"))
        XCTAssertEqual(PropValue.string(try XCTUnwrap(state.root), "text"), "EDITED")
        let restored = library.makeState(persistedState: state.snapshotState())
        restored.setSource(source)
        XCTAssertTrue(restored.errors.isEmpty, "\(restored.errors)")
        XCTAssertEqual(PropValue.string(try XCTUnwrap(restored.root), "text"), "EDITED")
        restored.setState("$title", value: .string("another document"))
        XCTAssertEqual(PropValue.string(try XCTUnwrap(restored.root), "text"), "ANOTHER DOCUMENT")
        XCTAssertEqual(PropValue.string(try XCTUnwrap(state.root), "text"), "EDITED")
    }

    @MainActor func testDocumentFunctionDefaultsRemainIndependentWithTheSameReader() throws {
        let defaultValue = Value.object([.init(key: "items", value: .array([.number(1), .number(2)]))])
        let returns = JSONValue.object([
            .init(key: "type", value: .string("object")),
            .init(key: "properties", value: .object([
                .init(key: "items", value: .object([.init(key: "default", value: .array([.number(1), .number(2)]))]))
            ])),
            .init(key: "required", value: .array([.string("items")]))
        ])
        let function = DefinedFunction(name: "DefaultPayload", description: "Fill a required return default.",
            params: [], returns: returns) { _ in .object([]) }
        let components = try OpenUIComponentLibrary(components: [
            OpenUIComponent(name: "ProbeValue", description: "Display a value.",
                params: [ParamDef(name: "value", required: true)]) { _ in EmptyView() }
        ], functions: [function], root: "ProbeValue")
        let library = OpenUILibrary(components: components)
        let source = "$enabled=true\nroot=ProbeValue($enabled ? @DefaultPayload() : {items:[9]})"
        let first = library.makeState()
        let second = OpenUILibrary(components: components).makeState()
        first.setSource(source)
        second.setSource(source)
        XCTAssertTrue(first.errors.isEmpty, "\(first.errors)")
        XCTAssertTrue(second.errors.isEmpty, "\(second.errors)")
        let left = try XCTUnwrap(PropValue.value(try XCTUnwrap(first.root), "value"))
        let right = try XCTUnwrap(PropValue.value(try XCTUnwrap(second.root), "value"))
        XCTAssertEqual(left, defaultValue)
        XCTAssertEqual(right, defaultValue)
        XCTAssertFalse(left.isSameValue(as: right), "A shared reader must not share runtime default objects")
        guard case .object(let leftFields) = left, case .object(let rightFields) = right else {
            return XCTFail("The function must actually produce object defaults")
        }
        let leftItems = try XCTUnwrap(leftFields["items"]), rightItems = try XCTUnwrap(rightFields["items"])
        XCTAssertFalse(leftItems.isSameValue(as: rightItems))
        first.setState("$enabled", value: .boolean(false))
        XCTAssertEqual(PropValue.value(try XCTUnwrap(first.root), "value"),
                       .object([.init(key: "items", value: .array([.number(9)]))]))
        XCTAssertEqual(PropValue.value(try XCTUnwrap(second.root), "value"), defaultValue)
        first.reset()
        XCTAssertEqual(PropValue.value(try XCTUnwrap(second.root), "value"), defaultValue)
    }

    @MainActor func testExtendedFacadeKeepsTheOriginalReaderSnapshot() throws {
        let originalComponents = try components()
        let original = OpenUILibrary(components: originalComponents)
        let extended = OpenUILibrary(components: try originalComponents.extending(overriding: [
            OpenUIComponent(name: "ProbeText", description: "A revised numeric reader.",
                            params: [OpenUIParameter.number("amount")]) { _ in EmptyView() }
        ]))
        for _ in 0..<2 {
            let first = original.makeState(), second = extended.makeState()
            first.setSource("root=ProbeText(\"original\")")
            second.setSource("root=ProbeText(7)")
            XCTAssertTrue(first.errors.isEmpty, "\(first.errors)")
            XCTAssertTrue(second.errors.isEmpty, "\(second.errors)")
            XCTAssertEqual(PropValue.string(try XCTUnwrap(first.root), "text"), "original")
            XCTAssertEqual(PropValue.value(try XCTUnwrap(second.root), "amount"), .number(7))
            XCTAssertNil(PropValue.value(try XCTUnwrap(second.root), "text"))
        }
        XCTAssertTrue(original.recognizesUI(in: "root=ProbeText(\"original\")"))
        XCTAssertTrue(extended.recognizesUI(in: "root=ProbeText(7)"))
        XCTAssertFalse(original.recognizesUI(in: "An ordinary paragraph."))
    }

    private actor RecordingProvider: ToolProvider {
        struct Call: Sendable {
            let name: OpenUIString
            let arguments: OpenUIObject
        }
        private(set) var calls: [Call] = []

        func callTool(name: OpenUIString, arguments: OpenUIObject) async throws -> Value {
            calls.append(Call(name: name, arguments: arguments))
            return .object([ObjectField(key: "label", value: .string("remote"))])
        }
    }

    @MainActor func testQueryProviderAndActionHandlerUseTheSamePersistedSession() async throws {
        let library = OpenUILibrary(components: try components())
        let provider = RecordingProvider()
        let persisted: [OpenUIString: Value] = ["$prefix": .string("restored")]
        let state = library.makeState(toolProvider: provider, persistedState: persisted)
        state.push("""
            $prefix = "default"
            data = Query("facade.load", {id: 7}, {label: "pending"})
            root = ProbeText($prefix + ":" + data.label)
            """)
        let rendered = expectation(description: "The supplied provider updates the document")
        let subscription = state.$root.filter { root in
            root.flatMap { PropValue.string($0, "text") } == "restored:remote"
        }.prefix(1).sink { _ in rendered.fulfill() }
        state.complete()
        await fulfillment(of: [rendered], timeout: 3)
        withExtendedLifetime(subscription) {}

        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertEqual(state.queryStates["data"]?.status, .success)
        XCTAssertEqual(PropValue.string(try XCTUnwrap(state.root), "text"), "restored:remote")
        let calls = await provider.calls
        XCTAssertEqual(calls.count, 1)
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.name, "facade.load")
        XCTAssertEqual(call.arguments.first(where: { $0.key == "id" })?.value, .number(7))

        var received: [ActionEvent] = []
        state.onAction = { received.append($0) }
        let dispatched = await state.triggerAction("Continue")
        XCTAssertEqual(dispatched.count, 1)
        XCTAssertEqual(received.count, 1)
        let action = try XCTUnwrap(received.first)
        XCTAssertEqual(action.type, "continue_conversation")
        XCTAssertEqual(action.humanFriendlyMessage, "Continue")
        XCTAssertEqual(action.formState?.first(where: { $0.0 == "$prefix" })?.1, .string("restored"))
    }
}
