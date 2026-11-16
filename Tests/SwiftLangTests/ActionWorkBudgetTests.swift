import XCTest
@testable import SwiftLang

final class ActionWorkBudgetTests: XCTestCase {
    @MainActor func testStateEventsAndQueryObservationsKeepTheirStepOrder() async {
        let store = createStore()
        defer { store.dispose() }
        store.set("$count", value: .number(0), pristine: true)
        let evaluator = Evaluator(context: EvaluationContext(
            getState: { store.get($0) ?? .null }, resolveRef: { _ in .null }), schema: LibrarySchema())
        let budget = NativeActionWorkBudget()
        evaluator.nativeWorkBudget = budget
        var observations: [String] = []
        func count() -> Int {
            if let stored = store.get("$count"), case .number(let value) = stored { return Int(value) }
            return -1
        }
        var context = ActionRuntimeContext(store: store, evaluate: evaluator.evaluate,
            stateDefaults: ["$count": .number(0)],
            runQuery: { observations.append("query:\($0):\(count())") },
            runMutation: { _ in .failure },
            formState: { [("$count", store.get("$count") ?? .null)] },
            onStateChange: { observations.append("state:\(count())") },
            onEvent: { observations.append("event:\($0.type.displayString):\(count())") })
        context.nativeWorkBudget = budget
        let plan = ActionPlan(steps: [
            .set(target: "$count", valueAST: .num(1)),
            .custom(name: "changed", args: [("value", .stateRef("$count"))]),
            .run(statementId: "load", refType: .query),
            .set(target: "$count", valueAST: .binOp("+", .stateRef("$count"), .num(1))),
            .continueConversation(messageAST: .stateRef("$count"), contextAST: nil),
            .reset(targets: ["$count"]),
            .continueConversation(messageAST: .stateRef("$count"), contextAST: nil),
        ])
        let events = await runActionPlan(plan, context: context)
        XCTAssertEqual(observations, ["state:1", "event:changed:1", "query:load:1", "state:2",
                                      "event:continue_conversation:2", "state:0", "event:continue_conversation:0"])
        XCTAssertEqual(events.map(\.humanFriendlyMessage), ["", "2", "0"])
        XCTAssertEqual(events.compactMap { $0.formState?.first?.1 }, [.number(1), .number(2), .number(0)])
        XCTAssertFalse(budget.exceeded)
        XCTAssertFalse(evaluator.nativeLimitExceeded)
    }

    @MainActor func testWholeDocumentActionAccumulatesOtherwiseValidExpressionAndRootWork() async throws {
        let schema = LibrarySchema(components: ["Button": [ParamDef(name: "action", required: true)]], callDefs: builtinCallDefs)
        let state = OpenUIState(schema: schema)
        defer { state.reset() }
        let expression = ["a", "b", "c", "d", "e"].reversed().reduce("1") {
            "@Each($items,\($1),\($0))"
        }
        let steps = Array(repeating: "@Set($x,@Count(\(expression)))", count: 100)
            + ["@ToAssistant(\"must not emit\")"]
        state.setSource("$items=[0,1,2,3,4]\n$x=0\nroot=Button(Action([" + steps.joined(separator: ",") + "]))")
        XCTAssertTrue(state.canExecuteActions)
        let plan = try XCTUnwrap(PropValue.actionPlan(try XCTUnwrap(state.root), "action"))
        var updates = 0, dispatched = 0
        state.onStateUpdate = { _ in updates += 1 }
        state.onAction = { _ in dispatched += 1 }
        let events = await state.perform(plan)
        XCTAssertGreaterThan(updates, 0, "The accepted prefix is observable and is not rolled back")
        XCTAssertLessThan(updates, 100, "Per-expression bounds alone used to allow all 100 expensive steps")
        XCTAssertEqual(state.stateValue("$x"), .number(5), "Count reads the outer five-element result")
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(dispatched, 0)
        XCTAssertTrue(state.isInterrupted)
        XCTAssertFalse(state.canExecuteActions)
        XCTAssertFalse(state.errors.isEmpty)
    }

    @MainActor func testOversizedHandBuiltPlanRejectsBeforeAnyStepOrCallback() async {
        let store = createStore()
        defer { store.dispose() }
        var evaluated = 0, changed = 0, reported = 0
        var context = ActionRuntimeContext(store: store,
            evaluate: { _ in evaluated += 1; return .number(1) },
            runQuery: { _ in XCTFail("Rejected plan cannot run a Query") },
            runMutation: { _ in XCTFail("Rejected plan cannot run a Mutation"); return .failure },
            onStateChange: { changed += 1 })
        context.onNativeLimit = { reported += 1 }
        let huge = ASTNode.arr(Array(repeating: .num(1), count: 40_000))
        let plan = ActionPlan(steps: [.set(target: "$x", valueAST: huge), .run(statementId: "q", refType: .query)])
        let events = await runActionPlan(plan, context: context)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(evaluated, 0)
        XCTAssertEqual(changed, 0)
        XCTAssertEqual(reported, 1)
        XCTAssertTrue(store.getSnapshot().isEmpty)
    }

    @MainActor func testOversizedFormPayloadStopsBeforeAnExternalEvent() async {
        let store = createStore()
        defer { store.dispose() }
        let shared = Value.array(Array(repeating: .number(1), count: 60_000))
        var dispatched = 0, reported = 0
        var context = ActionRuntimeContext(store: store, evaluate: { _ in .string("next") },
            runQuery: { _ in }, runMutation: { _ in .failure },
            formState: { [(OpenUIString("first"), shared), (OpenUIString("second"), shared)] },
            onEvent: { _ in dispatched += 1 })
        context.onNativeLimit = { reported += 1 }
        let events = await runActionPlan(ActionPlan(steps: [
            .continueConversation(messageAST: .str("next"), contextAST: nil)
        ]), context: context)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(dispatched, 0)
        XCTAssertEqual(reported, 1)
    }

    @MainActor func testAlreadyCancelledActionDoesNotEvaluateWriteOrDispatch() async {
        let store = createStore()
        defer { store.dispose() }
        var evaluated = 0, dispatched = 0
        let context = ActionRuntimeContext(store: store, evaluate: { _ in evaluated += 1; return .number(1) },
            runQuery: { _ in dispatched += 1 }, runMutation: { _ in dispatched += 1; return .success(.null) })
        let action = Task { await runActionPlan(ActionPlan(steps: [
            .set(target: "$x", valueAST: .num(1)), .run(statementId: "save", refType: .mutation)
        ]), context: context) }
        action.cancel()
        let events = await action.value
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(evaluated, 0)
        XCTAssertEqual(dispatched, 0)
        XCTAssertTrue(store.getSnapshot().isEmpty)
    }
}
