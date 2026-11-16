import XCTest
@testable import SwiftLang

final class NativeValueBudgetTests: XCTestCase {
    private let maximumUTF16 = OpenUIRuntimeBudget.maximumSourceUTF16

    private func nested(_ value: Value, levels: Int) -> Value {
        var result = value
        for _ in 0..<levels { result = .array([result]) }
        return result
    }

    private func sharedTree(levels: Int) -> Value {
        var result = Value.number(1)
        for _ in 0..<levels { result = .array([result, result]) }
        return result
    }

    func testNormalToolDataAndNonJSONScalarsAreAcceptedWithoutProjection() {
        let value = Value.object([
            ObjectField(key: "items", value: .array([
                .object([ObjectField(key: "name", value: .string("中文 👩🏽‍💻")),
                         ObjectField(key: "count", value: .number(12))]),
                .null, .undefined, .boolean(true), .number(.nan), .number(.infinity),
            ])),
            ObjectField(key: OpenUIString(codeUnits: [0xD800]), value: .string(OpenUIString(codeUnits: [0xDC00]))),
        ])
        XCTAssertFalse(nativeValueExceedsLimits(value))
    }

    func testNativeStateDictionaryPreservesRawUTF16KeysAndAggregatesSharedValues() {
        XCTAssertFalse(nativeStateExceedsLimits([OpenUIString(codeUnits: [0xD800]): .string("中文"), "normal": .number(1)]))
        let shared = Value.array(Array(repeating: .number(1), count: 60_000))
        XCTAssertFalse(nativeStateExceedsLimits(["first": shared]))
        XCTAssertTrue(nativeStateExceedsLimits(["first": shared, "second": shared]))
    }

    func testWideDataStopsAtTheSameNodeLimitAsTheJSOutputGuard() {
        XCTAssertFalse(nativeValueExceedsLimits(.array(Array(repeating: .number(0), count: 99_999))))
        XCTAssertTrue(nativeValueExceedsLimits(.array(Array(repeating: .number(0), count: 100_000))))
        let fields = (0..<100_000).map { ObjectField(key: "k\($0)", value: .number(Double($0))) }
        XCTAssertFalse(nativeValueExceedsLimits(.object(Array(fields.prefix(20_000)))))
        XCTAssertTrue(nativeValueExceedsLimits(.object(fields)))
    }

    func testDepthBoundaryIsCheckedBeforeRecursiveEncoding() {
        XCTAssertFalse(nativeValueExceedsLimits(nested(.number(1), levels: 256)))
        XCTAssertTrue(nativeValueExceedsLimits(nested(.number(1), levels: 257)))
    }

    func testSharedDAGCountsOccurrencesWithoutExpandingTheGraph() {
        // Only 15/16/40 reference containers are allocated by these inputs.
        // Expanded costs are 65,535 / 131,071 / over a trillion occurrences.
        XCTAssertFalse(nativeValueExceedsLimits(sharedTree(levels: 15)))
        XCTAssertTrue(nativeValueExceedsLimits(sharedTree(levels: 16)))
        XCTAssertTrue(nativeValueExceedsLimits(sharedTree(levels: 40)))
    }

    func testCachedSubtreeDepthIsRecheckedAtEveryOccurrence() {
        let subtree = nested(.number(1), levels: 16)
        XCTAssertFalse(nativeValueExceedsLimits(.array([subtree, nested(subtree, levels: 239)])))
        XCTAssertTrue(nativeValueExceedsLimits(.array([subtree, nested(subtree, levels: 240)])))
    }

    func testRejectedSpineSharesOneInspectionAllowanceAcrossSiblings() {
        let storage = Array(repeating: Value.number(1), count: 80_000)
        var value = Value.null
        for _ in 0..<40 {
            // Separate reference identities share Swift's immutable array
            // storage. Identity memoization alone cannot skip these siblings.
            value = .array([.array(OpenUIArray(storage)), value])
        }
        XCTAssertTrue(nativeValueExceedsLimits(value))
    }

    func testSyntheticMetadataAndActionLeavesShareTheInspectionAllowance() {
        let slots = NativeSourceReadiness(complete: true, closed: true,
            valueIndices: Array(repeating: 0, count: 99_980))
        var metadata = NativeSourceReadiness(complete: true, closed: true)
        for _ in 0..<40 { metadata = .init(complete: true, closed: true, children: ["wide": slots, "next": metadata]) }
        XCTAssertTrue(nativeValueExceedsLimits(.element(EvaluatedElement(typeName: "Box", sourceReadiness: metadata))))

        let targets = Array(repeating: "", count: 99_980)
        var plan = Value.actionPlan(ActionPlan())
        for _ in 0..<40 {
            plan = .actionPlan(ActionPlan(steps: [.reset(targets: targets), .set(target: "$next", valueAST: .runtimeValue(plan))]))
        }
        XCTAssertTrue(nativeValueExceedsLimits(plan))
    }

    func testUTF16CountsValuesKeysAndEverySharedOccurrence() {
        let exact = OpenUIString(codeUnits: Array(repeating: 0xD800, count: maximumUTF16))
        XCTAssertFalse(nativeValueExceedsLimits(.string(exact)))
        XCTAssertTrue(nativeValueExceedsLimits(.string(OpenUIString(codeUnits: exact.codeUnits + [0xDC00]))))
        XCTAssertFalse(nativeValueExceedsLimits(.object([ObjectField(key: exact, value: .null)])))
        XCTAssertTrue(nativeValueExceedsLimits(.object([ObjectField(key: exact, value: .string("x"))])))

        // An emoji takes two UTF-16 code units. String.count would undercount.
        let half = Value.array([.string(String(repeating: "😀", count: maximumUTF16 / 4))])
        XCTAssertFalse(nativeValueExceedsLimits(.array([half, half])))
        XCTAssertTrue(nativeValueExceedsLimits(.array([half, half, .string("x")])))
    }

    func testElementOccurrencesIncludeSharedReferencesAndPlainMarkers() {
        let element = Value.element(EvaluatedElement(typeName: "Text", props: [("text", .string("ok"))]))
        XCTAssertFalse(nativeValueExceedsLimits(.array(Array(repeating: element, count: 4_096))))
        XCTAssertTrue(nativeValueExceedsLimits(.array(Array(repeating: element, count: 4_097))))
        let marker = Value.object([ObjectField(key: "type", value: .string("element"))])
        XCTAssertFalse(nativeValueExceedsLimits(.array(Array(repeating: marker, count: 4_096))))
        XCTAssertTrue(nativeValueExceedsLimits(.array(Array(repeating: marker, count: 4_097))))
    }

    func testBindingsActionsAndCapturedValuesRemainBounded() {
        let normal = Value.array([
            .binding("$value"), .reactiveBinding(target: "$count", expression: .binOp("+", .stateRef("$value"), .num(1))),
            .actionPlan(ActionPlan(steps: [
                .set(target: "$data", valueAST: .runtimeValue(.object([ObjectField(key: "x", value: .number(1))]))),
                .reset(targets: ["$count"]), .run(statementId: "load", refType: .query),
                .continueConversation(messageAST: .str("next"), contextAST: .obj([("a", .bool(true))])),
                .openUrl(urlAST: .str("https://example.com")),
                .custom(name: "submit", args: [("value", .arr([.num(1), .null]))]),
            ])),
        ])
        XCTAssertFalse(nativeValueExceedsLimits(normal))
        let tooMany = sharedTree(levels: 16)
        XCTAssertTrue(nativeValueExceedsLimits(.reactiveBinding(target: "$data", expression: .runtimeValue(tooMany))))
        for step in [ActionStep.set(target: "$data", valueAST: .runtimeValue(tooMany)),
                     .continueConversation(messageAST: .str("next"), contextAST: .runtimeValue(tooMany)),
                     .openUrl(urlAST: .runtimeValue(tooMany)),
                     .custom(name: "submit", args: [("value", .runtimeValue(tooMany))])] {
            XCTAssertTrue(nativeValueExceedsLimits(.actionPlan(ActionPlan(steps: [step]))))
        }
    }

    func testASTCostIncludesContainersAndMappedProperties() {
        let normal = ASTNode.comp(name: "Box", args: [.ph("pending"), .runtimeRef("load", refType: .query)],
            mappedProps: [("value", .ternary(.bool(true),
                .member(.ref("item"), "title"), .index(.arr([.num(1)]), .num(0)))),
                ("change", .assign("$value", .unaryOp("-", .stateRef("$value"))))], fn: true)
        XCTAssertFalse(nativeValueExceedsLimits(.reactiveBinding(target: "$value", expression: normal)))
        var deep = ASTNode.num(1)
        for _ in 0..<257 { deep = .unaryOp("-", deep) }
        XCTAssertTrue(nativeValueExceedsLimits(.reactiveBinding(target: "$value", expression: deep)))
        let large = ASTNode.arr(Array(repeating: .num(1), count: 40_000))
        XCTAssertTrue(nativeValueExceedsLimits(.actionPlan(ActionPlan(steps: [.set(target: "$value", valueAST: large)]))))
        let mapped = ASTNode.comp(name: "Box", args: [], mappedProps: [("value", .runtimeValue(sharedTree(levels: 16)))], fn: false)
        XCTAssertTrue(nativeValueExceedsLimits(.reactiveBinding(target: "$value", expression: mapped)))
    }

    func testReadinessMetadataIsCheckedBeforeItsSeparateBridgeAllocation() {
        let slots = NativeSourceReadiness(complete: true, closed: true, valueIndices: Array(repeating: 0, count: 100_000))
        XCTAssertTrue(nativeValueExceedsLimits(.element(EvaluatedElement(typeName: "Box", sourceReadiness: slots))))
        let hint = NativeComponentPlaceholder(typeName: "Box", properties: ["value": sharedTree(levels: 16)])
        let metadata = NativeSourceReadiness(complete: false, closed: false, placeholder: hint)
        XCTAssertTrue(nativeValueExceedsLimits(.element(EvaluatedElement(typeName: "Box", sourceReadiness: metadata))))
        var deep = NativeSourceReadiness(complete: true, closed: true)
        for _ in 0..<130 { deep = .init(complete: true, closed: true, children: ["child": deep]) }
        XCTAssertTrue(nativeValueExceedsLimits(.element(EvaluatedElement(typeName: "Box", sourceReadiness: deep))))
    }
}
