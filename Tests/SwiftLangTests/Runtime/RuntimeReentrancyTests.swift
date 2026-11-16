import Combine
import SwiftUI
import XCTest
@testable import SwiftLang

final class RuntimeReentrancyTests: XCTestCase {
    private func schema() -> LibrarySchema {
        LibrarySchema(components: ["Box": [ParamDef(name: "value", required: true)]], callDefs: builtinCallDefs)
    }
    @MainActor private func value(_ state: OpenUIState) -> Value? {
        state.root.flatMap { PropValue.value($0, "value") }
    }

    @MainActor func testRootWillSetReplacementFinishesWithOnlyTheNewDocument() throws {
        let state = OpenUIState(schema: schema())
        state.setSource("root=Box(\"initial\")")
        var replaced = false
        var parsed: [Value] = []
        state.onParseResult = { _ in if let value = self.value(state) { parsed.append(value) } }
        let subscription = state.$root.dropFirst().sink { root in
            guard !replaced, root.flatMap({ PropValue.value($0, "value") }) == .string("obsolete") else { return }
            replaced = true
            XCTAssertEqual(self.value(state), .string("initial"), "Published retains its normal willSet read semantics")
            state.setSource("root=Box(\"replacement\")")
            XCTAssertEqual(self.value(state), .string("initial"), "The reentrant mutation runs after this setter finishes")
        }
        defer { subscription.cancel() }
        state.setSource("root=Box(\"obsolete\")")
        XCTAssertTrue(replaced)
        XCTAssertEqual(value(state), .string("replacement"))
        XCTAssertEqual(parsed, [.string("replacement")], "An obsolete source must not report the newer parse a second time")
        XCTAssertTrue(state.canExecuteActions)
    }

    @MainActor func testCompletionWillSetResetDoesNotRepublishItsOldRoot() {
        let state = OpenUIState(schema: schema())
        state.push("root=Box(\"stream\")")
        var reset = false, parses = 0
        state.onParseResult = { _ in parses += 1 }
        let subscription = state.$isComplete.dropFirst().sink { complete in
            guard complete, !reset else { return }
            reset = true
            state.reset()
        }
        defer { subscription.cancel() }
        state.complete()
        XCTAssertTrue(reset)
        XCTAssertNil(state.root)
        XCTAssertFalse(state.isComplete)
        XCTAssertFalse(state.isInterrupted)
        XCTAssertEqual(parses, 0)
        state.push("root=Box(\"next\")")
        state.complete()
        XCTAssertEqual(value(state), .string("next"))
    }

    @MainActor func testSameEpochStateWriteFromRootSubscriberWinsOverTheOuterPublication() {
        let state = OpenUIState(schema: schema())
        state.setSource("$value=0\nroot=Box($value)")
        let epoch = state.sourceRevision
        var changed = false
        var snapshots: [Value] = []
        state.onStateUpdate = { if let value = $0["$value"] { snapshots.append(value) } }
        let subscription = state.$root.dropFirst().sink { root in
            guard !changed, root.flatMap({ PropValue.value($0, "value") }) == .number(1) else { return }
            changed = true
            state.setState("$value", value: .number(2))
        }
        defer { subscription.cancel() }
        state.setState("$value", value: .number(1))
        XCTAssertEqual(state.sourceRevision, epoch)
        XCTAssertEqual(state.stateValue("$value"), .number(2))
        XCTAssertEqual(value(state), .number(2), "Store and published root must describe the same completed mutation")
        XCTAssertEqual(snapshots, [.number(2)])
    }

    @MainActor func testOnErrorRecoveryDoesNotDeliverTheReplacementParseTwice() {
        let state = OpenUIState(schema: schema())
        var recovered = false
        var parsed: [Value] = []
        state.onError = { errors in
            guard !errors.isEmpty, !recovered else { return }
            recovered = true
            state.setSource("root=Box(\"recovered\")")
        }
        state.onParseResult = { _ in if let value = self.value(state) { parsed.append(value) } }
        state.setSource("root=UnknownComponent()")
        XCTAssertTrue(recovered)
        XCTAssertEqual(value(state), .string("recovered"))
        XCTAssertEqual(parsed, [.string("recovered")])
        XCTAssertTrue(state.errors.isEmpty)
    }

    @MainActor func testParseCallbackCanAppendTheNextChunkBeforeOuterPushReturns() {
        let state = OpenUIState(schema: schema())
        var parses = 0
        state.onParseResult = { _ in
            parses += 1
            if parses == 1 { state.push(" tail\")") }
        }
        state.push("root=Box(\"first")
        XCTAssertEqual(parses, 2)
        XCTAssertEqual(value(state), .string("first tail"))
        XCTAssertFalse(state.isComplete)
        state.complete()
        XCTAssertEqual(parses, 3)
    }

    @MainActor func testSynchronousReplayOfTheSameSourceDoesNotAbandonItsPublication() {
        let state = OpenUIState(schema: schema())
        state.setSource("root=Box(\"initial\")")
        let source = "root=Box(\"stream\")"
        var parses = 0, observedChanges = 0
        state.onParseResult = { _ in parses += 1 }
        let subscription = state.objectWillChange.sink {
            observedChanges += 1
            state.setSource(source, streaming: true)
            state.push("")
        }
        state.setSource(source, streaming: true)
        subscription.cancel()
        XCTAssertGreaterThan(observedChanges, 0)
        XCTAssertEqual(value(state), .string("stream"))
        XCTAssertEqual(parses, 1)
        XCTAssertFalse(state.isComplete)
        XCTAssertTrue(state.errors.isEmpty)
    }

    @MainActor func testCompletionSubscriberReplayingCompleteDoesNotDropTheFinalParse() {
        let state = OpenUIState(schema: schema())
        state.push("root=Box(\"stream\")")
        var parses = 0
        state.onParseResult = { _ in parses += 1 }
        let subscription = state.$isComplete.dropFirst().sink { if $0 { state.complete() } }
        defer { subscription.cancel() }
        state.complete()
        XCTAssertTrue(state.isComplete)
        XCTAssertTrue(state.canExecuteActions)
        XCTAssertEqual(parses, 1)
    }

    @MainActor func testReentrantResetPushInitializeAndCompleteKeepTheirFIFOPrerequisites() {
        let state = OpenUIState(schema: schema())
        state.setSource("root=Box(\"initial\")")
        state.initializeField(form: "form", name: "field", value: .string("old"))
        var replaced = false
        let subscription = state.$root.dropFirst().sink { root in
            guard !replaced, root.flatMap({ PropValue.value($0, "value") }) == .string("obsolete") else { return }
            replaced = true
            state.reset()
            state.push("root=Box(\"new stream\")")
            state.initializeField(form: "form", name: "field", value: .string("new"))
            state.complete()
        }
        defer { subscription.cancel() }
        state.setSource("root=Box(\"obsolete\")")
        XCTAssertEqual(value(state), .string("new stream"))
        XCTAssertEqual(state.fieldValue(form: "form", name: "field"), .string("new"))
        XCTAssertTrue(state.isComplete)
        XCTAssertTrue(state.canExecuteActions)
    }

    @MainActor func testQueuedOldContextFieldWriteCannotEnterAReplacementDocument() throws {
        let state = OpenUIState(schema: schema())
        state.setSource("$field=\"initial\"\nroot=Box(\"initial\")")
        var replaced = false
        let subscription = state.$root.dropFirst().sink { root in
            guard !replaced, let root, PropValue.value(root, "value") == .string("obsolete") else { return }
            replaced = true
            let context = OpenUIComponentContext(element: root, registry: [:], state: state)
            let oldBinding = context.fieldBinding("$field")
            state.setSource("$field=\"replacement\"\nroot=Box(\"replacement\")")
            oldBinding.wrappedValue = .string("stale")
        }
        defer { subscription.cancel() }
        state.setSource("$field=\"initial\"\nroot=Box(\"obsolete\")")
        XCTAssertEqual(value(state), .string("replacement"))
        XCTAssertEqual(state.stateValue("$field"), .string("replacement"))
    }

    @MainActor func testQueuedReactiveBindingChecksItsSourceAgainBeforeEvaluation() throws {
        let schema = LibrarySchema(components: ["Input": [ParamDef(name: "value", required: true, isBindable: true)]],
            callDefs: builtinCallDefs)
        let state = OpenUIState(schema: schema)
        state.setSource("$count=0\n$trigger=0\nroot=Input($count=$value+2)")
        let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: [:], state: state)
        let binding = try XCTUnwrap(context.binding("value"))
        var replaced = false
        let subscription = state.$root.dropFirst().sink { _ in
            guard !replaced, state.stateValue("$trigger") == .number(1) else { return }
            replaced = true
            state.setSource("$count=100\nroot=Input($count)")
            binding.wrappedValue = .number(3)
        }
        defer { subscription.cancel() }
        state.setState("$trigger", value: .number(1))
        XCTAssertTrue(replaced)
        XCTAssertEqual(state.stateValue("$count"), .number(100))
    }

    @MainActor func testQueuedFieldWritesMergeAgainstTheStoreWhenTheyActuallyExecute() throws {
        let state = OpenUIState(schema: schema())
        state.setSource("root=Box(\"initial\")")
        var changed = false
        let subscription = state.$root.dropFirst().sink { root in
            guard !changed, root.flatMap({ PropValue.value($0, "value") }) == .string("trigger") else { return }
            changed = true
            state.setFieldValue(form: "form", name: "first", value: .string("A"))
            state.setFieldValue(form: "form", name: "second", value: .string("B"))
        }
        defer { subscription.cancel() }
        state.setSource("root=Box(\"trigger\")")
        XCTAssertEqual(state.fieldValue(form: "form", name: "first"), .string("A"))
        XCTAssertEqual(state.fieldValue(form: "form", name: "second"), .string("B"))
    }
}
