import XCTest
@testable import SwiftLang

final class RuntimeWorkBudgetTests: XCTestCase {
    private func schema() -> LibrarySchema {
        LibrarySchema(components: [
            "Box": [ParamDef(name: "value", required: true)],
            "Stack": [ParamDef(name: "children", required: true,
                schema: .object([.init(key: "type", value: .string("array"))]))],
            "Text": [ParamDef(name: "text", required: true)],
            "Button": [ParamDef(name: "action", required: true)],
        ], callDefs: builtinCallDefs)
    }

    private func each(_ width: Int) -> (declaration: String, expression: String) {
        let items = (0..<width).map(String.init).joined(separator: ",")
        return ("$items=[\(items)]", "@Each($items,a,@Each($items,b,@Each($items,c,@Each($items,d,@Each($items,e,1)))))")
    }

    private func aliases(_ levels: Int) -> String {
        var source = ["leaf=Text(\"visible\")"]
        for index in 0..<levels {
            let previous = index == 0 ? "leaf" : "a\(index - 1)"
            source.append("a\(index)=Stack([\(previous),\(previous)])")
        }
        source.append("root=a\(levels - 1)")
        return source.joined(separator: "\n")
    }

    @MainActor func testNormalNestedEachStillProducesItsCompleteValue() throws {
        let state = OpenUIState(schema: schema())
        let program = each(5)
        state.setSource(program.declaration + "\nroot=Box(" + program.expression + ")")
        let root = try XCTUnwrap(state.root)
        func leaves(_ value: Value) -> Int {
            if case .array(let values) = value { return values.reduce(0) { $0 + leaves($1) } }
            return 1
        }
        XCTAssertEqual(leaves(try XCTUnwrap(PropValue.value(root, "value"))), 3_125)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertTrue(state.canExecuteActions)
    }

    @MainActor func testTinySourceCannotPublishMillionsOfValuesOrStartTools() async throws {
        let provider = RecordingProvider()
        let state = OpenUIState(schema: schema(), toolProvider: provider)
        state.setSource("root=Box(\"readable\")")
        let previous = try XCTUnwrap(state.root)
        let program = each(30)
        var observedLimit = false
        state.onParseResult = { observedLimit = $0.nativeLimitExceeded }
        state.setSource(program.declaration + "\nroot=Box(" + program.expression + ")\nq=Query(\"load\",{},[])")
        XCTAssertTrue(state.root === previous, "Keep only the previously bounded presentation")
        XCTAssertTrue(observedLimit)
        XCTAssertTrue(state.isInterrupted)
        XCTAssertFalse(state.canExecuteActions)
        XCTAssertFalse(state.errors.isEmpty)
        let calls = await provider.calls
        XCTAssertEqual(calls, 0, "Root work is checked before any automatic Query dispatch")

        state.setSource(program.declaration + "\nroot=Box(" + program.expression + ")", streaming: true)
        XCTAssertTrue(state.isInterrupted, "A second rejected replacement is still a stopped document")
        XCTAssertTrue(state.isComplete)
        XCTAssertTrue(state.root === previous)

        state.setSource("root=Box(\"recovered\")")
        XCTAssertEqual(PropValue.string(try XCTUnwrap(state.root), "value"), "recovered")
        XCTAssertTrue(state.errors.isEmpty)
        XCTAssertTrue(state.canExecuteActions)
    }

    func testAliasExpansionIsBoundedBeforeLazyNativeProjection() {
        let result = createParser(schema: schema()).parse(aliases(18))
        XCTAssertTrue(result.nativeLimitExceeded)
        XCTAssertTrue(result.meta.incomplete)
        XCTAssertNil(result.root, "A blocked result must not retain an unsafe lazy projection")
        XCTAssertTrue(result.queryStatements.isEmpty)
        XCTAssertTrue(result.mutationStatements.isEmpty)
    }

    @MainActor func testRepeatedElementOccurrencesCountAgainstRenderBudget() throws {
        let state = OpenUIState(schema: schema())
        state.setSource(aliases(10))
        let previous = try XCTUnwrap(state.root)
        XCTAssertTrue(state.errors.isEmpty)
        state.setSource(aliases(12))
        XCTAssertTrue(state.root === previous)
        XCTAssertTrue(state.isInterrupted)
        XCTAssertFalse(state.canExecuteActions)
    }

    @MainActor func testFailedActionEvaluationCannotWriteItsNullFallbackOrEmit() async throws {
        let state = OpenUIState(schema: schema())
        let program = each(30)
        state.setSource(program.declaration + "\n$selected=\"keep\"\nroot=Button(Action([@Set($selected,"
            + program.expression + "),@ToAssistant(\"must not emit\")]))")
        XCTAssertTrue(state.canExecuteActions)
        let plan = try XCTUnwrap(PropValue.actionPlan(try XCTUnwrap(state.root), "action"))
        let events = await state.perform(plan)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(state.stateValue("$selected"), .string("keep"))
        XCTAssertTrue(state.isInterrupted)
        XCTAssertFalse(state.canExecuteActions)
    }

    @MainActor func testFailedMutationArgumentsNeverReachTheProvider() async throws {
        let provider = RecordingProvider()
        let state = OpenUIState(schema: schema(), toolProvider: provider)
        let program = each(30)
        state.setSource(program.declaration + "\nsave=Mutation(\"save\",{rows:" + program.expression
            + "})\nroot=Button(Action([@Run(save),@ToAssistant(\"must not emit\")]))")
        let plan = try XCTUnwrap(PropValue.actionPlan(try XCTUnwrap(state.root), "action"))
        let events = await state.perform(plan)
        XCTAssertTrue(events.isEmpty)
        let calls = await provider.calls
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(state.canExecuteActions)
    }

    @MainActor func testMaterializationFailureCannotInitializeTruncatedStateOrStartQuery() async throws {
        let provider = RecordingProvider()
        let state = OpenUIState(schema: schema(), toolProvider: provider)
        state.setSource("$x=\"keep\"\nroot=Box(\"readable\")")
        let previous = try XCTUnwrap(state.root)
        var source = ["root=Button(@OpenUrl(\"https://example.test\"))", "q=Query(\"load\",{x:$x},[])", "$x=a0"]
        source += (0..<255).map { "a\($0)=a\($0 + 1)" }
        source.append("a255=\"ok\"")
        state.setSource(source.joined(separator: "\n"))
        XCTAssertTrue(state.root === previous)
        XCTAssertEqual(state.stateValue("$x"), .string("keep"))
        XCTAssertFalse(state.canExecuteActions)
        let calls = await provider.calls
        XCTAssertEqual(calls, 0)
    }

    @MainActor func testDefaultExpressionBudgetCannotBecomeNullStateOrToolArguments() async throws {
        let provider = RecordingProvider()
        let state = OpenUIState(schema: schema(), toolProvider: provider)
        state.setSource("$x=\"keep\"\nroot=Box(\"readable\")")
        let previous = try XCTUnwrap(state.root)
        let program = each(30)
        let source = program.declaration + "\n$x=" + program.expression + "\nroot=Box($x)\nq=Query(\"load\",{x:$x},[])"
        let parsed = createParser(schema: schema()).parse(source)
        XCTAssertTrue(parsed.nativeLimitExceeded)
        XCTAssertTrue(parsed.stateDeclarations.isEmpty)
        XCTAssertTrue(parsed.queryStatements.isEmpty)
        state.setSource(source)
        XCTAssertTrue(state.root === previous)
        XCTAssertEqual(state.stateValue("$x"), .string("keep"))
        XCTAssertFalse(state.canExecuteActions)
        let calls = await provider.calls
        XCTAssertEqual(calls, 0)
    }

    @MainActor func testChangedQueryDefaultStillPublishesSynchronouslyWithoutProvider() throws {
        let state = OpenUIState(schema: schema())
        state.setSource("$x=1\ndata=Query(\"load\",{},$x)\nroot=Box(data)")
        XCTAssertEqual(PropValue.value(try XCTUnwrap(state.root), "value"), .number(1))
        state.setState("$x", value: .number(2))
        XCTAssertEqual(PropValue.value(try XCTUnwrap(state.root), "value"), .number(2))
        XCTAssertTrue(state.errors.isEmpty)
    }

    @MainActor func testChangedQueryDefaultIsBudgetedBeforeItsNewToolRequest() async throws {
        let started = expectation(description: "Initial query started")
        let unexpected = expectation(description: "Over-budget update entered provider")
        unexpected.isInverted = true
        let provider = RecordingProvider(suspended: true) { count in
            if count == 1 { started.fulfill() } else { unexpected.fulfill() }
        }
        let state = OpenUIState(schema: schema(), toolProvider: provider)
        defer { state.reset(); Task { await provider.finish() } }
        state.setSource("""
            $items=[1]
            q=Query("load",{count:@Count($items)},$items)
            root=Box(@Each(q,a,@Each(q,b,@Each(q,c,@Each(q,d,@Each(q,e,1))))))
            """)
        await fulfillment(of: [started], timeout: 2)
        let previous = try XCTUnwrap(state.root)
        state.setState("$items", value: .array((0..<30).map { .number(Double($0)) }))
        XCTAssertTrue(state.root === previous)
        XCTAssertTrue(state.isInterrupted)
        XCTAssertFalse(state.canExecuteActions)
        await provider.finish()
        await fulfillment(of: [unexpected], timeout: 0.1)
        let calls = await provider.calls
        XCTAssertEqual(calls, 1, "Discard the count:30 request before creating its provider task")
    }

    private actor RecordingProvider: ToolProvider {
        private(set) var calls = 0
        private var suspended: Bool
        private var waiting: [CheckedContinuation<Value, Never>] = []
        private let onCall: (@Sendable (Int) -> Void)?
        init(suspended: Bool = false, onCall: (@Sendable (Int) -> Void)? = nil) {
            self.suspended = suspended; self.onCall = onCall
        }
        func callTool(name: OpenUIString, arguments: OpenUIObject) async throws -> Value {
            calls += 1
            onCall?(calls)
            if suspended { return await withCheckedContinuation { waiting.append($0) } }
            return .null
        }
        func finish() {
            suspended = false
            let pending = waiting
            waiting = []
            pending.forEach { $0.resume(returning: .null) }
        }
    }
}
