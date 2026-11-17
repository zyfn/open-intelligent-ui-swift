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

    @MainActor func testWriteCompletionsAcknowledgeCanonicalValuesBeforePublicStateUpdates() throws {
        let schema = LibrarySchema(components: ["Input": [ParamDef(name: "value", required: true, isBindable: true)]],
            callDefs: builtinCallDefs)
        for writer in ["reactive", "field", "formField"] {
            let state = OpenUIState(schema: schema)
            state.setSource("$count=10\nroot=Input($count=$value-1)")
            let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: [:], state: state,
                exactFormName: writer == "formField" ? "form" : nil)
            var receipts: [Value?] = []
            var events: [String] = []
            let completion: (Value?) -> Void = { value in
                receipts.append(value)
                events.append("accepted")
            }
            let binding: Binding<Value>
            if writer == "reactive" {
                binding = try XCTUnwrap(context.binding("value", completion: completion))
            } else {
                binding = context.fieldBinding("amount", completion: completion)
            }
            state.onStateUpdate = { _ in
                XCTAssertEqual(receipts, [.number(10)], writer)
                events.append("published")
            }
            defer { state.onStateUpdate = nil }

            // The reactive write normalizes 11 to the already stored 10. Field
            // receipts expose that same value, without their Store wrappers.
            binding.wrappedValue = .number(writer == "reactive" ? 11 : 10)

            XCTAssertEqual(receipts, [.number(10)], writer)
            XCTAssertEqual(events, ["accepted", "published"], writer)
            XCTAssertEqual(state.stateValue("$count"), .number(10), writer)
            if writer != "reactive" {
                XCTAssertEqual(state.fieldValue(form: context.exactFormName, name: "amount"), .number(10), writer)
            }
            XCTAssertFalse(state.isInterrupted, writer)
            XCTAssertTrue(state.errors.isEmpty, writer)
        }
    }

    @MainActor func testQueuedWriteCompletionsRejectRetiredTargetsAndOversizedValuesOnce() throws {
        let schema = LibrarySchema(components: [
            "Stack": [ParamDef(name: "children", required: true)],
            "Input": [ParamDef(name: "value", required: true, isBindable: true)],
            "Box": [ParamDef(name: "value", required: true)]
        ], callDefs: builtinCallDefs)
        var oversized = Value.number(1)
        for _ in 0..<300 { oversized = .array([oversized]) }
        XCTAssertTrue(nativeValueExceedsLimits(oversized))
        for writer in ["binding", "reactive", "field", "formField"] {
            for retire in [true, false] {
                let label = "\(writer), \(retire ? "retired" : "budget")"
                let state = OpenUIState(schema: schema)
                state.setSource("""
                $shown=true
                $count=10
                $trigger=0
                root=Stack($shown ? [Input($count),Input($count=$value+2),Box("field")] : [])
                """)
                let index = writer == "binding" ? 0 : writer == "reactive" ? 1 : 2
                let element = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).dropFirst(index).first)
                let context = OpenUIComponentContext(element: element, registry: [:], state: state,
                    exactFormName: writer == "formField" ? "form" : nil)
                var receipts: [Value?] = []
                let completion: (Value?) -> Void = { receipts.append($0) }
                let binding: Binding<Value>
                if writer == "binding" || writer == "reactive" {
                    binding = try XCTUnwrap(context.binding("value", completion: completion))
                } else {
                    binding = context.fieldBinding("amount", completion: completion)
                }
                var queued = false
                let subscription = state.$root.dropFirst().sink { _ in
                    guard !queued, state.stateValue("$trigger") == .number(1) else { return }
                    queued = true
                    if retire { state.setState("$shown", value: .boolean(false)) }
                    XCTAssertTrue(context.canInteract, "The target is still current while its removal is queued: \(label)")
                    binding.wrappedValue = retire ? .number(37) : oversized
                    XCTAssertTrue(receipts.isEmpty, "Enqueuing alone must not acknowledge a write: \(label)")
                }
                defer { subscription.cancel() }

                state.setState("$trigger", value: .number(1))

                XCTAssertTrue(queued, label)
                XCTAssertEqual(receipts, [nil], label)
                XCTAssertEqual(state.stateValue("$count"), .number(10), label)
                XCTAssertNil(state.snapshotState()["amount"], label)
                XCTAssertNil(state.snapshotState()["form"], label)
                XCTAssertEqual(state.isInterrupted, !retire, label)
                if retire {
                    XCTAssertTrue(PropValue.children(try XCTUnwrap(state.root)).isEmpty, label)
                } else {
                    XCTAssertFalse(state.errors.isEmpty, label)
                }
            }
        }
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

    @MainActor func testErrorCallbacksDistinguishRawUnicodeAndStillDeduplicateUnchangedErrors() throws {
        let message = ParamDef(name: "message", required: true)
        let schema = LibrarySchema(components: ["Box": [ParamDef(name: "value", required: true)]],
            callDefs: builtinCallDefs.merging(["Fail": CallDef(kind: .function, params: [message])]) { _, new in new })
        let state = OpenUIState(schema: schema,
            functions: ["Fail": CustomFunction(params: [message], fn: { args in
                guard let value = args["message"], case .string(let text) = value, !text.isEmpty else { return .null }
                throw CallbackDiagnostic(description: text.displayString)
            })])
        defer { state.reset() }
        var reports: [[OpenUIError]] = []
        state.onError = { reports.append($0) }
        state.setSource("$value=\"\u{00E9}\"\nroot=Box(@Fail($value))")
        let first = try XCTUnwrap(state.errors.first)
        XCTAssertEqual(reports.count, 1)
        XCTAssertFalse(state.isInterrupted, "An ordinary root property error remains recoverable")
        XCTAssertFalse(state.nativePresentation.hasRuntimeFailure)

        let decomposed = Value.string("e\u{301}")
        state.setState("$value", value: decomposed)
        let second = try XCTUnwrap(state.errors.first)
        XCTAssertEqual(first.message, second.message, "Swift considers the two spellings canonically equivalent")
        XCTAssertFalse(first.message.utf16.elementsEqual(second.message.utf16))
        XCTAssertEqual(reports.count, 2, "A changed raw diagnostic must reach the host")
        XCTAssertTrue(try XCTUnwrap(reports.last?.first).message.utf16.elementsEqual(second.message.utf16))
        XCTAssertTrue(state.canExecuteActions)
        XCTAssertFalse(state.nativePresentation.hasRuntimeFailure)

        state.setState("$value", value: decomposed)
        XCTAssertEqual(reports.count, 2, "The same full error still has one notification")
        state.setState("$value", value: .string(""))
        XCTAssertEqual(reports.count, 3)
        XCTAssertTrue(try XCTUnwrap(reports.last).isEmpty)
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

private struct CallbackDiagnostic: Error, CustomStringConvertible {
    let description: String
}
