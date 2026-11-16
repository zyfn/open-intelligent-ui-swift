import Foundation
import XCTest
@testable import SwiftLang

final class ActionCancellationTests: XCTestCase {
    @MainActor func testCancelledTriggerRejectsLegacyPlanAndDefaultActions() async {
        let schema = LibrarySchema(components: ["Button": [ParamDef(name: "action", required: true)]], callDefs: builtinCallDefs)
        let state = OpenUIState(schema: schema)
        state.setSource("root=Button(@ToAssistant(\"ready\"))")
        let legacy = Value.object([
            ObjectField(key: "type", value: .string("open_url")),
            ObjectField(key: "url", value: .string("https://example.com")),
        ])
        let plan = Value.actionPlan(ActionPlan(steps: [.openUrl(urlAST: .str("https://example.com"))]))
        var dispatched: [ActionEvent] = []
        state.onAction = { dispatched.append($0) }
        let actions: [Value?] = [legacy, plan, nil, .null]
        for action in actions {
            // This test owns MainActor until the await below, so cancellation
            // precedes entry into every representation of triggerAction.
            let task = Task { await state.triggerAction("Open", action: action) }
            task.cancel()
            let events = await task.value
            XCTAssertTrue(events.isEmpty)
        }
        XCTAssertTrue(dispatched.isEmpty)
        let accepted = await state.triggerAction("Open", action: legacy)
        XCTAssertEqual(accepted.count, 1, "An active legacy action retains its existing behavior")
        XCTAssertEqual(dispatched.count, 1)
        XCTAssertEqual(accepted.first?.type, "open_url")
    }

    /// Cancellation is observed but intentionally does not release the await.
    /// The SDK must finish its own waiter without depending on this provider.
    private final class SuspendedProvider: ToolProvider, @unchecked Sendable {
        private let lock = NSLock()
        private let started: [String: [XCTestExpectation]]
        private var counts: [String: Int] = [:]
        private var waiting: [String: [CheckedContinuation<Value, Never>]] = [:]
        private var cancelled: [String] = []
        init(started: [String: [XCTestExpectation]]) { self.started = started }
        var cancellations: [String] { lock.lock(); defer { lock.unlock() }; return cancelled }
        var calls: [String: Int] { lock.lock(); defer { lock.unlock() }; return counts }
        private func cancel(_ name: String) { lock.lock(); cancelled.append(name); lock.unlock() }
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
            }, onCancel: { self.cancel(name) })
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

    @MainActor func testCancellationEndsOnlyTheCallingActionAndAllowsAnIsolatedRetry() async {
        let queryStarted = expectation(description: "Unrelated Query started")
        let keptStarted = expectation(description: "Unrelated Mutation started")
        let firstStarted = expectation(description: "Action Mutation started")
        let retryStarted = expectation(description: "Same declaration retry started")
        let actionReturned = expectation(description: "Cancelled action returned before provider")
        let keptReturned = expectation(description: "Unrelated Mutation returned")
        let retryReturned = expectation(description: "Retry returned")
        let provider = SuspendedProvider(started: ["load": [queryStarted], "keep": [keptStarted], "save": [firstStarted, retryStarted]])
        let manager = QueryManager(provider: provider), store = createStore()
        defer { provider.releaseAll(); manager.dispose(); store.dispose() }
        let evaluator = Evaluator(context: EvaluationContext(getState: { store.get($0) ?? .null }, resolveRef: { _ in .null }), schema: LibrarySchema())
        manager.evaluateStatements([QueryStatementInfo(statementId: "q", toolAST: .str("load"), argsAST: .obj([]),
            defaultsAST: .str("default"), refreshAST: nil, deps: nil, complete: true)], evaluator: evaluator)
        manager.registerMutations(["save": "save", "keep": "keep"])
        let kept = Task {
            let result = await manager.runMutation(statementId: "keep", tool: "keep", args: .object([]))
            keptReturned.fulfill(); return result
        }
        var dispatched = 0
        let context = ActionRuntimeContext(store: store, evaluate: evaluator.evaluate,
            runQuery: { manager.invalidateQuery(statementId: $0) },
            runMutation: { id in
                let result = await manager.runMutation(statementId: id, tool: "save", args: .object([]))
                return result.status == .success ? .success(result.data ?? .null) : .failure
            }, onEvent: { _ in dispatched += 1 })
        let action = Task {
            let events = await runActionPlan(ActionPlan(steps: [
                .set(target: "$note", valueAST: .str("accepted")),
                .run(statementId: "save", refType: .mutation),
                .set(target: "$note", valueAST: .str("stale")),
                .continueConversation(messageAST: .str("stale"), contextAST: nil),
            ]), context: context)
            actionReturned.fulfill(); return events
        }
        await fulfillment(of: [queryStarted, keptStarted, firstStarted], timeout: 2)
        action.cancel()
        await fulfillment(of: [actionReturned], timeout: 1)
        XCTAssertEqual(provider.cancellations, ["save"])
        XCTAssertEqual(manager.queryState(for: "q")?.status, .loading)
        XCTAssertEqual(manager.mutationState(for: "keep")?.status, .loading)
        XCTAssertEqual(manager.mutationState(for: "save")?.status, .idle)
        XCTAssertEqual(store.get("$note"), .string("accepted"))
        XCTAssertEqual(dispatched, 0)

        let retry = Task {
            let result = await manager.runMutation(statementId: "save", tool: "save", args: .object([]))
            retryReturned.fulfill(); return result
        }
        await fulfillment(of: [retryStarted], timeout: 2)
        provider.releaseFirst("save", value: .string("stale"))
        provider.releaseFirst("save", value: .string("current"))
        provider.releaseFirst("keep", value: .string("kept"))
        let querySettled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            manager.queryState(for: "q")?.data == .string("loaded")
        }, object: nil)
        provider.releaseFirst("load", value: .string("loaded"))
        await fulfillment(of: [keptReturned, retryReturned, querySettled], timeout: 2)
        let events = await action.value, keptResult = await kept.value, retryResult = await retry.value
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(keptResult.status, .success)
        XCTAssertEqual(retryResult.status, .success)
        XCTAssertEqual(retryResult.data, .string("current"))
        XCTAssertEqual(manager.mutationState(for: "save")?.data, .string("current"))
        XCTAssertEqual(store.get("$note"), .string("accepted"))
        XCTAssertEqual(dispatched, 0)
        XCTAssertEqual(provider.calls, ["load": 1, "keep": 1, "save": 2])
        XCTAssertEqual(provider.cancellations, ["save"])
    }

    @MainActor func testCancellingStatePerformPreservesDocumentAndRejectsLateSteps() async throws {
        let started = expectation(description: "Document Mutation started")
        let returned = expectation(description: "Document action cancelled before provider")
        let provider = SuspendedProvider(started: ["save": [started]])
        let schema = LibrarySchema(components: ["Button": [ParamDef(name: "action", required: true)]], callDefs: builtinCallDefs)
        let state = OpenUIState(schema: schema, toolProvider: provider)
        defer { provider.releaseAll(); state.reset() }
        state.setSource("$note=\"keep\"\nsave=Mutation(\"save\",{})\nroot=Button(Action([@Run(save),@Set($note,\"stale\"),@ToAssistant(\"stale\")]))")
        let plan = try XCTUnwrap(PropValue.actionPlan(try XCTUnwrap(state.root), "action"))
        var dispatched = 0
        state.onAction = { _ in dispatched += 1 }
        let action = Task {
            let events = await state.perform(plan)
            returned.fulfill(); return events
        }
        await fulfillment(of: [started], timeout: 2)
        action.cancel()
        await fulfillment(of: [returned], timeout: 1)
        XCTAssertTrue(state.canExecuteActions, "Cancelling one action does not dispose its document")
        XCTAssertFalse(state.isInterrupted)
        XCTAssertEqual(state.stateValue("$note"), .string("keep"))
        XCTAssertEqual(provider.cancellations, ["save"])
        provider.releaseAll()
        let events = await action.value
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(dispatched, 0)
        XCTAssertEqual(state.stateValue("$note"), .string("keep"))
    }
}
