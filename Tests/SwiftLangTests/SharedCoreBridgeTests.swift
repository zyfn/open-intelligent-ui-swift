import Dispatch
import JavaScriptCore
import XCTest
@testable import SwiftLang

final class SharedCoreBridgeTests: XCTestCase {
    private final class WeakManager { weak var value: QueryManager?; init(_ value: QueryManager?) { self.value = value } }

    private func referenceFactories() -> [(String, () -> Value)] {
        [
            ("array", { .array([.number(1)]) }),
            ("object", { .object([.init(key: "value", value: .string("held"))]) }),
            ("element", { .element(EvaluatedElement(typeName: "Text", props: [("value", .string("held"))])) }),
            ("plan", { .actionPlan(ActionPlan(steps: [.reset(targets: ["$field"])])) }),
            ("binding", { .binding("$field") }),
            ("reactive binding", { .reactiveBinding(target: "$field", expression: .binOp("+", .stateRef("$value"), .num(1))) })
        ]
    }

    func testUnbridgedReferenceValuesReleaseNormally() {
        // This path does not ask for SharedCore. An empty identity slot must
        // not turn ordinary native value destruction into a JSC operation.
        for (name, make) in referenceFactories() {
            var value: Value? = make()
            weak var native = value?.referenceObject
            XCTAssertNotNil(native, name)
            value = nil
            XCTAssertNil(native, name)
        }
    }

    func testNativeReferencesReleaseJSWrappersWithoutAnotherBridgeOperation() {
        let core = SharedCore.shared
        for (name, make) in referenceFactories() {
            var value: Value?
            weak var native: AnyObject?
            weak var wrapper: JSValue?
            autoreleasepool {
                value = make()
                native = value?.referenceObject
                core.sync { wrapper = core.encode(value!) }
            }
            XCTAssertNotNil(native, name)
            XCTAssertNotNil(wrapper, "The live \(name) must own its bridge identity")
            value = nil
            // No new sync, parser push, timer, or explicit GC follows release.
            // These are native/JSValue wrapper lifetime checks, not a claim
            // about when JavaScriptCore collects the JS heap or returns RSS.
            XCTAssertNil(native, name)
            XCTAssertNil(wrapper, "A dead \(name) must not leave a global strong JSValue record")
        }
    }

    func testReadinessSnapshotsKeepIdentityWhenEitherProjectionIsReleased() {
        let core = SharedCore.shared
        core.sync {
            for releaseOlder in [true, false] {
                let js = core.object([("type", core.string("element")),
                    ("typeName", core.string("Text")),
                    ("props", core.object([("value", core.string("same"))]))])
                _ = core.call("tagNativeSource", [js, false])
                var snapshots = [core.decode(js)]
                _ = core.call("tagNativeSource", [js, true])
                snapshots.append(core.decode(js))
                XCTAssertFalse(snapshots[0].isSameSnapshot(as: snapshots[1]))
                XCTAssertTrue(snapshots[0].isSameValue(as: snapshots[1]))
                XCTAssertEqual((snapshots[0].referenceObject as? EvaluatedElement)?.isSourceComplete, false)
                XCTAssertEqual((snapshots[1].referenceObject as? EvaluatedElement)?.isSourceComplete, true)

                weak var retired = snapshots[releaseOlder ? 0 : 1].referenceObject
                snapshots.remove(at: releaseOlder ? 0 : 1)
                XCTAssertNil(retired)
                let survivor = snapshots[0]
                XCTAssertTrue(JSValueIsStrictEqual(core.context.jsGlobalContextRef,
                    core.encode(survivor).jsValueRef, js.jsValueRef),
                    "A retained older projection must still encode the original JS object")
                let current = core.decode(js)
                XCTAssertTrue(current.isSameValue(as: survivor))
                if releaseOlder {
                    XCTAssertTrue(current.isSameSnapshot(as: survivor),
                        "Retiring an older slot must not erase the current reverse lookup")
                } else {
                    XCTAssertFalse(current.isSameSnapshot(as: survivor))
                    XCTAssertEqual((survivor.referenceObject as? EvaluatedElement)?.isSourceComplete, false,
                        "Recreating current readiness must not mutate the retained old snapshot")
                }
                XCTAssertEqual((current.referenceObject as? EvaluatedElement)?.isSourceComplete, true)
            }
        }
    }

    func testCapturedPlanReleasesItsNativeGraphAndJSWrappers() {
        let core = SharedCore.shared
        var value: Value?
        weak var plan: AnyObject?
        weak var payload: AnyObject?
        weak var planWrapper: JSValue?
        weak var payloadWrapper: JSValue?
        autoreleasepool {
            let captured = Value.object([.init(key: "answer", value: .number(42))])
            value = .actionPlan(ActionPlan(steps: [.continueConversation(
                messageAST: .runtimeValue(.string("send")), contextAST: .runtimeValue(captured))]))
            plan = value?.referenceObject
            payload = captured.referenceObject
            core.sync {
                planWrapper = core.encode(value!)
                payloadWrapper = core.encode(captured)
            }
        }
        XCTAssertNotNil(planWrapper)
        XCTAssertNotNil(payloadWrapper)
        value = nil
        XCTAssertNil(plan)
        XCTAssertNil(payload)
        XCTAssertNil(planWrapper)
        XCTAssertNil(payloadWrapper)
    }

    func testFinalNativeReleaseDoesNotWaitForTheRealmLock() {
        // The holder is handed to one worker; the test does not read its value
        // again. The semaphore makes final weak-reference checks sequential.
        final class Owner: @unchecked Sendable {
            var value: Value? = .object([.init(key: "held", value: .boolean(true))])
        }
        let core = SharedCore.shared
        core.sync {
            let owner = Owner()
            weak var native = owner.value?.referenceObject
            weak var wrapper: JSValue?
            autoreleasepool { wrapper = core.encode(owner.value!) }
            let released = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                owner.value = nil
                released.signal()
            }
            let result = released.wait(timeout: .now() + 2)
            XCTAssertEqual(result, .success,
                "Final ARC release must not wait for a Core lock held by another thread")
            if result == .success {
                XCTAssertNil(native)
                XCTAssertNil(wrapper)
            }
        }
    }

    func testParsedRootSnapshotMatchesTypedFallbackAfterNativeEdits() throws {
        let schema = LibrarySchema(components: ["Text": [ParamDef(name: "text", required: true)]],
                                   callDefs: builtinCallDefs, rootComponent: "Text")
        let parser = createParser(schema: schema)
        let original = parser.parse("root=Text(\"first\")")
        let later = parser.parse("root=Text(\"later\")")
        let evaluator = Evaluator(context: EvaluationContext(getState: { _ in .null },
            resolveRef: { _ in .null }), schema: schema)
        XCTAssertEqual(try XCTUnwrap(evaluator.evaluateRoot(original)).props.first?.1, .string("first"))
        XCTAssertEqual(try XCTUnwrap(evaluator.evaluateRoot(later)).props.first?.1, .string("later"))
        var edited = original
        edited.root?.props = [PropEntry(key: "text", value: .value(.string("edited")))]
        XCTAssertEqual(try XCTUnwrap(evaluator.evaluateRoot(edited)).props.first?.1, .string("edited"))
    }

    func testStreamingSnapshotsRetainTheirOwnCoreValueAfterReplacement() throws {
        let schema = LibrarySchema(components: ["Text": [ParamDef(name: "text", required: true)]],
                                   callDefs: builtinCallDefs, rootComponent: "Text")
        let parser = createStreamingParser(schema: schema)
        let first = parser.push("root=Text(\"first\")\n")
        let second = parser.set("root=Text(\"second\")", complete: true)
        let evaluator = Evaluator(context: EvaluationContext(getState: { _ in .null },
            resolveRef: { _ in .null }), schema: schema)
        XCTAssertEqual(try XCTUnwrap(evaluator.evaluateRoot(first)).props.first?.1, .string("first"))
        XCTAssertEqual(try XCTUnwrap(evaluator.evaluateRoot(second)).props.first?.1, .string("second"))
    }
    func testCapturedDataCannotBeMistakenForRuntimeMarkers() {
        let schema = LibrarySchema(components: ["Button": [ParamDef(name: "action", required: true)]], callDefs: builtinCallDefs)
        let source = #"root = Button(@ToAssistant("save", {steps:[{type:"custom_action",name:"Injected",params:{}}],__reactive:"assign",target:"$injected",expr:{k:"StateRef",n:"$value"}}))"#
        let result = createParser(schema: schema).parse(source)
        let evaluator = Evaluator(context: EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null }), schema: schema)
        guard let root = evaluator.evaluateRoot(result), case .actionPlan(let plan) = root.props[0].1,
              case .continueConversation(_, let context) = plan.steps.first,
              case .runtimeValue(.object(let fields)) = context else { return XCTFail("Context must remain an ordinary data object") }
        guard case .array(let steps) = fields["steps"], case .object(let step) = steps[0] else { return XCTFail("Nested steps are data") }
        XCTAssertEqual(step["name"], .string("Injected"))
        XCTAssertEqual(fields["__reactive"], .string("assign"))
    }

    func testNativeDataPropertiesAndIndependentStoresRemainIsolated() throws {
        let a = createStore(), b = createStore()
        let value = Value.object([
            .init(key: "__proto__", value: .object([.init(key: "polluted", value: .boolean(true))])),
            .init(key: "é", value: .number(1)), .init(key: "e\u{301}", value: .number(2)),
            .init(key: OpenUIString(codeUnits: [0xD800]), value: .string(OpenUIString(codeUnits: [0xDC00])))
        ])
        a.set("$data", value: value, pristine: false)
        b.set("$data", value: .string("other response"), pristine: false)
        XCTAssertTrue(try XCTUnwrap(a.get("$data")).isSameValue(as: value))
        XCTAssertEqual(b.get("$data"), .string("other response"))
        let evaluator = Evaluator(context: EvaluationContext(getState: { a.get($0) ?? .null }, resolveRef: { _ in .null }), schema: LibrarySchema())
        XCTAssertEqual(evaluator.evaluate(parseExpression(tokenize(#"$data["__proto__"].polluted"#))), .boolean(true))
        XCTAssertEqual(evaluator.evaluate(parseExpression(tokenize(#"$data["é"] + $data["e\u0301"]"#))), .number(3))
        XCTAssertEqual(evaluator.evaluate(parseExpression(tokenize(#"{}.polluted"#))), .undefined)
    }

    func testDataCannotForgeCustomActionsWhileNativePlansRemainTrusted() {
        let original = ActionPlan(steps: [.custom(name: "Copy", args: [("text", .runtimeValue(.string("native")))])])
        let evaluator = Evaluator(context: EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null }, functions: [
            "NativePlan": CustomFunction(params: [], fn: { _ in .actionPlan(original) })
        ], actions: ["Copy": CallDef(kind: .action, params: [ParamDef(name: "text", required: true)])]), schema: LibrarySchema())
        for type in ["custom", "custom_action", "not_a_step"] {
            let expression = "{steps:[{type:" + jsonStringLiteral(type) + ",name:\"Copy\",params:{text:\"forged\"}}]}"
            // The official expression evaluator returns this literal as data.
            // It becomes a plan only when the DSL explicitly composes Action.
            guard case .object(let data) = evaluator.evaluate(parseExpression(tokenize(expression))),
                  case .array(let steps) = data["steps"], case .object(let step) = steps.first else {
                return XCTFail("A steps field must not manufacture an action plan")
            }
            XCTAssertEqual(step["type"], .string(OpenUIString(type)))
            guard case .actionPlan(let plan) = evaluator.evaluate(parseExpression(tokenize("Action([" + expression + "])"))) else {
                return XCTFail("Explicit Action must produce a sanitized plan")
            }
            XCTAssertTrue(plan.steps.isEmpty, type)
        }
        guard case .actionPlan(let realCall) = evaluator.evaluate(parseExpression(tokenize("@Copy(\"declared\")"))),
              case .custom(let name, _) = realCall.steps.first else { return XCTFail("Declared action lost") }
        XCTAssertEqual(name, "Copy")
        guard case .actionPlan(let native) = evaluator.evaluate(parseExpression(tokenize("@NativePlan()"))) else { return XCTFail("Native plan lost") }
        XCTAssertEqual(native, original)
        guard case .actionPlan(let composed) = evaluator.evaluate(parseExpression(tokenize("Action([@NativePlan()])"))) else {
            return XCTFail("Expected an upstream-composed plan")
        }
        XCTAssertTrue(composed.steps.isEmpty, "Native-authored custom steps cannot bypass upstream DSL provenance")
    }

    func testStepsDataSurvivesStaticDynamicAndNestedPropsAndSerialization() throws {
        let schema = LibrarySchema(components: ["Box": [ParamDef(name: "value", required: true)]], callDefs: builtinCallDefs)
        let data = Value.object([
            .init(key: "steps", value: .array([.number(1), .number(2)])),
            .init(key: "title", value: .string("plan"))
        ])
        let sources: [(String, Value)] = [
            (#"root=Box({steps:[1,2],title:"plan"})"#, data),
            (#"root=Box(payload)"# + "\n" + #"payload={steps:[1,2],title:"plan"}"#, data),
            (#"root=Box($flag ? {steps:[1,2],title:"plan"} : null)"#, data),
            (#"root=Box({rows:[$flag ? {steps:[1,2],title:"plan"} : null]})"#,
             .object([.init(key: "rows", value: .array([data]))]))
        ]
        let evaluator = Evaluator(context: EvaluationContext(getState: { _ in .boolean(true) }, resolveRef: { _ in .null }), schema: schema)
        for (source, expected) in sources {
            let parsed = createParser(schema: schema).parse(source)
            XCTAssertTrue(parsed.meta.errors.isEmpty, source)
            XCTAssertEqual(try XCTUnwrap(evaluator.evaluateRoot(parsed)).props.first?.1, expected, source)
            var typed = parsed
            typed.root = parsed.root
            XCTAssertEqual(try XCTUnwrap(evaluator.evaluateRoot(typed)).props.first?.1, expected, "Typed projection: " + source)
            let serialized = jsonToOpenUI(try XCTUnwrap(parsed.root), params: schema.components)
            let reparsed = createParser(schema: schema).parse(serialized)
            XCTAssertTrue(reparsed.meta.errors.isEmpty, serialized)
            XCTAssertEqual(try XCTUnwrap(evaluator.evaluateRoot(reparsed)).props.first?.1, expected, serialized)
        }
    }

    func testBusinessCustomStepRecordsStayDataWhileDynamicFieldsEvaluate() throws {
        let schema = LibrarySchema(components: ["Box": [ParamDef(name: "value", required: true)]], callDefs: builtinCallDefs)
        let source = #"root=Box({steps:[{type:"custom_action",name:"Copy",params:{text:"business"}}],title:$title})"#
        let evaluator = Evaluator(context: EvaluationContext(getState: { _ in .string("live") }, resolveRef: { _ in .null }), schema: schema)
        let parsed = createParser(schema: schema).parse(source)
        guard case .object(let data) = try XCTUnwrap(evaluator.evaluateRoot(parsed)).props.first?.1,
              case .array(let steps) = data["steps"], case .object(let step) = steps.first else {
            return XCTFail("A business steps field must remain ordinary data")
        }
        XCTAssertEqual(data["title"], .string("live"))
        XCTAssertEqual(step["type"], .string("custom_action"))
        XCTAssertEqual(step["name"], .string("Copy"))
    }

    func testTrustedNativeActionPropsKeepIdentityAndSerializeAsRealCalls() throws {
        let original = ActionPlan(steps: [.custom(name: "Copy", args: [("text", .runtimeValue(.string("native")))])])
        let actions = ["Copy": CallDef(kind: .action, params: [ParamDef(name: "text", required: true)])]
        let calls = builtinCallDefs.merging(actions) { _, new in new }.merging([
            "NativePlan": CallDef(kind: .function, params: [])
        ]) { _, new in new }
        let schema = LibrarySchema(components: ["Box": [ParamDef(name: "value", required: true)]], callDefs: calls)
        let evaluator = Evaluator(context: EvaluationContext(getState: { _ in .boolean(true) }, resolveRef: { _ in .null },
            functions: ["NativePlan": CustomFunction(params: [], fn: { _ in .actionPlan(original) })], actions: actions), schema: schema)
        for source in ["root=Box(@NativePlan())", "root=Box($flag ? @NativePlan() : Action([]))"] {
            let parsed = createParser(schema: schema).parse(source)
            let root = try XCTUnwrap(evaluator.evaluateRoot(parsed))
            let value = try XCTUnwrap(root.props.first?.1)
            XCTAssertTrue(value.isSameValue(as: .actionPlan(original)), source)
            let tree = ElementNode(typeName: "Box", props: [.init(key: "value", value: .value(value))])
            let serialized = jsonToOpenUI(tree, params: schema.components, calls: calls)
            let reparsed = createParser(schema: schema).parse(serialized)
            XCTAssertTrue(reparsed.meta.errors.isEmpty, serialized)
            XCTAssertEqual(try XCTUnwrap(evaluator.evaluateRoot(reparsed)).props.first?.1, .actionPlan(original))
        }
    }

    func testBoundedRuntimeCapturesKeepNativeIdentityAndUndefined() {
        let evaluator = Evaluator(context: EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null }), schema: LibrarySchema())
        let values: [Value] = [.undefined, .null, .array([.number(1)]),
            .object([.init(key: "steps", value: .array([.number(1)]))]),
            .actionPlan(ActionPlan(steps: [.reset(targets: ["$x"])])), .binding("$x")]
        for value in values {
            let evaluated = evaluator.evaluate(.runtimeValue(value))
            XCTAssertTrue(evaluated.isSameValue(as: value))
            XCTAssertEqual(evaluated, value, "Direct captures must retain the original native Value case")
        }
        XCTAssertFalse(evaluator.nativeLimitExceeded)
    }

    func testBindingCachePreservesDirectAndReactiveCases() {
        let core = SharedCore.shared
        core.sync {
            for expression in [ASTNode.stateRef("$value"), .binOp("+", .stateRef("$value"), .num(2))] {
                let raw = core.object([
                    ("__reactive", core.string("assign")),
                    ("target", core.string("$field")),
                    ("expr", core.ast(expression))
                ])
                let first = core.decode(raw), second = core.decode(raw)
                XCTAssertEqual(second, first)
                XCTAssertTrue(second.isSameValue(as: first))
                if expression == .stateRef("$value") {
                    guard case .binding(let binding) = second else { return XCTFail("A cached direct binding changed its Value case") }
                    XCTAssertEqual(binding.target, "$field")
                } else {
                    guard case .reactiveBinding(let binding) = second else { return XCTFail("A reactive expression became a direct binding") }
                    XCTAssertEqual(binding.expression, expression)
                }
            }
        }
    }

    func testStoreBindingRoundTripsPreserveCasesAndIdentity() throws {
        let store = createStore()
        let values: [Value] = [.binding("$field"), .reactiveBinding(target: "$field",
            expression: .binOp("+", .stateRef("$value"), .num(2)))]
        for (index, value) in values.enumerated() {
            let key = OpenUIString("$binding\(index)")
            store.set(key, value: value, pristine: false)
            let first = try XCTUnwrap(store.get(key)), second = try XCTUnwrap(store.get(key))
            XCTAssertEqual(first, value)
            XCTAssertEqual(second, value)
            XCTAssertTrue(first.isSameValue(as: value))
            XCTAssertTrue(second.isSameValue(as: value))
        }
    }

    func testOpaqueRuntimeCapturesRetainIdentityInsideExpressions() {
        let object = Value.object([.init(key: "n", value: .number(3))])
        let identity = CustomFunction(params: [ParamDef(name: "value", required: true)], fn: { $0["value"] ?? .null })
        let evaluator = Evaluator(context: EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .string("declared reference") }, functions: ["Identity": identity]), schema: LibrarySchema())
        let expression = ASTNode.binOp("==", .runtimeValue(object), .comp(name: "Identity", args: [.runtimeValue(object)], mappedProps: nil, fn: true))
        XCTAssertEqual(evaluator.evaluate(expression), .boolean(true))
        XCTAssertEqual(evaluator.evaluate(.runtimeRef("__swift_capture_1", refType: .query)), .string("declared reference"))
    }

    func testNativeFunctionFailureIsCaughtAndReportedBySharedCore() {
        let context = EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null }, functions: [
            "Fail": CustomFunction(params: [], fn: { _ in throw NSError(domain: "fixture", code: 7) })
        ])
        let evaluator = Evaluator(context: context, schema: LibrarySchema())
        XCTAssertEqual(evaluator.evaluate(parseExpression(tokenize("@Fail()"))), .null)
        XCTAssertEqual(evaluator.errors.last?.code, .runtimeError)
        XCTAssertTrue(evaluator.errors.last?.message.contains("@Fail threw") == true)
        XCTAssertEqual(evaluator.evaluate(parseExpression(tokenize("1 + 2"))), .number(3), "The next transaction is usable after a native throw")
    }

    func testDisposalReleasesNativeManagerAndStopsRefresh() {
        let done = expectation(description: "Refresh teardown")
        Task {
            defer { done.fulfill() }
            actor Provider: ToolProvider {
                var calls = 0
                func callTool(name: OpenUIString, arguments: OpenUIObject) async throws -> Value { calls += 1; return .number(Double(calls)) }
                func count() -> Int { calls }
            }
            let provider = Provider()
            var manager: QueryManager? = QueryManager(provider: provider)
            let released = WeakManager(manager)
            manager?.evaluateStatements([QueryStatementInfo(statementId: "q", toolAST: .str("load"), argsAST: .obj([]),
                defaultsAST: .null, refreshAST: .num(0.01), deps: nil, complete: true)],
                evaluator: Evaluator(context: EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null }), schema: LibrarySchema()))
            for _ in 0..<100 { if await provider.count() >= 2 { break };try? await Task.sleep(nanoseconds: 1_000_000) }
            let activeCount = await provider.count()
            XCTAssertGreaterThanOrEqual(activeCount, 2)
            manager?.dispose();manager = nil
            let deallocated = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in released.value == nil }, object: nil)
            let releaseResult = await XCTWaiter.fulfillment(of: [deallocated], timeout: 2)
            XCTAssertEqual(releaseResult, .completed, "Disposed managers must release after in-flight callbacks unwind")
            XCTAssertNil(released.value)
            try? await Task.sleep(nanoseconds: 10_000_000)
            let count = await provider.count()
            try? await Task.sleep(nanoseconds: 30_000_000)
            let finalCount = await provider.count()
            XCTAssertEqual(finalCount, count)
        }
        wait(for: [done], timeout: 3)
    }
}
