import Combine
import OpenUICore
import OpenUILang
import SwiftUI
import XCTest

/// These tests deliberately import neither component library. Custom names,
/// definitions, state and actions must work through the public Core API alone.
final class CoreRuntimeIndependenceTests: XCTestCase {
    private enum OptionalContextKey: OpenUIContextKey {
        static let defaultValue: String? = "library default"
    }

    func testTypedContextCanExplicitlyClearAnOptionalLibraryDefault() {
        var values = OpenUIContextValues()
        XCTAssertEqual(values[OptionalContextKey.self], "library default")
        values[OptionalContextKey.self] = nil
        XCTAssertNil(values[OptionalContextKey.self])
    }

    @MainActor private func counterLibrary() throws -> OpenUIComponentLibrary {
        try OpenUIComponentLibrary(components: [
            OpenUIComponent(name: "ProbeCounter", description: "A client-owned counter", params: [
                OpenUIParameter.string("title"),
                OpenUIParameter.number("value", required: true),
                OpenUIParameter.action("action", required: true)
            ]) { context in
                Text(context.string("title") ?? "")
            }
        ], root: "ProbeCounter")
    }

    @MainActor func testCustomLibraryRunsStateAndActionsWithoutEitherUILibrary() async throws {
        let library = try counterLibrary()
        XCTAssertNotNil(library.registry["ProbeCounter"])
        XCTAssertNil(library.registry["Button"])
        let state = OpenUIState(schema: library.library.toSchema())
        state.setSource("""
        $count = 1
        root = ProbeCounter("Counter", $count, Action([@Set($count, $count + 1), @ToAssistant("Saved", $count)]))
        """)
        let root = try XCTUnwrap(state.root)
        XCTAssertEqual(root.typeName, "ProbeCounter")
        XCTAssertEqual(PropValue.value(root, "value"), .number(1))
        XCTAssertTrue(state.errors.isEmpty)
        let events = await state.perform(try XCTUnwrap(PropValue.actionPlan(root, "action")))
        XCTAssertEqual(state.stateValue("$count"), .number(2))
        XCTAssertEqual(PropValue.value(try XCTUnwrap(state.root), "value"), .number(2))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.humanFriendlyMessage, "Saved")

        let restored = OpenUIState(schema: library.library.toSchema(), persistedState: state.snapshotState())
        restored.setSource("$count = 1\nroot = ProbeCounter(\"Restored\", $count, @ToAssistant(\"Again\"))")
        XCTAssertEqual(PropValue.value(try XCTUnwrap(restored.root), "value"), .number(2))
        state.reset()
        XCTAssertNil(state.root)
        XCTAssertEqual(restored.stateValue("$count"), .number(2), "Separate Core sessions cannot reset one another")
    }

    @MainActor func testStreamingSnapshotsDoNotReparseAnUnchangedClientBuffer() throws {
        let library = try counterLibrary()
        let state = OpenUIState(schema: library.library.toSchema())
        let source = "$count = 3\nroot = ProbeCounter(\"Streaming\", $count, @ToAssistant(\"Done\"))"
        state.setSource(source, streaming: true)
        let root = try XCTUnwrap(state.root)
        let revision = state.sourceRevision
        var parses = 0
        var updates = 0
        state.onParseResult = { _ in parses += 1 }
        let subscription = state.objectWillChange.sink { updates += 1 }
        defer { subscription.cancel() }
        for _ in 0..<50 { state.setSource(source, streaming: true) }
        XCTAssertEqual(parses, 0)
        XCTAssertEqual(updates, 0)
        XCTAssertEqual(state.sourceRevision, revision)
        XCTAssertTrue(state.root === root)
        state.complete()
        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(PropValue.value(try XCTUnwrap(state.root), "value"), .number(3))
    }
}
