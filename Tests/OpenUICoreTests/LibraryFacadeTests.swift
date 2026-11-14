import Combine
import OpenUICore
import OpenUILang
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
