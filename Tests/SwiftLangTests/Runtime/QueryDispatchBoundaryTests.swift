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

    @MainActor func testObsoleteOversizedQueryResultCannotStopChangedArguments() async throws {
        try await checkObsoleteOversizedQueryResponse(recreateDeclaration: false, result: .success(deepValue()))
    }

    @MainActor func testObsoleteOversizedQueryResultCannotStopRecreatedDeclaration() async throws {
        try await checkObsoleteOversizedQueryResponse(recreateDeclaration: true, result: .success(deepValue()))
    }

    @MainActor func testObsoleteOversizedQueryErrorIsDiscardedBeforeReadingItsDescription() async throws {
        for recreateDeclaration in [false, true] {
            let error = DescribedToolFailure(String(repeating: "x", count: NativeValueCost.maximumUTF16 + 1))
            try await checkObsoleteOversizedQueryResponse(recreateDeclaration: recreateDeclaration, result: .failure(error))
            XCTAssertEqual(error.descriptionCount, 0, "Obsolete errors must not be inspected or encoded")
        }
    }

    @MainActor private func checkObsoleteOversizedQueryResponse(recreateDeclaration: Bool, result: Result<Value, Error>) async throws {
        let firstStarted = expectation(description: "Original request entered provider")
        let currentStarted = expectation(description: "Current request entered provider")
        let obsoleteLimit = expectation(description: "Obsolete response stopped the current document")
        obsoleteLimit.isInverted = true
        let provider = ControlledResponseProvider { index in
            if index == 0 { firstStarted.fulfill() } else { currentStarted.fulfill() }
        }
        let state = OpenUIState(schema: schema(), toolProvider: provider)
        state.onError = { [weak state] errors in
            if !errors.isEmpty, state?.isInterrupted == true { obsoleteLimit.fulfill() }
        }
        defer { state.onError = nil; state.reset(); provider.finishAll() }
        state.setSource("$version=1\nq=Query(\"load\",{version:$version},\"waiting\")\nroot=Box(q)")
        await fulfillment(of: [firstStarted], timeout: 2)
        if recreateDeclaration {
            // Preserve the same native manager while removing and recreating
            // the declaration with exactly the original request key.
            state.applyPatch("q=null")
            state.applyPatch("q=Query(\"load\",{version:$version},\"waiting\")")
        } else {
            state.setState("$version", value: .number(2))
        }
        await fulfillment(of: [currentStarted], timeout: 2)
        provider.finish(0, result: result)
        await fulfillment(of: [obsoleteLimit], timeout: 0.2)
        XCTAssertFalse(state.isInterrupted)
        XCTAssertTrue(state.errors.isEmpty)

        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            state.queryStates["q"]?.status == .success
                && state.root.flatMap { PropValue.value($0, "value") } == .string("current")
        }, object: nil)
        provider.finish(1, value: .string("current"))
        await fulfillment(of: [settled], timeout: 2)
        XCTAssertTrue(state.canExecuteActions)
        XCTAssertTrue(state.errors.isEmpty)
        XCTAssertEqual(provider.callCount, 2)
    }

    @MainActor func testCurrentOversizedQueryResultStillStopsItsDocument() async throws {
        let started = expectation(description: "Current request entered provider")
        let stopped = expectation(description: "Current oversized result rejected")
        let provider = ControlledResponseProvider { _ in started.fulfill() }
        let state = OpenUIState(schema: schema(), toolProvider: provider)
        var reported = false
        state.onError = { [weak state] errors in
            if !reported, !errors.isEmpty, state?.isInterrupted == true {
                reported = true; stopped.fulfill()
            }
        }
        defer { state.onError = nil; state.reset(); provider.finishAll() }
        state.setSource("q=Query(\"load\",{},\"bounded\")\nroot=Box(q)")
        await fulfillment(of: [started], timeout: 2)
        provider.finish(0, value: deepValue())
        await fulfillment(of: [stopped], timeout: 2)
        XCTAssertTrue(state.isInterrupted)
        XCTAssertFalse(state.canExecuteActions)
        XCTAssertEqual(PropValue.value(try XCTUnwrap(state.root), "value"), .string("bounded"))
    }

    @MainActor func testCurrentOversizedQueryErrorStopsItsDocument() async throws {
        let started = expectation(description: "Current request entered provider")
        let stopped = expectation(description: "Current oversized error rejected")
        let provider = ControlledResponseProvider { _ in started.fulfill() }
        let state = OpenUIState(schema: schema(), toolProvider: provider)
        var reported = false
        state.onError = { [weak state] errors in
            if !reported, !errors.isEmpty, state?.isInterrupted == true {
                reported = true; stopped.fulfill()
            }
        }
        defer { state.onError = nil; state.reset(); provider.finishAll() }
        state.setSource("q=Query(\"load\",{},\"bounded\")\nroot=Box(q)")
        await fulfillment(of: [started], timeout: 2)
        provider.finish(0, result: .failure(MCPToolError(String(repeating: "x", count: NativeValueCost.maximumUTF16 + 1))))
        await fulfillment(of: [stopped], timeout: 2)
        XCTAssertTrue(state.isInterrupted)
        XCTAssertFalse(state.canExecuteActions)
        XCTAssertEqual(PropValue.value(try XCTUnwrap(state.root), "value"), .string("bounded"))
    }

    @MainActor func testSharedQueryRequestSurvivesRemovalOfItsOriginalDeclaration() async throws {
        let started = expectation(description: "Shared request entered provider")
        let provider = ControlledResponseProvider { index in if index == 0 { started.fulfill() } }
        let state = OpenUIState(schema: schema(), toolProvider: provider)
        defer { state.reset(); provider.finishAll() }
        state.setSource("first=Query(\"load\",{},null)\nkept=Query(\"load\",{},null)\nroot=Box(kept)")
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(provider.callCount, 1, "Both declarations share the same in-flight cache entry")
        state.applyPatch("first=null")
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            state.queryStates["kept"]?.status == .success
                && state.root.flatMap { PropValue.value($0, "value") } == .string("shared")
        }, object: nil)
        provider.finish(0, value: .string("shared"))
        await fulfillment(of: [settled], timeout: 2)
        XCTAssertTrue(state.canExecuteActions)
        XCTAssertTrue(state.errors.isEmpty)
        XCTAssertEqual(provider.callCount, 1, "Removing one consumer must not discard useful shared work")
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

    func testOversizedToolErrorsRetireTheManagerAndSettleMutationWaiters() async {
        let oversized = String(repeating: "x", count: NativeValueCost.maximumUTF16 + 1)
        let described = DescribedToolFailure(oversized)
        let failures: [Error] = [
            MCPToolError(oversized),
            described,
            ToolNotFoundError(toolName: oversized),
            ToolNotFoundError(toolName: "save", availableTools: Array(repeating: OpenUIString(""), count: NativeValueCost.maximumNodes)),
            ToolNotFoundError(toolName: "save", availableTools: Array(repeating: OpenUIString(String(repeating: "x", count: 1_024)), count: 1_025)),
        ]
        for failure in failures {
            let manager = QueryManager(tools: ["save": { _ in throw failure }])
            defer { manager.dispose() }
            let outcome = await manager.runMutation(statementId: "save", tool: "save", args: .object([]))
            XCTAssertEqual(outcome.status, .error)
            XCTAssertTrue(manager.nativeLimitExceeded)
            XCTAssertTrue(manager.isDisposed)
        }
        XCTAssertEqual(described.descriptionCount, 1, "Measure and encode from one Error description")
    }

    func testOrdinaryToolErrorsKeepTheirExistingCodesAndText() async throws {
        let described = DescribedToolFailure("transport unavailable")
        let failures: [(error: Error, code: OpenUIErrorCode, message: String, text: String, hint: String?)] = [
            (described, .toolError, "Mutation \"save\" failed: transport unavailable", "transport unavailable", nil),
            (MCPToolError("permission denied"), .mcpError, "Mutation \"save\" returned an error: permission denied", "MCP tool error: permission denied", nil),
            (ToolNotFoundError(toolName: "save", availableTools: ["read", "list"]), .toolNotFound,
                "Mutation tool \"save\" not found", "[openui] No handler for tool \"save\". Available: read, list", "Available tools: read, list"),
        ]
        for failure in failures {
            let manager = QueryManager(tools: ["save": { _ in throw failure.error }])
            defer { manager.dispose() }
            let outcome = await manager.runMutation(statementId: "save", tool: "save", args: .object([]))
            XCTAssertEqual(outcome.status, .error)
            let error = try XCTUnwrap(outcome.error)
            XCTAssertEqual(error.source, .mutation)
            XCTAssertEqual(error.code, failure.code)
            XCTAssertEqual(error.message, failure.message)
            XCTAssertEqual(error.hint, failure.hint)
            guard case .object(let fields) = outcome.value else { return XCTFail("Expected the ordinary mutation result") }
            XCTAssertEqual(fields["error"], .string(OpenUIString(failure.text)))
            XCTAssertFalse(manager.nativeLimitExceeded)
            XCTAssertFalse(manager.isDisposed)
        }
        XCTAssertEqual(described.descriptionCount, 1)
    }

    func testChangedAndRemovedQueriesCancelSuspendedProvidersBeforeTheyReturn() async {
        let started = (0..<3).map { expectation(description: "Request \($0) entered provider") }
        let cancelled = (0..<3).map { expectation(description: "Request \($0) cancelled while suspended") }
        let provider = ControlledResponseProvider(onCall: { index in fulfillProviderEvent(started, at: index) },
            onCancellation: { index in fulfillProviderEvent(cancelled, at: index) })
        let manager = QueryManager(provider: provider)
        defer { manager.dispose(); provider.finishAll() }
        let evaluator = queryEvaluator()
        for version in 1...3 {
            manager.evaluateStatements([query(version: Double(version))], evaluator: evaluator)
            await fulfillment(of: [started[version - 1]], timeout: 2)
            if version > 1 { await fulfillment(of: [cancelled[version - 2]], timeout: 2) }
            XCTAssertEqual(provider.cancelledIndices.sorted(), Array(0..<(version - 1)))
            XCTAssertEqual(manager.queryState(for: "q")?.status, .loading)
        }
        manager.evaluateStatements([], evaluator: evaluator)
        await fulfillment(of: [cancelled[2]], timeout: 2)
        XCTAssertEqual(provider.cancelledIndices.sorted(), [0, 1, 2])
        XCTAssertEqual(provider.callCount, 3)
        XCTAssertNil(manager.queryState(for: "q"))
        XCTAssertFalse(manager.isDisposed)
        XCTAssertFalse(manager.nativeLimitExceeded)
        // No provider continuation has returned: cancellation and native
        // Promise retirement must not depend on cooperation from transport.
    }

    func testSharedQueryCancelsItsProviderOnlyAfterTheLastConsumerIsRemoved() async {
        let started = expectation(description: "Shared provider entered")
        let cancelled = expectation(description: "Last consumer released shared provider")
        let provider = ControlledResponseProvider(onCall: { _ in started.fulfill() },
            onCancellation: { _ in cancelled.fulfill() })
        let manager = QueryManager(provider: provider)
        defer { manager.dispose(); provider.finishAll() }
        let evaluator = queryEvaluator()
        manager.evaluateStatements([query(version: 1, id: "first"), query(version: 1, id: "kept")], evaluator: evaluator)
        await fulfillment(of: [started], timeout: 2)
        manager.evaluateStatements([query(version: 1, id: "kept")], evaluator: evaluator)
        XCTAssertTrue(provider.cancelledIndices.isEmpty)
        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(manager.queryState(for: "kept")?.status, .loading)
        manager.evaluateStatements([], evaluator: evaluator)
        await fulfillment(of: [cancelled], timeout: 2)
        XCTAssertEqual(provider.cancelledIndices, [0])
        XCTAssertFalse(manager.isDisposed)
    }

    func testQueryKeyExchangeSurvivesAnIntermediateNewRequestNotification() async {
        let started = (0..<3).map { expectation(description: "Request \($0) entered provider") }
        let provider = ControlledResponseProvider { index in fulfillProviderEvent(started, at: index) }
        let manager = QueryManager(provider: provider)
        defer { manager.dispose(); provider.finishAll() }
        let evaluator = queryEvaluator()
        manager.evaluateStatements([query(version: 1, id: "left")], evaluator: evaluator)
        await fulfillment(of: [started[0]], timeout: 2)
        manager.evaluateStatements([query(version: 1, id: "left"), query(version: 2, id: "right")], evaluator: evaluator)
        await fulfillment(of: [started[1]], timeout: 2)
        // Starting middle publishes inside applyNodes, after left changes
        // away from key 1 but before right becomes that key's next consumer.
        manager.evaluateStatements([query(version: 2, id: "left"), query(version: 3, id: "middle"),
            query(version: 1, id: "right")], evaluator: evaluator)
        await fulfillment(of: [started[2]], timeout: 2)
        XCTAssertTrue(provider.cancelledIndices.isEmpty)
        XCTAssertEqual(provider.callCount, 3)
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            manager.queryState(for: "left")?.data == .string("B")
                && manager.queryState(for: "right")?.data == .string("A")
                && manager.queryState(for: "middle")?.data == .string("C")
        }, object: nil)
        provider.finish(0, value: .string("A"))
        provider.finish(1, value: .string("B"))
        provider.finish(2, value: .string("C"))
        await fulfillment(of: [settled], timeout: 2)
        XCTAssertTrue(provider.cancelledIndices.isEmpty)
    }

    @MainActor func testUpstreamCompletionCancelsItsObsoleteReaderWithoutWaitingForThatReader() async {
        let started = (0..<4).map { expectation(description: "Request \($0) entered provider") }
        let readerCancelled = expectation(description: "Old reader cancelled while suspended")
        let provider = ControlledResponseProvider(onCall: { index in fulfillProviderEvent(started, at: index) },
            onCancellation: { index in if index == 1 { readerCancelled.fulfill() } })
        let state = OpenUIState(schema: schema(), toolProvider: provider)
        defer { state.reset(); provider.finishAll() }
        state.setSource("upstream=Query(\"load\",{},0)\nreader=Query(\"read\",{version:upstream},\"waiting\")\nroot=Box(reader)")
        await fulfillment(of: [started[0]], timeout: 2)
        provider.finish(0, value: .number(1))
        await fulfillment(of: [started[1]], timeout: 2)
        state.runQuery(statementId: "upstream", tool: "load", args: .object([]), defaults: .number(0))
        await fulfillment(of: [started[2]], timeout: 2)
        provider.finish(2, value: .number(2))
        await fulfillment(of: [started[3], readerCancelled], timeout: 2)
        XCTAssertEqual(provider.cancelledIndices, [1])
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            state.queryStates["reader"]?.status == .success
                && state.root.flatMap { PropValue.value($0, "value") } == .string("current")
        }, object: nil)
        provider.finish(3, value: .string("current"))
        await fulfillment(of: [settled], timeout: 2)
        XCTAssertTrue(state.errors.isEmpty)
        XCTAssertTrue(state.canExecuteActions)
    }

    func testBatchRetirementSettlesEveryPromiseBeforeCancellationHandlersReenter() async {
        let started = (0..<5).map { expectation(description: "Request \($0) entered provider") }
        let reentered = expectation(description: "First cancellation synchronously reused the other old key")
        let provider = ControlledResponseProvider { index in fulfillProviderEvent(started, at: index) }
        let manager = QueryManager(provider: provider)
        defer { manager.dispose(); provider.finishAll() }
        let evaluator = queryEvaluator()
        let replacements = [query(version: 3, id: "left"), query(version: 4, id: "right")]
        let returned = [query(version: 2, id: "returned"), query(version: 1, id: "returned")]
        let reentry = ProviderCancellationGate()
        provider.setCancellationHandler { [weak manager] index in
            guard index < 2, reentry.claim() else { return }
            // Whichever old request is cancelled first, adopt the other old
            // key. Keeping left/right also keeps that key as previous data.
            manager?.evaluateStatements(replacements + [returned[index]], evaluator: evaluator)
            reentered.fulfill()
        }
        manager.evaluateStatements([query(version: 1, id: "left")], evaluator: evaluator)
        await fulfillment(of: [started[0]], timeout: 2)
        manager.evaluateStatements([query(version: 1, id: "left"), query(version: 2, id: "right")], evaluator: evaluator)
        await fulfillment(of: [started[1]], timeout: 2)
        manager.evaluateStatements(replacements, evaluator: evaluator)
        await fulfillment(of: [reentered, started[2], started[3], started[4]], timeout: 2)
        XCTAssertEqual(provider.callCount, 5, "The reused old key needs a new provider request")
        XCTAssertEqual(provider.callVersions.filter { $0 == .number(1) || $0 == .number(2) }.count, 3)
        XCTAssertEqual(provider.cancelledIndices.sorted(), [0, 1])
        XCTAssertEqual(manager.queryState(for: "returned")?.status, .loading)
        XCTAssertNil(manager.queryState(for: "returned")?.error)
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            manager.queryState(for: "returned")?.status == .success
                && manager.queryState(for: "returned")?.data == .string("accepted")
        }, object: nil)
        for index in 2..<5 { provider.finish(index, value: .string("accepted")) }
        await fulfillment(of: [settled], timeout: 2)
        XCTAssertNil(manager.queryState(for: "returned")?.error)
        XCTAssertFalse(manager.nativeLimitExceeded)
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

    private func query(version: Double, defaults: ASTNode = .null, id: String = "q") -> QueryStatementInfo {
        QueryStatementInfo(statementId: id, toolAST: .str("load"), argsAST: .obj([("version", .num(version))]),
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

private func fulfillProviderEvent(_ expectations: [XCTestExpectation], at index: Int) {
    guard expectations.indices.contains(index) else {
        XCTFail("Unexpected provider event at request \(index)")
        return
    }
    expectations[index].fulfill()
}

private final class ProviderCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

/// Intentionally ignores task cancellation so that acceptance is tested at the
/// SDK boundary, independently of whether a network provider cooperates.
private final class ControlledResponseProvider: ToolProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [Int: CheckedContinuation<Value, Error>] = [:]
    private var count = 0
    private var closed = false
    private var cancelled: [Int] = []
    private var versions: [Value] = []
    private let onCall: @Sendable (Int) -> Void
    private var onCancellation: @Sendable (Int) -> Void
    convenience init(onCall: @escaping @Sendable (Int) -> Void) {
        self.init(onCall: onCall, onCancellation: { _ in })
    }
    init(onCall: @escaping @Sendable (Int) -> Void, onCancellation: @escaping @Sendable (Int) -> Void) {
        self.onCall = onCall; self.onCancellation = onCancellation
    }
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    var callVersions: [Value] { lock.lock(); defer { lock.unlock() }; return versions }
    var cancelledIndices: [Int] { lock.lock(); defer { lock.unlock() }; return cancelled }
    func setCancellationHandler(_ handler: @escaping @Sendable (Int) -> Void) {
        lock.lock(); onCancellation = handler; lock.unlock()
    }
    private func nextIndex(arguments: OpenUIObject) -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return nil }
        let index = count; count += 1
        versions.append(arguments["version"] ?? .undefined)
        return index
    }
    private func recordCancellation(_ index: Int) {
        lock.lock(); cancelled.append(index)
        let handler = onCancellation; lock.unlock()
        handler(index)
    }
    func callTool(name: OpenUIString, arguments: OpenUIObject) async throws -> Value {
        guard let index = nextIndex(arguments: arguments) else { return .null }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !closed else { lock.unlock(); continuation.resume(returning: .null); return }
                pending[index] = continuation
                lock.unlock()
                onCall(index)
            }
        }, onCancel: { self.recordCancellation(index) })
    }
    func finish(_ index: Int, value: Value) {
        finish(index, result: .success(value))
    }
    func finish(_ index: Int, result: Result<Value, Error>) {
        lock.lock(); let continuation = pending.removeValue(forKey: index); lock.unlock()
        continuation?.resume(with: result)
    }
    func finishAll() {
        lock.lock(); closed = true
        let continuations = Array(pending.values); pending.removeAll(); lock.unlock()
        continuations.forEach { $0.resume(returning: .null) }
    }
}

private final class DescribedToolFailure: Error, CustomStringConvertible, @unchecked Sendable {
    private let text: String
    private let lock = NSLock()
    private var reads = 0
    init(_ text: String) { self.text = text }
    var descriptionCount: Int { lock.lock(); defer { lock.unlock() }; return reads }
    var description: String {
        lock.lock(); reads += 1; lock.unlock()
        return text
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
