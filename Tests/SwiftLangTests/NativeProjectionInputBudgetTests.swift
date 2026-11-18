import Foundation
import XCTest
@testable import SwiftLang

final class NativeProjectionInputBudgetTests: XCTestCase {
    private func schema() -> LibrarySchema {
        LibrarySchema(components: ["Box": [ParamDef(name: "value", required: true)]], callDefs: builtinCallDefs)
    }
    private func evaluator(_ schema: LibrarySchema) -> Evaluator {
        Evaluator(context: EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null }), schema: schema)
    }
    private func deepAST() -> ASTNode {
        var node = ASTNode.num(1)
        for _ in 0..<300 { node = .unaryOp("-", node) }
        return node
    }

    func testOverriddenParseExpressionIsCheckedBeforeRecursiveNativeEncoding() {
        let schema = schema(), parser = createParser(schema: schema)
        var result = parser.parse("root=Box(\"parsed\")")
        XCTAssertFalse(result.nativeLimitExceeded)
        result.rootExpression = deepAST()
        let evaluator = evaluator(schema)
        XCTAssertNil(evaluator.evaluateRoot(result))
        XCTAssertTrue(evaluator.nativeLimitExceeded)
        XCTAssertEqual(evaluator.errors.count, 1)
        XCTAssertNil(evaluator.evaluateRoot(parser.parse("root=Box(\"later\")")), "Failure is sticky for this evaluator")
    }

    func testOverriddenMaterializedRootIsCheckedBeforeRecursiveConversion() {
        let schema = schema()
        var result = createParser(schema: schema).parse("root=Box(\"parsed\")")
        var value = Materialized.null
        for _ in 0..<300 { value = .array([value]) }
        result.root = ElementNode(typeName: "Box", props: [PropEntry(key: "value", value: value)])
        result.rootExpression = nil
        let evaluator = evaluator(schema)
        XCTAssertNil(evaluator.evaluateRoot(result))
        XCTAssertTrue(evaluator.nativeLimitExceeded)
    }

    func testNormalManualProjectionStillEvaluatesAndFreshEvaluatorRecovers() throws {
        let schema = schema()
        var result = createParser(schema: schema).parse("root=Box(\"parsed\")")
        result.root = nil
        // The pinned core evaluates component expressions after the parser
        // maps positional arguments to properties. An unmapped Comp is not a
        // materialized root expression (upstream returns null / no-root).
        result.rootExpression = .comp(name: "Box", args: [.str("manual")],
            mappedProps: [("value", .str("manual"))], fn: false)
        let evaluator = evaluator(schema)
        let root = try XCTUnwrap(evaluator.evaluateRoot(result))
        XCTAssertEqual(PropValue.string(root, "value"), "manual")
        XCTAssertFalse(evaluator.nativeLimitExceeded)
    }

    func testHandBuiltQueryASTAndMetadataAreRejectedBeforeProviderDispatch() {
        let oversizedName = String(repeating: "x", count: OpenUIRuntimeBudget.maximumSourceUTF16 + 1)
        let unsafe = [
            QueryStatementInfo(statementId: "deep", toolAST: .str("load"), argsAST: deepAST(),
                               defaultsAST: .null, refreshAST: nil, deps: nil, complete: true),
            QueryStatementInfo(statementId: "deps", toolAST: .str("load"), argsAST: .obj([]),
                               defaultsAST: .null, refreshAST: nil, deps: [oversizedName], complete: true),
        ]
        for declaration in unsafe {
            let manager = QueryManager(tools: ["load": { _ in
                XCTFail("Rejected native AST must never reach a provider")
                return .null
            }])
            defer { manager.dispose() }
            let evaluator = evaluator(LibrarySchema())
            manager.evaluateStatements([declaration], evaluator: evaluator)
            XCTAssertTrue(evaluator.nativeLimitExceeded)
            XCTAssertTrue(manager.nativeLimitExceeded)
            XCTAssertTrue(manager.isDisposed)
            XCTAssertNil(manager.queryState(for: declaration.statementId))
        }
    }

    func testQueryBatchAggregateIsCheckedBeforeAnyNodeEncoding() {
        let part = ASTNode.arr(Array(repeating: .num(1), count: 20_000))
        XCTAssertFalse(nativeASTCost(part).exceeds)
        let manager = QueryManager(provider: nil)
        let evaluator = evaluator(LibrarySchema())
        defer { manager.dispose() }
        let statements = ["a", "b"].map {
            QueryStatementInfo(statementId: $0, toolAST: .str("load"), argsAST: .obj([]),
                               defaultsAST: part, refreshAST: nil, deps: nil, complete: true)
        }
        manager.evaluateStatements(statements, evaluator: evaluator)
        XCTAssertTrue(manager.nativeLimitExceeded, "Each AST fits; their actual shared bridge input does not")
        XCTAssertTrue(evaluator.nativeLimitExceeded)
        XCTAssertNil(manager.queryState(for: "a"))
    }
}
