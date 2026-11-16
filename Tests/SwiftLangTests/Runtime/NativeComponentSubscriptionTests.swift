import Combine
import XCTest
@testable import SwiftLang

final class NativeComponentSubscriptionTests: XCTestCase {
    @MainActor private func makeState(streaming: Bool = false) -> OpenUIState {
        let schema = LibrarySchema(components: ["Probe": [ParamDef(name: "text", required: true)]],
                                   callDefs: builtinCallDefs)
        let state = OpenUIState(schema: schema)
        state.setSource("root=Probe(\"stable\")", streaming: streaming)
        return state
    }

    @MainActor private func makeContext(_ subscription: NativeComponentSubscription, state: OpenUIState,
                                   element: EvaluatedElement? = nil, form: OpenUIString? = nil) throws -> OpenUIComponentContext {
        let element = try XCTUnwrap(element ?? state.root)
        let (presentation, reads) = subscription.begin(element: element, state: state)
        return OpenUIComponentContext(element: presentation.element, registry: OpenUIComponentRegistry(), state: state,
            values: OpenUIContextValues(), resources: [:], exactFormName: form,
            nativePresentation: presentation, readScope: reads)
    }

    @MainActor func testFieldChangesNotifyOnlySubscriptionsThatReadThatField() throws {
        let state = makeState()
        defer { state.reset() }
        let left = NativeComponentSubscription(), right = NativeComponentSubscription(), plain = NativeComponentSubscription()
        let leftContext = try makeContext(left, state: state), rightContext = try makeContext(right, state: state)
        _ = try makeContext(plain, state: state)
        XCTAssertEqual(leftContext.fieldValue("left"), .null)
        XCTAssertEqual(rightContext.fieldBinding("right").wrappedValue, .null)
        var leftChanges = 0, rightChanges = 0, plainChanges = 0
        let subscriptions = [
            left.objectWillChange.sink { leftChanges += 1 },
            right.objectWillChange.sink { rightChanges += 1 },
            plain.objectWillChange.sink { plainChanges += 1 }
        ]
        defer { subscriptions.forEach { $0.cancel() } }
        state.setFieldValue(form: nil, name: "unrelated", value: .string("no reader"))
        XCTAssertEqual([leftChanges, rightChanges, plainChanges], [0, 0, 0])
        state.setFieldValue(form: nil, name: "left", value: .string("left changed"))
        XCTAssertEqual([leftChanges, rightChanges, plainChanges], [1, 0, 0])
        state.setFieldValue(form: nil, name: "right", value: .string("right changed"))
        XCTAssertEqual([leftChanges, rightChanges, plainChanges], [1, 1, 0])
        XCTAssertEqual(leftContext.fieldValue("left"), .string("left changed"))
        XCTAssertEqual(rightContext.fieldBinding("right").wrappedValue, .string("right changed"))
    }

    @MainActor func testMissingFieldAndExplicitUndefinedKeepDistinctFallbackBehavior() throws {
        let state = makeState()
        defer { state.reset() }
        let subscription = NativeComponentSubscription()
        let context = try makeContext(subscription, state: state, form: "form")
        XCTAssertEqual(context.fieldValue("value", fallback: .string("first")), .string("first"))
        XCTAssertEqual(context.fieldValue("value", fallback: .string("second")), .string("second"))
        var changes = 0
        let sink = subscription.objectWillChange.sink { changes += 1 }
        defer { sink.cancel() }
        state.setState("form", value: .object([ObjectField(key: "value", value: .undefined)]))
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(context.fieldValue("value", fallback: .string("first")), .undefined)
        XCTAssertEqual(context.fieldValue("value", fallback: .string("second")), .undefined)
    }

    @MainActor func testAFirstDelayedBindingReadUsesTheLatestCommitThenObservesFutureChanges() throws {
        let state = makeState()
        defer { state.reset() }
        let subscription = NativeComponentSubscription(), context = try makeContext(subscription, state: state)
        // A child may not ask for its Binding until after a later commit.
        // Do not assume Binding.init itself delays calling its getter.
        let delayedRead = { context.fieldBinding("late").wrappedValue }
        var changes = 0
        let sink = subscription.objectWillChange.sink { changes += 1 }
        defer { sink.cancel() }
        state.setFieldValue(form: nil, name: "late", value: .string("before the first getter"))
        XCTAssertEqual(changes, 0, "A field that no body or Binding getter has read is not yet a dependency")
        XCTAssertEqual(delayedRead(), .string("before the first getter"))
        state.setFieldValue(form: nil, name: "late", value: .string("after the first getter"))
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(delayedRead(), .string("after the first getter"))
    }

    @MainActor func testRetainedContextAndBindingReadThePreviousCommitDuringPublicWillSet() throws {
        let state = makeState()
        defer { state.reset() }
        state.setFieldValue(form: nil, name: "field", value: .string("before"))
        let subscription = NativeComponentSubscription(), context = try makeContext(subscription, state: state)
        let binding = context.fieldBinding("field")
        XCTAssertEqual(binding.wrappedValue, .string("before"))
        var duringField: [Value] = [], duringBinding: [Value] = []
        let sink = state.$root.dropFirst().sink { _ in
            duringField.append(context.fieldValue("field"))
            duringBinding.append(binding.wrappedValue)
        }
        defer { sink.cancel() }
        state.setFieldValue(form: nil, name: "field", value: .string("after"))
        XCTAssertEqual(duringField, [.string("before")])
        XCTAssertEqual(duringBinding, [.string("before")])
        XCTAssertEqual(context.fieldValue("field"), .string("after"))
        XCTAssertEqual(binding.wrappedValue, .string("after"))
    }

    @MainActor func testScopedBindingsKeepTheirTargetAndReactiveWriteTransform() throws {
        let schema = LibrarySchema(components: ["Input": [ParamDef(name: "value", required: true, isBindable: true)]],
                                   callDefs: builtinCallDefs)
        for (expression, expected) in [("$count", 5.0), ("$count=$value+2", 7.0)] {
            let state = OpenUIState(schema: schema)
            defer { state.reset() }
            state.setSource("$count=1\nroot=Input(\(expression))")
            let subscription = NativeComponentSubscription(), context = try makeContext(subscription, state: state)
            let binding = try XCTUnwrap(context.binding("value"))
            XCTAssertEqual(binding.wrappedValue, .number(1))
            binding.wrappedValue = .number(5)
            XCTAssertEqual(state.stateValue("$count"), .number(expected))
            XCTAssertEqual(binding.wrappedValue, .number(expected), "A retained Binding reads the latest completed commit")
        }
    }

    @MainActor func testAReboundSubscriptionIgnoresReadsFromOldContextsAndOldDocuments() throws {
        let first = makeState(), second = makeState()
        defer { first.reset(); second.reset() }
        let subscription = NativeComponentSubscription()
        let oldContext = try makeContext(subscription, state: first)
        _ = oldContext.fieldValue("old")
        let newContext = try makeContext(subscription, state: second)
        _ = newContext.fieldValue("new")
        // A retained Binding or view from the retired scope may still read.
        // Its dependency must not become a dependency of the new document.
        _ = oldContext.fieldBinding("old").wrappedValue
        var changes = 0
        let sink = subscription.objectWillChange.sink { changes += 1 }
        defer { sink.cancel() }
        first.setFieldValue(form: nil, name: "old", value: .string("first document"))
        second.setFieldValue(form: nil, name: "old", value: .string("unobserved second field"))
        XCTAssertEqual(changes, 0)
        second.setFieldValue(form: nil, name: "new", value: .string("observed second field"))
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(newContext.fieldValue("new"), .string("observed second field"))
    }

    @MainActor func testSourceReplacementRetiresReadScopeBeforeTheNextHostRender() throws {
        let state = makeState()
        defer { state.reset() }
        let subscription = NativeComponentSubscription(), oldContext = try makeContext(subscription, state: state)
        _ = oldContext.fieldValue("previous field")
        var changes = 0
        let sink = subscription.objectWillChange.sink { changes += 1 }
        defer { sink.cancel() }
        let sourceRevision = state.sourceRevision
        state.setSource("$generation=1\nroot=Probe(\"stable\")")
        XCTAssertNotEqual(state.sourceRevision, sourceRevision)
        XCTAssertEqual(changes, 1)
        // No new begin/render occurs yet. Both an existing dependency and a
        // first delayed read belong to the retired source, despite the same
        // OpenUIState instance and identical displayed component properties.
        let oldBinding = oldContext.fieldBinding("late field")
        XCTAssertEqual(oldBinding.wrappedValue, .null)
        state.setFieldValue(form: nil, name: "previous field", value: .string("unobserved"))
        state.setFieldValue(form: nil, name: "late field", value: .string("latest commit"))
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(oldBinding.wrappedValue, .string("latest commit"), "Only dependency registration is retired")
        let currentContext = try makeContext(subscription, state: state)
        _ = currentContext.fieldValue("current field")
        state.setFieldValue(form: nil, name: "current field", value: .string("observed"))
        XCTAssertEqual(changes, 2)
    }

    @MainActor func testDelimiterReadinessAndRemovalReachADirectMountedOldSnapshot() throws {
        let state = makeState()
        defer { state.reset() }
        state.setSource("root=Probe(\"stable", streaming: true)
        let original = try XCTUnwrap(state.root), subscription = NativeComponentSubscription()
        let before = try makeContext(subscription, state: state, element: original)
        XCTAssertFalse(before.canInteract)
        var changes = 0
        let sink = subscription.objectWillChange.sink { changes += 1 }
        defer { sink.cancel() }
        state.push("\")")
        XCTAssertEqual(changes, 1)
        XCTAssertTrue(try makeContext(subscription, state: state, element: original).canInteract)
        let revision = state.sourceRevision
        state.push("\nroot=Probe(\"replacement\")")
        XCTAssertEqual(state.sourceRevision, revision)
        XCTAssertEqual(changes, 2)
        XCTAssertFalse(try makeContext(subscription, state: state, element: original).canInteract)
    }

    @MainActor func testCompletionReachesTheSameSubscriptionWithoutChangingItsOwner() throws {
        let state = makeState(streaming: true)
        defer { state.reset() }
        let subscription = NativeComponentSubscription(), original = try XCTUnwrap(state.root)
        XCTAssertTrue(try makeContext(subscription, state: state, element: original).isStreaming)
        var changes = 0
        let sink = subscription.objectWillChange.sink { changes += 1 }
        defer { sink.cancel() }
        state.complete()
        XCTAssertEqual(changes, 1)
        XCTAssertFalse(try makeContext(subscription, state: state, element: original).isStreaming)
    }

    @MainActor func testInterruptPublishesPendingQueryPresentationWithoutDispatchingAProvider() throws {
        let state = makeState()
        defer { state.reset() }
        state.setSource("q=Query(\"load\",{},\"fallback\")\nroot=Probe(q)", streaming: true)
        let subscription = NativeComponentSubscription(), original = try XCTUnwrap(state.root)
        let before = try makeContext(subscription, state: state, element: original)
        XCTAssertTrue(before.isStreaming)
        XCTAssertTrue(before.isQueryLoading)
        XCTAssertTrue(before.hasPendingData)
        XCTAssertFalse(before.hasInterruptedData)
        var changes = 0
        let sink = subscription.objectWillChange.sink { changes += 1 }
        defer { sink.cancel() }
        state.interrupt()
        let after = try makeContext(subscription, state: state, element: original)
        XCTAssertEqual(changes, 1)
        XCTAssertFalse(after.isStreaming)
        XCTAssertFalse(after.isQueryLoading)
        XCTAssertFalse(after.hasPendingData)
        XCTAssertTrue(after.hasInterruptedData)
    }

    @MainActor func testWeakRegistrationRetainsNeitherAMountedSubscriptionNorItsDocument() throws {
        var state: OpenUIState? = makeState()
        weak var weakState = state
        var subscription: NativeComponentSubscription? = NativeComponentSubscription()
        weak var weakSubscription = subscription
        _ = try makeContext(XCTUnwrap(subscription), state: XCTUnwrap(state))
        subscription = nil
        XCTAssertNil(weakSubscription)
        state = nil
        XCTAssertNil(weakState)
    }
}
