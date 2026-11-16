import Combine
import XCTest
@testable import SwiftLang

final class NativePresentationCommitTests: XCTestCase {
    private var schema: LibrarySchema {
        LibrarySchema(components: ["Box": [ParamDef(name: "value", required: true)]], callDefs: builtinCallDefs)
    }

    @MainActor private func value(_ commit: NativePresentationCommit) -> Value? {
        commit.root.flatMap { PropValue.value($0, "value") }
    }

    @MainActor func testPublicCallbacksKeepTheirImmediateReadsWhileNativeReadsStayOnTheCompletedCommit() throws {
        let state = OpenUIState(schema: schema)
        state.setSource("$value=1\nroot=Box($value)")
        let before = state.nativePresentation
        let oldRoot = try XCTUnwrap(before.root)
        var rootCallbacks = 0, stateCallbacks = 0
        let roots = state.$root.dropFirst().sink { incoming in
            guard incoming.flatMap({ PropValue.value($0, "value") }) == .number(2) else { return }
            rootCallbacks += 1
            XCTAssertEqual(state.stateValue("$value"), .number(2), "The public Store read remains immediate")
            XCTAssertEqual(state.root.flatMap { PropValue.value($0, "value") }, .number(1),
                           "Published retains its existing willSet semantics")
            XCTAssertTrue(state.nativePresentation === before)
            XCTAssertEqual(state.nativePresentedStateValue("$value"), .number(1))
            XCTAssertTrue(state.nativeLiveElement(matching: oldRoot) === oldRoot,
                          "A reentrant view read must use the committed tree, not the candidate live index")
            XCTAssertTrue(state.nativeIsElementReady(oldRoot))
        }
        state.onStateUpdate = { snapshot in
            stateCallbacks += 1
            XCTAssertEqual(snapshot["$value"], .number(2))
            XCTAssertEqual(state.root.flatMap { PropValue.value($0, "value") }, .number(2))
            XCTAssertTrue(state.nativePresentation === before,
                          "The internal UI commit follows the existing synchronous public callbacks")
        }
        var committed: [NativePresentationCommit] = []
        let presentations = state.presentationStore.$snapshot.dropFirst().sink { committed.append($0) }
        defer { state.onStateUpdate = nil; roots.cancel(); presentations.cancel() }

        state.setState("$value", value: .number(2))

        XCTAssertEqual(rootCallbacks, 1)
        XCTAssertEqual(stateCallbacks, 1)
        XCTAssertEqual(committed.count, 1)
        let after = state.nativePresentation
        XCTAssertTrue(after === committed.last)
        XCTAssertTrue(after.root === state.root)
        XCTAssertEqual(value(after), .number(2))
        XCTAssertEqual(after.storeValues["$value"], .number(2))
        XCTAssertTrue(after.canExecuteActions)
        XCTAssertEqual(value(before), .number(1), "A retained read model never changes underneath its reader")
        XCTAssertEqual(before.storeValues["$value"], .number(1))
    }

    @MainActor func testReentrantPublicSourceReplacementDoesNotCommitTheSupersededDocumentToNativeUI() {
        let state = OpenUIState(schema: schema)
        state.setSource("root=Box(\"initial\")")
        let initial = state.nativePresentation
        var replaced = false
        let roots = state.$root.dropFirst().sink { incoming in
            guard !replaced, incoming.flatMap({ PropValue.value($0, "value") }) == .string("obsolete") else { return }
            replaced = true
            state.setSource("root=Box(\"replacement\")")
            XCTAssertTrue(state.nativePresentation === initial)
        }
        var values: [Value] = []
        let presentations = state.presentationStore.$snapshot.dropFirst().sink {
            if let value = self.value($0) { values.append(value) }
        }
        defer { roots.cancel(); presentations.cancel() }

        state.setSource("root=Box(\"obsolete\")")

        XCTAssertTrue(replaced)
        XCTAssertEqual(values, [.string("replacement")])
        XCTAssertEqual(value(state.nativePresentation), .string("replacement"))
        XCTAssertEqual(state.nativePresentation.sourceRevision, state.sourceRevision)
        XCTAssertEqual(state.nativePresentation.presentationRevision, state.presentationRevision)
    }

    @MainActor func testRetiredContextRejectsInteractionEvenWhileItsReadModelIsTheLastCommit() throws {
        let state = OpenUIState(schema: schema)
        state.setSource("root=Box(\"initial\")")
        let initial = state.nativePresentation, oldRoot = try XCTUnwrap(initial.root)
        let subscription = NativeComponentSubscription()
        let (presentation, reads) = subscription.begin(element: oldRoot, state: state)
        let context = OpenUIComponentContext(element: oldRoot, registry: [:], state: state,
            values: OpenUIContextValues(), resources: [:], nativePresentation: presentation, readScope: reads)
        XCTAssertTrue(context.canInteract)
        var inspected = false
        let roots = state.$root.dropFirst().sink { incoming in
            guard incoming.flatMap({ PropValue.value($0, "value") }) == .string("replacement") else { return }
            inspected = true
            XCTAssertTrue(state.nativePresentation === initial)
            XCTAssertTrue(state.nativeIsElementReady(oldRoot), "Display reads still have the last complete projection")
            XCTAssertFalse(context.canInteract,
                           "Event-time safety must already reject a retired document, including inline-link gating")
        }
        defer { roots.cancel() }

        state.setSource("root=Box(\"replacement\")")

        XCTAssertTrue(inspected)
        XCTAssertFalse(context.canInteract)
        XCTAssertEqual(value(state.nativePresentation), .string("replacement"))
        XCTAssertTrue(state.nativeIsElementReady(try XCTUnwrap(state.nativePresentation.root)))
    }

    @MainActor func testNativeSnapshotWillSetReentryCannotOverwriteANewerStoreOrRoot() {
        let state = OpenUIState(schema: schema)
        state.setSource("$value=1\nroot=Box($value)")
        let initial = state.nativePresentation
        var changed = false, committed: [Value] = []
        let presentations = state.presentationStore.$snapshot.dropFirst().sink { incoming in
            if let value = self.value(incoming) { committed.append(value) }
            guard !changed, self.value(incoming) == .number(2) else { return }
            changed = true
            XCTAssertEqual(incoming.storeValues["$value"], .number(2))
            XCTAssertTrue(state.nativePresentation === initial)
            state.setState("$value", value: .number(3))
            XCTAssertEqual(state.stateValue("$value"), .number(2),
                           "Reentrant work waits for the native Published setter to finish")
        }
        defer { presentations.cancel() }

        state.setState("$value", value: .number(2))

        XCTAssertTrue(changed)
        XCTAssertEqual(committed, [.number(2), .number(3)])
        XCTAssertEqual(state.stateValue("$value"), .number(3))
        XCTAssertEqual(value(state.nativePresentation), .number(3))
        XCTAssertEqual(state.nativePresentation.storeValues["$value"], .number(3))
    }

    @MainActor func testComponentNotificationReentryFinishesTheReplacementBeforeReturning() throws {
        let state = OpenUIState(schema: schema)
        state.setSource("$value=1\nroot=Box($value)")
        let node = NativeComponentSubscription()
        _ = node.begin(element: try XCTUnwrap(state.root), state: state)
        var changed = false
        var notifications = 0
        let updates = node.objectWillChange.sink {
            notifications += 1
            guard !changed else { return }
            changed = true
            XCTAssertEqual(self.value(state.nativePresentation), .number(2))
            state.setSource("root=Box(\"replacement\")")
        }
        defer { updates.cancel() }

        state.setState("$value", value: .number(2))

        XCTAssertTrue(changed)
        XCTAssertEqual(notifications, 2, "The queued replacement must reach the same mounted node before returning")
        XCTAssertEqual(value(state.nativePresentation), .string("replacement"))
        XCTAssertTrue(state.nativePresentation.root === state.root)
        XCTAssertEqual(state.nativePresentation.sourceRevision, state.sourceRevision)
    }

    @MainActor func testInterruptAndResetPublishCompleteLifecycleSnapshots() {
        let state = OpenUIState(schema: schema)
        state.push("$value=7\nroot=Box($value)")
        var commits: [NativePresentationCommit] = []
        let presentations = state.presentationStore.$snapshot.dropFirst().sink { commits.append($0) }
        defer { presentations.cancel() }

        state.interrupt()

        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(value(state.nativePresentation), .number(7))
        XCTAssertTrue(state.nativePresentation.isComplete)
        XCTAssertTrue(state.nativePresentation.isInterrupted)
        XCTAssertFalse(state.nativePresentation.canExecuteActions)
        XCTAssertEqual(state.nativePresentation.storeValues["$value"], .number(7))
        let interrupted = state.nativePresentation
        state.complete()
        XCTAssertTrue(state.nativePresentation === interrupted)

        state.reset()

        XCTAssertEqual(commits.count, 2)
        XCTAssertNil(state.nativePresentation.root)
        XCTAssertNil(state.nativePresentation.presentationRoot)
        XCTAssertTrue(state.nativePresentation.storeValues.isEmpty)
        XCTAssertTrue(state.nativePresentation.queryStates.isEmpty)
        XCTAssertTrue(state.nativePresentation.mutationStates.isEmpty)
        XCTAssertTrue(state.nativePresentation.errors.isEmpty)
        XCTAssertFalse(state.nativePresentation.isComplete)
        XCTAssertFalse(state.nativePresentation.isInterrupted)
        XCTAssertEqual(value(interrupted), .number(7))
    }

    @MainActor func testRejectedWriteCommitsFailureWithTheLastGoodRootAndStore() throws {
        let state = OpenUIState(schema: schema)
        state.setSource("$value=7\nroot=Box($value)")
        let root = try XCTUnwrap(state.nativePresentation.root)
        var tooDeep = Value.number(9)
        for _ in 0..<300 { tooDeep = .array([tooDeep]) }

        state.setState("$value", value: tooDeep)

        let failure = state.nativePresentation
        XCTAssertTrue(failure.root === root)
        XCTAssertEqual(failure.storeValues["$value"], .number(7))
        XCTAssertTrue(failure.isComplete)
        XCTAssertTrue(failure.isInterrupted)
        XCTAssertTrue(failure.hasRuntimeFailure)
        XCTAssertFalse(failure.canExecuteActions)
        XCTAssertFalse(failure.errors.isEmpty)
        XCTAssertFalse(state.nativeIsElementReady(root))
    }

    @MainActor func testSameSourceReplayAndEmptyPushDoNotCreateNativeCommits() {
        let state = OpenUIState(schema: schema)
        let source = "$value=1\nroot=Box($value)"
        state.setSource(source, streaming: true)
        let initial = state.nativePresentation
        var notifications = 0
        let presentations = state.presentationStore.$snapshot.dropFirst().sink { _ in notifications += 1 }
        defer { presentations.cancel() }

        state.setSource(source, streaming: true)
        state.push("")

        XCTAssertEqual(notifications, 0)
        XCTAssertTrue(state.nativePresentation === initial)
        state.complete()
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(state.nativePresentation.storeRevision, initial.storeRevision,
                       "Completing an unchanged plain-data Store must reuse its read model")
    }
}
