import JavaScriptCore
import XCTest
@testable import SwiftLang

final class EvaluationDefinitionsTests: XCTestCase {
    private let params = [ParamDef(name: "value", required: true)]

    func testSharedDefinitionsKeepExecutionReadersAndFunctionCallbacksSeparate() {
        let core = SharedCore.shared
        let definitions = CoreEvaluationDefinitions(
            functions: ["Echo": CustomFunction(params: params, fn: { $0["value"] ?? .undefined })],
            actions: ["Send": CallDef(kind: .action, params: params)])
        let store = createStore()
        store.set("$value", value: .number(1), pristine: false)
        let first = Evaluator(context: EvaluationContext(getState: { store.get($0) ?? .null },
            resolveRef: { _ in .null }, functions: definitions.functions, actions: definitions.actions),
            schema: LibrarySchema(), definitions: definitions)
        let second = Evaluator(context: EvaluationContext(getState: { _ in .number(7) },
            resolveRef: { _ in .null }, functions: definitions.functions, actions: definitions.actions),
            schema: LibrarySchema(), definitions: definitions)

        core.sync {
            let left = first.jsContext(), right = second.jsContext()
            func same(_ a: JSValue, _ b: JSValue) -> Bool {
                JSValueIsStrictEqual(core.context.jsGlobalContextRef, a.jsValueRef, b.jsValueRef)
            }
            XCTAssertTrue(same(left.forProperty("actions"), right.forProperty("actions")))
            let leftFunction = left.forProperty("functions").forProperty("Echo")!
            let rightFunction = right.forProperty("functions").forProperty("Echo")!
            XCTAssertTrue(same(leftFunction.forProperty("params"), rightFunction.forProperty("params")))
            XCTAssertFalse(same(leftFunction.forProperty("fn"), rightFunction.forProperty("fn")),
                "Callbacks retain their execution owner, input checks and failure observer")
            XCTAssertFalse(same(left.forProperty("getState"), right.forProperty("getState")))
        }
        let expression = ASTNode.comp(name: "Echo", args: [.stateRef("$value")], mappedProps: nil, fn: true)
        XCTAssertEqual(first.evaluate(expression), .number(1))
        XCTAssertEqual(second.evaluate(expression), .number(7))
        store.set("$value", value: .number(2), pristine: false)
        XCTAssertEqual(first.evaluate(expression), .number(2), "Prepared definitions must never cache a function result")
        XCTAssertEqual(second.evaluate(expression), .number(7))
        XCTAssertNil(first.nativeFailure)
        XCTAssertNil(second.nativeFailure)
    }

    func testEachContextKeepsItsOwnFailureObserverWithPreparedDefinitions() {
        let core = SharedCore.shared
        let definitions = CoreEvaluationDefinitions(functions: [:], actions: [:])
        let context = EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null })
        let first = Evaluator(context: context, schema: LibrarySchema(), definitions: definitions)
        let second = Evaluator(context: context, schema: LibrarySchema(), definitions: definitions)
        var observed: [String] = []
        core.sync {
            let previous = first.jsContext(onNativeFailure: { _ in observed.append("previous") })
            let current = first.jsContext(onNativeFailure: { _ in observed.append("current") })
            _ = previous.invokeMethod("reportNativeLimit", withArguments: [])
            XCTAssertEqual(observed, ["previous"])
            _ = current.invokeMethod("reportNativeLimit", withArguments: [])
            XCTAssertEqual(observed, ["previous", "current"])
        }
        XCTAssertTrue(first.nativeLimitExceeded)
        XCTAssertEqual(second.evaluate(.num(3)), .number(3))
        XCTAssertNil(second.nativeFailure, "A shared definition is not an execution or failure scope")
    }

    func testStandaloneEvaluatorsSnapshotMutableContextDefinitionsIndependently() {
        func function(_ value: String) -> CustomFunction {
            CustomFunction(params: [ParamDef(name: "value", required: true,
                hasDefault: true, defaultValue: .string(value))], fn: { $0["value"] ?? .undefined })
        }
        var context = EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null },
            functions: ["Echo": function("before")])
        let original = Evaluator(context: context, schema: LibrarySchema())
        context.functions["Echo"] = function("after")
        let replacement = Evaluator(context: context, schema: LibrarySchema())
        let expression = ASTNode.comp(name: "Echo", args: [], mappedProps: nil, fn: true)
        XCTAssertEqual(original.evaluate(expression), .string("before"))
        XCTAssertEqual(replacement.evaluate(expression), .string("after"))
        XCTAssertEqual(original.evaluate(expression), .string("before"))
        XCTAssertNil(original.nativeFailure)
        XCTAssertNil(replacement.nativeFailure)
    }

    func testObjectDefaultsKeepTheirPerContextIdentity() {
        let value = Value.object([.init(key: "items", value: .array([.number(1)]))])
        let params = [ParamDef(name: "value", required: true, hasDefault: true, defaultValue: value)]
        let definitions = CoreEvaluationDefinitions(
            functions: ["Default": CustomFunction(params: params, fn: { $0["value"] ?? .undefined })],
            actions: ["Send": CallDef(kind: .action, params: params)])
        let evaluator = Evaluator(context: EvaluationContext(getState: { _ in .null },
            resolveRef: { _ in .null }, functions: definitions.functions, actions: definitions.actions),
            schema: LibrarySchema(), definitions: definitions)
        let expression = ASTNode.comp(name: "Default", args: [], mappedProps: nil, fn: true)
        let first = evaluator.evaluate(expression), second = evaluator.evaluate(expression)
        XCTAssertEqual(first, value)
        XCTAssertEqual(second, value)
        XCTAssertFalse(first.isSameValue(as: second), "A default object is a fresh runtime value in each execution context")
        guard case .object(let left) = first, case .object(let right) = second,
              let leftItems = left["items"], let rightItems = right["items"] else {
            return XCTFail("Expected the nested object default")
        }
        XCTAssertFalse(leftItems.isSameValue(as: rightItems))
        guard case .array(let sameContext) = evaluator.evaluate(.arr([expression, expression])) else {
            return XCTFail("Expected two calls in the same execution context")
        }
        XCTAssertTrue(sameContext[0].isSameValue(as: sameContext[1]),
            "Repeated calls within one context still share that context's default")
        let core = SharedCore.shared
        core.sync {
            let firstContext = evaluator.jsContext(), secondContext = evaluator.jsContext()
            let firstDefault = firstContext.forProperty("actions").forProperty("Send")
                .forProperty("params").forProperty("properties").forProperty("value").forProperty("default")!
            let secondDefault = secondContext.forProperty("actions").forProperty("Send")
                .forProperty("params").forProperty("properties").forProperty("value").forProperty("default")!
            XCTAssertFalse(JSValueIsStrictEqual(core.context.jsGlobalContextRef,
                firstDefault.jsValueRef, secondDefault.jsValueRef))
        }
        XCTAssertNil(evaluator.nativeFailure)
    }

    func testNestedReturnDefaultsAreFreshAcrossContexts() {
        let returns = JSONValue.object([
            .init(key: "type", value: .string("object")),
            .init(key: "properties", value: .object([
                .init(key: "payload", value: .object([
                    .init(key: "default", value: .array([.number(1)]))
                ]))
            ])),
            .init(key: "required", value: .array([.string("payload")]))
        ])
        let evaluator = Evaluator(context: EvaluationContext(getState: { _ in .null },
            resolveRef: { _ in .null }, functions: ["Result": CustomFunction(params: [],
                returns: returns, fn: { _ in .object([]) })]), schema: LibrarySchema())
        let expression = ASTNode.comp(name: "Result", args: [], mappedProps: nil, fn: true)
        guard case .object(let first) = evaluator.evaluate(expression),
              case .object(let second) = evaluator.evaluate(expression),
              let firstDefault = first["payload"], let secondDefault = second["payload"] else {
            return XCTFail("Expected validation to fill the required nested return default")
        }
        XCTAssertEqual(firstDefault, .array([.number(1)]))
        XCTAssertEqual(secondDefault, .array([.number(1)]))
        XCTAssertFalse(firstDefault.isSameValue(as: secondDefault))
        XCTAssertNil(evaluator.nativeFailure)
    }
}
