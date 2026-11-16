import Foundation
import XCTest
@testable import SwiftLang

final class QueryDispatchBoundaryTests: XCTestCase {
    private func schema() -> LibrarySchema {
        LibrarySchema(components: [
            "Box": [ParamDef(name: "value", required: true)],
            "Button": [ParamDef(name: "action", required: true)],
        ], callDefs: builtinCallDefs)
    }
    private var program: String {
        """
        rows=Query("rows",{},[])
        next=Query("reader",{count:@Count(rows)},null)
        root=Box(@Each(rows,a,@Each(rows,b,@Each(rows,c,@Each(rows,d,@Each(rows,e,1))))))
        """
    }

    @MainActor func testAsyncResultMustPassTheRootBudgetBeforeAReaderEntersItsProvider() async throws {
        let started = expectation(description: "Upstream provider started")
        let reader = expectation(description: "Rejected root entered downstream provider")
        reader.isInverted = true
        let readerEntered = DispatchSemaphore(value: 0)
        let stopped = expectation(description: "Root expansion stopped this document")
        let provider = ReaderProvider(onRows: { started.fulfill() }, onReader: { reader.fulfill(); readerEntered.signal() })
        let state = OpenUIState(schema: schema(), toolProvider: provider)
        var reported = false
        state.onError = { [weak state] errors in
            if !reported, !errors.isEmpty, state?.isInterrupted == true { reported = true; stopped.fulfill() }
        }
        defer { state.onError = nil; state.reset(); provider.finishRows(.null) }
        state.setSource(program)
        await fulfillment(of: [started], timeout: 2)
        provider.finishRows(.array((0..<30).map { .number(Double($0)) }))
        // Keep MainActor occupied briefly while native transport settles the
        // JS promise. A reader must wait for its root preflight, even when the
        // actor cannot immediately process the queued query notification.
        XCTAssertFalse(providerEnteredWhileMainActorIsBusy(readerEntered))
        await fulfillment(of: [stopped], timeout: 2)
        await fulfillment(of: [reader], timeout: 0.1)
        let calls = await provider.calls
        XCTAssertEqual(calls, ["rows"])
        XCTAssertTrue(state.isInterrupted)
        XCTAssertFalse(state.canExecuteActions)
        XCTAssertEqual(PropValue.value(try XCTUnwrap(state.root), "value"), .array([]),
            "Keep the bounded default presentation instead of the rejected expansion")
    }

    @MainActor func testOrdinaryAsyncReaderStillRunsOnceAndPublishesItsResult() async throws {
        let started = expectation(description: "Upstream provider started")
        let reader = expectation(description: "Accepted downstream provider started")
        let provider = ReaderProvider(onRows: { started.fulfill() }, onReader: { reader.fulfill() })
        let state = OpenUIState(schema: schema(), toolProvider: provider)
        defer { state.reset(); provider.finishRows(.null) }
        state.setSource(program)
        await fulfillment(of: [started], timeout: 2)
        provider.finishRows(.array([.number(1), .number(2)]))
        await fulfillment(of: [reader], timeout: 2)
        let calls = await provider.calls
        XCTAssertEqual(calls, ["rows", "reader"])
        func leaves(_ value: Value) -> Int {
            if case .array(let values) = value { return values.reduce(0) { $0 + leaves($1) } }
            return 1
        }
        XCTAssertEqual(leaves(try XCTUnwrap(PropValue.value(try XCTUnwrap(state.root), "value"))), 32)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertTrue(state.canExecuteActions)
    }

    @MainActor func testParseCallbackReplacementFinishesBeforeInitialProviderEntry() async throws {
        let called = expectation(description: "Obsolete initial query entered provider")
        called.isInverted = true
        let entered = DispatchSemaphore(value: 0)
        let provider = PendingDispatchProvider { _ in called.fulfill(); entered.signal() }
        let state = OpenUIState(schema: schema(), toolProvider: provider)
        var replaced = false
        state.onParseResult = { _ in
            guard !replaced else { return }
            replaced = true
            XCTAssertFalse(self.providerEnteredWhileMainActorIsBusy(entered),
                "The initial batch must wait until this synchronous publication finishes")
            state.setSource("root=Box(\"replacement\")")
        }
        defer { state.onParseResult = nil; state.reset() }
        state.setSource("q=Query(\"load\",{version:1},null)\nroot=Box(q)")
        XCTAssertTrue(replaced)
        XCTAssertEqual(PropValue.value(try XCTUnwrap(state.root), "value"), .string("replacement"))
        await fulfillment(of: [called], timeout: 0.1)
        let calls = await provider.calls
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor func testOversizedMutationResultSettlesAndCannotContinueItsActionPlan() async throws {
        let provider = FixedProvider(result: deepValue())
        let state = OpenUIState(schema: schema(), toolProvider: provider)
        state.setSource("save=Mutation(\"save\",{})\nroot=Button(Action([@Run(save),@ToAssistant(\"must not emit\")]))")
        let previous = try XCTUnwrap(state.root)
        let plan = try XCTUnwrap(PropValue.actionPlan(previous, "action"))
        var dispatched: [ActionEvent] = []
        state.onAction = { dispatched.append($0) }
        let events = await state.perform(plan)
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(dispatched.isEmpty)
        XCTAssertTrue(state.isInterrupted)
        XCTAssertFalse(state.canExecuteActions)
        XCTAssertNotNil(state.root)
        XCTAssertFalse(state.errors.isEmpty)
        let calls = await provider.calls
        XCTAssertEqual(calls, 1)
    }

    func testStandaloneMutationRejectsOversizedArgumentsBeforeProviderEntry() async {
        let provider = FixedProvider(result: .null)
        let manager = QueryManager(provider: provider)
        let outcome = await manager.runMutation(statementId: "save", tool: "save", args: deepValue())
        XCTAssertEqual(outcome.status, .error)
        XCTAssertTrue(manager.nativeLimitExceeded)
        XCTAssertTrue(manager.isDisposed)
        let calls = await provider.calls
        XCTAssertEqual(calls, 0)
    }

    @MainActor func testPublicQueryRejectsOversizedArgumentsAndPreservesTheLastPresentation() throws {
        let state = OpenUIState(schema: schema())
        state.setSource("q=Query(\"load\",{},null)\nroot=Box(\"bounded\")")
        state.runQuery(statementId: "q", tool: "load", args: deepValue())
        XCTAssertTrue(state.isInterrupted)
        XCTAssertFalse(state.canExecuteActions)
        XCTAssertEqual(PropValue.value(try XCTUnwrap(state.root), "value"), .string("bounded"))
        XCTAssertFalse(state.errors.isEmpty)
    }

    func testStandaloneMutationRejectsOversizedResultsWithoutHangingItsAwait() async {
        let provider = FixedProvider(result: deepValue())
        let manager = QueryManager(provider: provider)
        let outcome = await manager.runMutation(statementId: "save", tool: "save", args: .object([]))
        XCTAssertEqual(outcome.status, .error)
        XCTAssertTrue(manager.nativeLimitExceeded)
        XCTAssertTrue(manager.isDisposed)
        let calls = await provider.calls
        XCTAssertEqual(calls, 1)
    }

    func testChangedQueryKeyCannotDispatchAnOldRequestAfterPreflightSuspends() async {
        let oldWaiting = expectation(description: "Old key awaits presentation")
        let newWaiting = expectation(description: "New key awaits presentation")
        let newCalled = expectation(description: "Current key enters provider")
        let oldCalled = expectation(description: "Old key entered provider")
        oldCalled.isInverted = true
        let gate = PendingDispatchGate { index in
            if index == 1 { oldWaiting.fulfill() } else { newWaiting.fulfill() }
        }
        let provider = PendingDispatchProvider { value in
            if value == .number(2) { newCalled.fulfill() } else { oldCalled.fulfill() }
        }
        let manager = QueryManager(provider: provider)
        defer { manager.dispose() }
        manager.setAutomaticDispatchCheck { _ in await gate.check() }
        let evaluator = queryEvaluator()
        manager.evaluateStatements([query(version: 1)], evaluator: evaluator)
        await fulfillment(of: [oldWaiting], timeout: 2)
        manager.evaluateStatements([query(version: 2)], evaluator: evaluator)
        await fulfillment(of: [newWaiting], timeout: 2)
        await gate.open()
        await fulfillment(of: [newCalled], timeout: 2)
        await fulfillment(of: [oldCalled], timeout: 0.1)
        let calls = await provider.calls
        XCTAssertEqual(calls, [.number(2)], "The official key, including arguments, must still own this request")
    }

    func testRemovedQueryCannotDispatchItsPendingRequest() async {
        let waiting = expectation(description: "Removed query awaits presentation")
        let called = expectation(description: "Removed query entered provider")
        called.isInverted = true
        let gate = PendingDispatchGate { _ in waiting.fulfill() }
        let provider = PendingDispatchProvider { _ in called.fulfill() }
        let manager = QueryManager(provider: provider)
        defer { manager.dispose() }
        manager.setAutomaticDispatchCheck { _ in await gate.check() }
        let evaluator = queryEvaluator()
        manager.evaluateStatements([query(version: 1)], evaluator: evaluator)
        await fulfillment(of: [waiting], timeout: 2)
        manager.evaluateStatements([], evaluator: evaluator)
        await gate.open()
        await fulfillment(of: [called], timeout: 0.1)
        let calls = await provider.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertNil(manager.queryState(for: "q"))
    }

    func testUnchangedQueryKeySurvivesPatchWhileItsPreflightIsPending() async {
        let waiting = expectation(description: "Retained query awaits presentation")
        let called = expectation(description: "Retained query enters provider")
        let gate = PendingDispatchGate { _ in waiting.fulfill() }
        let provider = PendingDispatchProvider { _ in called.fulfill() }
        let manager = QueryManager(provider: provider)
        defer { manager.dispose() }
        manager.setAutomaticDispatchCheck { _ in await gate.check() }
        let evaluator = queryEvaluator()
        manager.evaluateStatements([query(version: 1)], evaluator: evaluator)
        await fulfillment(of: [waiting], timeout: 2)
        manager.evaluateStatements([query(version: 1, defaults: .str("updated default"))], evaluator: evaluator)
        XCTAssertEqual(manager.queryState(for: "q")?.data, .string("updated default"))
        await gate.open()
        await fulfillment(of: [called], timeout: 2)
        let calls = await provider.calls
        XCTAssertEqual(calls, [.number(1)], "A presentation patch must not cancel an unchanged official request key")
    }

    func testExplicitQueryEvaluationLimitSettlesItsRegisteredCallback() {
        let parsed = createParser(schema: schema()).parse("""
        $rows=[]
        q=Query("load",{values:@Each($rows,a,@Each($rows,b,@Each($rows,c,@Each($rows,d,@Each($rows,e,1)))))},null)
        root=Box(q)
        """)
        let store = createStore()
        store.initialize(defaults: parsed.stateDeclarations, persisted: [:])
        let evaluator = Evaluator(context: EvaluationContext(getState: { store.get($0) ?? .null }, resolveRef: { _ in .null }), schema: schema())
        let manager = QueryManager(provider: nil)
        defer { manager.dispose() }
        manager.evaluateStatements(parsed.queryStatements, evaluator: evaluator)
        XCTAssertFalse(evaluator.nativeLimitExceeded)
        store.set("$rows", value: .array((0..<30).map { .number(Double($0)) }), pristine: false)
        let settled = expectation(description: "Explicit query failure settled")
        manager.runQuery(statementId: "q", tool: "load", args: .object([]), defaults: .null,
            onSettled: { settled.fulfill() })
        wait(for: [settled], timeout: 1)
        XCTAssertTrue(evaluator.nativeLimitExceeded)
        XCTAssertTrue(manager.nativeLimitExceeded)
        XCTAssertTrue(manager.isDisposed)
    }

    private func query(version: Double, defaults: ASTNode = .null) -> QueryStatementInfo {
        QueryStatementInfo(statementId: "q", toolAST: .str("load"), argsAST: .obj([("version", .num(version))]),
            defaultsAST: defaults, refreshAST: nil, deps: nil, complete: true)
    }

    private func queryEvaluator() -> Evaluator {
        Evaluator(context: EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null }), schema: LibrarySchema())
    }

    private func deepValue() -> Value {
        var value = Value.number(1)
        for _ in 0..<300 { value = .array([value]) }
        return value
    }

    private func providerEnteredWhileMainActorIsBusy(_ signal: DispatchSemaphore) -> Bool {
        // This short synchronous section deliberately models a busy UI actor.
        // It is not the asynchronous wait used to finish the test.
        signal.wait(timeout: .now() + 0.1) == .success
    }
}

private actor ReaderProvider: ToolProvider {
    private(set) var calls: [String] = []
    private let rows = ReaderRowsGate()
    private let onRows: @Sendable () -> Void
    private let onReader: @Sendable () -> Void
    init(onRows: @escaping @Sendable () -> Void, onReader: @escaping @Sendable () -> Void) {
        self.onRows = onRows; self.onReader = onReader
    }
    func callTool(name: OpenUIString, arguments: OpenUIObject) async throws -> Value {
        calls.append(name.displayString)
        if name == "rows" {
            return await withCheckedContinuation { rows.store($0); onRows() }
        }
        onReader()
        return .null
    }
    nonisolated func finishRows(_ value: Value) { rows.finish(value) }
}

private final class ReaderRowsGate: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: CheckedContinuation<Value, Never>?
    func store(_ continuation: CheckedContinuation<Value, Never>) {
        lock.lock(); pending = continuation; lock.unlock()
    }
    func finish(_ value: Value) {
        lock.lock(); let continuation = pending; pending = nil; lock.unlock()
        continuation?.resume(returning: value)
    }
}

private actor FixedProvider: ToolProvider {
    let result: Value
    private(set) var calls = 0
    init(result: Value) { self.result = result }
    func callTool(name: OpenUIString, arguments: OpenUIObject) async throws -> Value {
        calls += 1
        return result
    }
}

private actor PendingDispatchGate {
    private let onWait: @Sendable (Int) -> Void
    private var waiting: [CheckedContinuation<Bool, Never>] = []
    private var opened = false
    init(onWait: @escaping @Sendable (Int) -> Void) { self.onWait = onWait }
    func check() async -> Bool {
        if opened { return true }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            onWait(waiting.count)
        }
    }
    func open() {
        opened = true
        let continuations = waiting
        waiting = []
        continuations.forEach { $0.resume(returning: true) }
    }
}

private actor PendingDispatchProvider: ToolProvider {
    private let onCall: @Sendable (Value) -> Void
    private(set) var calls: [Value] = []
    init(onCall: @escaping @Sendable (Value) -> Void) { self.onCall = onCall }
    func callTool(name: OpenUIString, arguments: OpenUIObject) async throws -> Value {
        let value = arguments["version"] ?? .null
        calls.append(value)
        onCall(value)
        return value
    }
}
