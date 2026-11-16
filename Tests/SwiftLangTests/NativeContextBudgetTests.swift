import Foundation
import XCTest
@testable import SwiftLang

final class NativeContextBudgetTests: XCTestCase {
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func record() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }
    private func call(_ name: String) -> ASTNode { .comp(name: name, args: [], mappedProps: nil, fn: true) }
    private func nested(_ levels: Int) -> Value {
        var result = Value.number(1)
        for _ in 0..<levels { result = .array([result]) }
        return result
    }
    private func sharedTree(_ levels: Int) -> Value {
        var result = Value.number(1)
        for _ in 0..<levels { result = .array([result, result]) }
        return result
    }

    func testCustomFunctionRejectsWideDeepAndSharedValuesBeforeEncodingOrLaterCalls() {
        let values: [Value] = [.array(Array(repeating: .number(1), count: 100_000)), nested(257), sharedTree(40)]
        for value in values {
            let calls = Calls()
            let evaluator = Evaluator(context: EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null }, functions: [
                "Huge": CustomFunction(params: [], fn: { _ in value }),
                "Later": CustomFunction(params: [], fn: { _ in calls.record(); return .number(1) }),
            ]), schema: LibrarySchema())
            XCTAssertEqual(evaluator.evaluate(.arr([call("Huge"), call("Later")])), .null)
            XCTAssertTrue(evaluator.nativeLimitExceeded)
            XCTAssertEqual(calls.value, 0)
            XCTAssertEqual(evaluator.errors.count, 1, "The native limit is not an ordinary function error")
            XCTAssertEqual(evaluator.evaluate(call("Later")), .null)
            XCTAssertEqual(calls.value, 0, "A retired evaluator cannot resume native callbacks")
        }
        let fresh = Evaluator(context: EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null }), schema: LibrarySchema())
        XCTAssertEqual(fresh.evaluate(.num(3)), .number(3), "Failure must not leak into another budget scope")
        XCTAssertFalse(fresh.nativeLimitExceeded)
    }

    func testStateAndReferenceReadersRejectBeforeTheNextNativeCall() {
        let input = sharedTree(40)
        for useState in [true, false] {
            let calls = Calls()
            let evaluator = Evaluator(context: EvaluationContext(getState: { _ in input }, resolveRef: { _ in input }, functions: [
                "Later": CustomFunction(params: [], fn: { _ in calls.record(); return .number(1) }),
            ]), schema: LibrarySchema())
            let read = useState ? ASTNode.stateRef("$data") : .runtimeRef("data", refType: .query)
            XCTAssertEqual(evaluator.evaluate(.arr([read, call("Later")])), .null)
            XCTAssertTrue(evaluator.nativeLimitExceeded)
            XCTAssertEqual(calls.value, 0)
        }
    }

    func testExtraScopeIsBudgetedAsOneGraphBeforeExpressionOrRootEvaluation() {
        let part = Value.array(Array(repeating: .number(1), count: 60_000))
        let context = EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null }, extraScope: ["left": part, "right": part])
        let evaluator = Evaluator(context: context, schema: LibrarySchema())
        XCTAssertEqual(evaluator.evaluate(.num(1)), .null)
        XCTAssertTrue(evaluator.nativeLimitExceeded)
        let schema = LibrarySchema(components: ["Text": [ParamDef(name: "text", required: true)]])
        let rootEvaluator = Evaluator(context: context, schema: schema)
        XCTAssertNil(rootEvaluator.evaluateRoot(createParser(schema: schema).parse("root=Text(\"ok\")")))
        XCTAssertTrue(rootEvaluator.nativeLimitExceeded)
    }

    func testScopeKeysAreBoundedBeforeUTF16CopyingAndNormalValuesRemainValid() {
        XCTAssertFalse(nativeScopeExceedsLimits(["x": .number(1), "😀": .string("中文")]))
        XCTAssertTrue(nativeScopeExceedsLimits([String(repeating: "😀", count: OpenUIRuntimeBudget.maximumSourceUTF16 / 2 + 1): .null]))
        let shared = Value.object([ObjectField(key: "n", value: .number(1))])
        let evaluator = Evaluator(context: EvaluationContext(getState: { _ in shared }, resolveRef: { _ in shared }, functions: [
            "Shared": CustomFunction(params: [], fn: { _ in shared }),
        ]), schema: LibrarySchema())
        XCTAssertEqual(evaluator.evaluate(.binOp("==", .stateRef("$a"), .stateRef("$a"))), .boolean(true))
        XCTAssertTrue(evaluator.evaluate(call("Shared")).isSameValue(as: shared))
        XCTAssertFalse(evaluator.nativeLimitExceeded)
    }

    func testAcceptedInputCacheDoesNotRetainNativeGraphs() {
        let checks = NativeInputChecks()
        var array: OpenUIArray? = OpenUIArray([.number(1)])
        weak var released = array
        XCTAssertFalse(checks.exceeds(.array(array!)))
        XCTAssertFalse(checks.exceeds(.array(array!)))
        array = nil
        XCTAssertNil(released)
        XCTAssertTrue(checks.exceeds(sharedTree(40)), "A previous successful identity never permits a different graph")
    }

    func testPublicASTPreflightIncludesDirectAndNestedOpaqueCaptures() {
        let huge = sharedTree(40)
        for node in [ASTNode.runtimeValue(huge),
                     .arr([.num(1), .runtimeValue(huge)]),
                     .comp(name: "Identity", args: [.runtimeValue(huge)], mappedProps: nil, fn: true)] {
            let calls = Calls()
            let evaluator = Evaluator(context: EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null }, functions: [
                "Identity": CustomFunction(params: [ParamDef(name: "value", required: true)], fn: { args in calls.record(); return args["value"] ?? .null }),
            ]), schema: LibrarySchema())
            XCTAssertEqual(evaluator.evaluate(node), .null)
            XCTAssertTrue(evaluator.nativeLimitExceeded)
            XCTAssertEqual(evaluator.errors.count, 1)
            XCTAssertEqual(calls.value, 0)
        }
        let normal = Evaluator(context: EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null }), schema: LibrarySchema())
        XCTAssertEqual(normal.evaluate(.binOp("+", .num(2), .num(3))), .number(5))
        let small = Value.array([.number(1), .string("中文")])
        XCTAssertTrue(normal.evaluate(.runtimeValue(small)).isSameValue(as: small))
        XCTAssertEqual(normal.evaluate(.arr([.runtimeValue(small), .bool(true)])), .array([small, .boolean(true)]))
        XCTAssertFalse(normal.nativeLimitExceeded)
    }
}
