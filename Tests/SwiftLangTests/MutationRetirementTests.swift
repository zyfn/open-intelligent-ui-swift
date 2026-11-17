import Foundation
import XCTest
@testable import SwiftLang

final class MutationRetirementTests: XCTestCase {
    /// Records cancellation but deliberately remains suspended until the test
    /// releases it. Retiring a declaration must not wait for this provider.
    private final class SuspendedProvider: ToolProvider, @unchecked Sendable {
        private let lock = NSLock()
        private let started: [String: [XCTestExpectation]]
        private var counts: [String: Int] = [:]
        private var waiting: [String: [CheckedContinuation<Value, Never>]] = [:]
        private var cancelled: [String] = []

        init(started: [String: [XCTestExpectation]]) { self.started = started }
        var cancellations: [String] { lock.lock(); defer { lock.unlock() }; return cancelled }
        var calls: [String: Int] { lock.lock(); defer { lock.unlock() }; return counts }
        private func recordCancellation(_ name: String) { lock.lock(); cancelled.append(name); lock.unlock() }
        private func suspend(_ name: String, _ continuation: CheckedContinuation<Value, Never>) {
            lock.lock()
            let index = counts[name, default: 0]
            counts[name] = index + 1
            waiting[name, default: []].append(continuation)
            let signal = started[name].flatMap { index < $0.count ? $0[index] : nil }
            lock.unlock()
            signal?.fulfill()
        }
        func callTool(name: OpenUIString, arguments: OpenUIObject) async throws -> Value {
            let name = name.displayString
            return await withTaskCancellationHandler(operation: {
                await withCheckedContinuation { suspend(name, $0) }
            }, onCancel: { self.recordCancellation(name) })
        }
        func releaseFirst(_ name: String, value: Value) {
            lock.lock()
            let continuation = waiting[name]?.isEmpty == false ? waiting[name]?.removeFirst() : nil
            lock.unlock()
            continuation?.resume(returning: value)
        }
        func releaseAll() {
            lock.lock(); let continuations = waiting.values.flatMap { $0 }; waiting.removeAll(); lock.unlock()
            continuations.forEach { $0.resume(returning: .string("late")) }
        }
    }

    private func startQuery(_ manager: QueryManager) {
        let evaluator = Evaluator(context: EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null }), schema: LibrarySchema())
        manager.evaluateStatements([QueryStatementInfo(statementId: "query", toolAST: .str("load"),
            argsAST: .obj([]), defaultsAST: .str("default"), refreshAST: nil, deps: nil, complete: true)], evaluator: evaluator)
    }

    @MainActor func testReplacingOneMutationReleasesItsAwaitAndPreservesOtherRequests() async {
        let queryStarted = expectation(description: "Query started")
        let oldStarted = expectation(description: "Old mutation started")
        let keptStarted = expectation(description: "Unchanged mutation started")
        let oldReturned = expectation(description: "Retired await returned before provider")
        let keptReturned = expectation(description: "Unchanged await returned")
        let provider = SuspendedProvider(started: ["load": [queryStarted], "old": [oldStarted], "keep": [keptStarted]])
        let manager = QueryManager(provider: provider)
        defer { provider.releaseAll(); manager.dispose() }
        startQuery(manager)
        manager.registerMutations(["save": "old", "keep": "keep"])
        let old = Task {
            let result = await manager.runMutation(statementId: "save", tool: "old", args: .object([]))
            oldReturned.fulfill(); return result
        }
        let kept = Task {
            let result = await manager.runMutation(statementId: "keep", tool: "keep", args: .object([]))
            keptReturned.fulfill(); return result
        }
        await fulfillment(of: [queryStarted, oldStarted, keptStarted], timeout: 2)
        manager.registerMutations(["save": "replacement", "keep": "keep"])
        await fulfillment(of: [oldReturned], timeout: 1)
        XCTAssertEqual(provider.cancellations, ["old"])
        XCTAssertEqual(manager.queryState(for: "query")?.status, .loading)
        XCTAssertEqual(manager.mutationState(for: "keep")?.status, .loading)
        XCTAssertEqual(manager.mutationState(for: "save")?.status, .idle)

        provider.releaseFirst("old", value: .string("stale"))
        provider.releaseFirst("keep", value: .string("kept"))
        let querySettled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            manager.queryState(for: "query")?.data == .string("loaded")
        }, object: nil)
        provider.releaseFirst("load", value: .string("loaded"))
        await fulfillment(of: [keptReturned, querySettled], timeout: 2)
        let oldResult = await old.value, keptResult = await kept.value
        XCTAssertEqual(oldResult.status, .error)
        XCTAssertEqual(keptResult.status, .success)
        XCTAssertEqual(manager.mutationState(for: "save")?.status, .idle)
        XCTAssertEqual(manager.queryState(for: "query")?.data, .string("loaded"))
        XCTAssertEqual(provider.cancellations, ["old"])
        XCTAssertEqual(provider.calls, ["load": 1, "old": 1, "keep": 1])
    }

    @MainActor func testInvalidationReleasesSameToolAwaitAndIsolatesNextGeneration() async {
        let firstStarted = expectation(description: "First generation started")
        let secondStarted = expectation(description: "Second generation started")
        let firstReturned = expectation(description: "First generation retired")
        let secondReturned = expectation(description: "Second generation completed")
        let provider = SuspendedProvider(started: ["save": [firstStarted, secondStarted]])
        let manager = QueryManager(provider: provider)
        defer { provider.releaseAll(); manager.dispose() }
        manager.registerMutations(["save": "save"])
        let first = Task {
            let result = await manager.runMutation(statementId: "save", tool: "save", args: .object([]))
            firstReturned.fulfill(); return result
        }
        await fulfillment(of: [firstStarted], timeout: 2)
        manager.invalidateMutations()
        await fulfillment(of: [firstReturned], timeout: 1)
        XCTAssertEqual(manager.mutationState(for: "save")?.status, .idle)
        let second = Task {
            let result = await manager.runMutation(statementId: "save", tool: "save", args: .object([]))
            secondReturned.fulfill(); return result
        }
        await fulfillment(of: [secondStarted], timeout: 2)
        provider.releaseFirst("save", value: .string("stale"))
        XCTAssertEqual(manager.mutationState(for: "save")?.status, .loading)
        provider.releaseFirst("save", value: .string("current"))
        await fulfillment(of: [secondReturned], timeout: 2)
        let firstResult = await first.value, secondResult = await second.value
        XCTAssertEqual(firstResult.status, .error)
        XCTAssertEqual(secondResult.data, .string("current"))
        XCTAssertEqual(manager.mutationState(for: "save")?.data, .string("current"))
        XCTAssertEqual(provider.cancellations, ["save"])
    }

    @MainActor func testPatchEndsOldActionWithoutWaitingForProviderAndPreservesEdits() async throws {
        let started = expectation(description: "Action tool started")
        let returned = expectation(description: "Patched action returned before provider")
        let provider = SuspendedProvider(started: ["save": [started]])
        let schema = LibrarySchema(components: ["Button": [ParamDef(name: "action", required: true)]],
            callDefs: builtinCallDefs, rootComponent: "Button")
        let state = OpenUIState(schema: schema, toolProvider: provider)
        defer { provider.releaseAll(); state.reset() }
        state.setSource("$note=\"default\"\nsave=Mutation(\"save\",{n:1})\nroot=Button(Action([@Run(save),@Set($note,\"stale\"),@ToAssistant(\"stale\")]))")
        state.setState("$note", value: .string("edited"))
        let plan = try XCTUnwrap(PropValue.actionPlan(try XCTUnwrap(state.root), "action"))
        let action = Task {
            let events = await state.perform(plan)
            returned.fulfill(); return events
        }
        await fulfillment(of: [started], timeout: 2)
        var patchedMutationIDs: [String]?
        state.onParseResult = { patchedMutationIDs = $0.mutationStatements.map(\.statementId) }
        state.applyPatch("save=Mutation(\"save\",{n:2})\nroot=Button(@ToAssistant(\"current\"))")
        state.onParseResult = nil
        await fulfillment(of: [returned], timeout: 1)
        XCTAssertEqual(provider.cancellations, ["save"])
        provider.releaseFirst("save", value: .string("stale"))
        let events = await action.value
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(state.stateValue("$note"), .string("edited"))
        // The official merge removes declarations unreachable from the new
        // root. This patch no longer references save, so it has no idle slot.
        XCTAssertEqual(patchedMutationIDs, [])
        XCTAssertNil(state.mutationStates["save"])
    }

    @MainActor func testPatchKeepsReachableMutationIdleAfterRetiringItsOldAction() async throws {
        let started = expectation(description: "Action tool started")
        let returned = expectation(description: "Patched action returned before provider")
        let provider = SuspendedProvider(started: ["save": [started]])
        let schema = LibrarySchema(components: ["Button": [ParamDef(name: "action", required: true)]],
            callDefs: builtinCallDefs, rootComponent: "Button")
        let state = OpenUIState(schema: schema, toolProvider: provider)
        defer { provider.releaseAll(); state.reset() }
        state.setSource("$note=\"default\"\nsave=Mutation(\"save\",{n:1})\nroot=Button(Action([@Run(save),@Set($note,\"stale\"),@ToAssistant(\"stale\")]))")
        state.setState("$note", value: .string("edited"))
        let plan = try XCTUnwrap(PropValue.actionPlan(try XCTUnwrap(state.root), "action"))
        let action = Task {
            let events = await state.perform(plan)
            returned.fulfill(); return events
        }
        await fulfillment(of: [started], timeout: 2)
        var patchedMutationIDs: [String]?
        state.onParseResult = { patchedMutationIDs = $0.mutationStatements.map(\.statementId) }
        state.applyPatch("save=Mutation(\"save\",{n:2})\nroot=Button(@Run(save))")
        state.onParseResult = nil
        await fulfillment(of: [returned], timeout: 1)
        XCTAssertEqual(provider.cancellations, ["save"])
        XCTAssertEqual(patchedMutationIDs, ["save"])
        XCTAssertEqual(state.mutationStates["save"]?.status, .idle)
        provider.releaseFirst("save", value: .string("stale"))
        let events = await action.value
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(state.stateValue("$note"), .string("edited"))
        XCTAssertEqual(state.mutationStates["save"]?.status, .idle)
        XCTAssertEqual(provider.calls, ["save": 1])
    }

    @MainActor func testDisposeReleasesAllAwaitersWithoutProviderCooperation() async {
        let queryStarted = expectation(description: "Query started")
        let mutationStarted = expectation(description: "Mutation started")
        let returned = expectation(description: "Disposed await returned before provider")
        let provider = SuspendedProvider(started: ["load": [queryStarted], "save": [mutationStarted]])
        let manager = QueryManager(provider: provider)
        defer { provider.releaseAll(); manager.dispose() }
        startQuery(manager)
        manager.registerMutations(["save": "save"])
        let mutation = Task {
            let result = await manager.runMutation(statementId: "save", tool: "save", args: .object([]))
            returned.fulfill(); return result
        }
        await fulfillment(of: [queryStarted, mutationStarted], timeout: 2)
        manager.dispose()
        await fulfillment(of: [returned], timeout: 1)
        XCTAssertEqual(provider.cancellations.sorted(), ["load", "save"])
        provider.releaseAll()
        let result = await mutation.value
        XCTAssertEqual(result.status, .error)
        XCTAssertNil(manager.queryState(for: "query"))
        XCTAssertNil(manager.mutationState(for: "save"))
    }

    @MainActor func testDeferredQueryDispatchStartsAfterTheHostAccepts() async {
        let started = expectation(description: "Accepted query entered provider")
        let provider = SuspendedProvider(started: ["load": [started]])
        let manager = QueryManager(provider: provider)
        defer { provider.releaseAll(); manager.dispose() }
        let accepted = manager.withDeferredToolDispatch {
            startQuery(manager)
            XCTAssertEqual(manager.queryState(for: "query")?.status, .loading)
            XCTAssertTrue(provider.calls.isEmpty)
            XCTAssertTrue(manager.withDeferredToolDispatch { true })
            XCTAssertTrue(provider.calls.isEmpty, "Nested acceptance cannot dispatch before the outer scope")
            return true
        }
        XCTAssertTrue(accepted)
        await fulfillment(of: [started], timeout: 2)
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            manager.queryState(for: "query")?.data == .string("accepted")
        }, object: nil)
        provider.releaseFirst("load", value: .string("accepted"))
        await fulfillment(of: [settled], timeout: 2)
        XCTAssertEqual(manager.queryState(for: "query")?.data, .string("accepted"))
        XCTAssertEqual(provider.calls, ["load": 1])
    }

    @MainActor func testRejectedDispatchNeverEntersProviderAndEndsExistingAwait() async {
        let mutationStarted = expectation(description: "Existing mutation started")
        let queryStarted = expectation(description: "Rejected query must not enter provider")
        queryStarted.isInverted = true
        let returned = expectation(description: "Rejected document ended existing await")
        let provider = SuspendedProvider(started: ["save": [mutationStarted], "load": [queryStarted]])
        let manager = QueryManager(provider: provider)
        defer { provider.releaseAll(); manager.dispose() }
        manager.registerMutations(["save": "save"])
        let mutation = Task {
            let result = await manager.runMutation(statementId: "save", tool: "save", args: .object([]))
            returned.fulfill(); return result
        }
        await fulfillment(of: [mutationStarted], timeout: 2)
        let accepted = manager.withDeferredToolDispatch {
            startQuery(manager)
            XCTAssertEqual(manager.queryState(for: "query")?.status, .loading)
            return false
        }
        XCTAssertFalse(accepted)
        await fulfillment(of: [returned], timeout: 1)
        await fulfillment(of: [queryStarted], timeout: 0.05)
        XCTAssertEqual(provider.calls, ["save": 1])
        XCTAssertEqual(provider.cancellations, ["save"])
        XCTAssertNil(manager.queryState(for: "query"))
        provider.releaseAll()
        let result = await mutation.value
        XCTAssertEqual(result.status, .error)
    }
}
