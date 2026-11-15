import Foundation
import XCTest
@testable import SwiftLang

final class Lang111Tests: XCTestCase {
    private let schema = LibrarySchema(components: ["Box": [ParamDef(name: "value", required: true)]],
                                       callDefs: builtinCallDefs, rootComponent: "Box")

    func testExpressionDefaultsAreComputedOnceAndListMathUsesOfficialSemantics() throws {
        let result = createParser(schema: schema).parse("""
            $n = 2
            $total = $n * 3
            root = Box([$n, $total, @Round([1.4, 2.6, -1.5]), @Abs([-2, 0, 3]), @Floor([1.9, -1.1]), @Ceil([1.1, -1.9])])
            """)
        XCTAssertTrue(result.meta.errors.isEmpty)
        let store = createStore()
        store.initialize(defaults: result.stateDeclarations, persisted: ["$n": .number(10)])
        let evaluator = Evaluator(context: EvaluationContext(getState: { store.get($0) ?? .null },
            resolveRef: { _ in .null }), schema: schema)
        XCTAssertEqual(try XCTUnwrap(evaluator.evaluateRoot(result)).props.first?.1, .array([
            .number(10), .number(6), .array([.number(1), .number(3), .number(-1)]),
            .array([.number(2), .number(0), .number(3)]),
            .array([.number(1), .number(-2)]), .array([.number(2), .number(-1)])
        ]))
        store.set("$n", value: .number(20), pristine: false)
        XCTAssertEqual(store.get("$total"), .number(6), "A computed default is not a reactive formula")
    }

    func testSourceSplittingKeepsMultilineTernariesCommentsAndUTF16Boundaries() {
        let conditional = "root = $show\n ? Box(\"🧭\")\n : Box(\"返回\")"
        let label = "label = \"值😀\" // trailing comment"
        let source = "// 💡 leading comment\n" + conditional + "\n" + label + "\n"
        XCTAssertEqual(splitStatementTexts(source), [conditional, label])
        let merged = mergeStatements("$show = true\n" + conditional, "$show = false")
        XCTAssertTrue(merged.contains(conditional), "Merging must keep the whole conditional statement")
        XCTAssertEqual(splitStatementTexts(merged), ["$show = false", conditional])
    }

    private actor ChainProvider: ToolProvider {
        struct Call: Sendable {
            let name: OpenUIString
            let arguments: OpenUIObject
        }
        private(set) var calls: [Call] = []
        private var replacementIDs: Value?
        func replaceIDs(_ value: Value?) { replacementIDs = value }
        func callTool(name: OpenUIString, arguments: OpenUIObject) async throws -> Value {
            calls.append(Call(name: name, arguments: arguments))
            if name == "ids" {
                try await Task.sleep(nanoseconds: 30_000_000)
                return replacementIDs ?? .array([arguments["region"] ?? .null])
            }
            return .object(arguments)
        }
    }

    func testLangOnlyManagerWaitsForDependenciesAndReadsLiveState() async throws {
        let result = createParser(schema: schema).parse("""
            root = Box(details)
            $region = "west"
            filters = {region: $region}
            first = Query("ids", filters, [])
            alias = first
            args = {ids: alias}
            details = Query("details", args, [])
            """)
        XCTAssertTrue(result.meta.errors.isEmpty)
        XCTAssertEqual(result.queryStatements.first(where: { $0.statementId == "first" })?.deps, ["$region"])
        XCTAssertEqual(result.queryStatements.first(where: { $0.statementId == "details" })?.waitFor, ["first"])
        let store = createStore()
        store.initialize(defaults: result.stateDeclarations, persisted: [:])
        let provider = ChainProvider()
        let manager = QueryManager(provider: provider)
        defer { manager.dispose() }
        let evaluator = Evaluator(context: EvaluationContext(getState: { store.get($0) ?? .null },
            resolveRef: { [weak manager] in manager?.queryState(for: $0)?.data ?? .null }), schema: schema)
        manager.evaluateStatements(result.queryStatements, evaluator: evaluator)
        XCTAssertEqual(manager.queryState(for: "details")?.status, .loading)
        await eventually { manager.queryState(for: "details")?.status == .success }
        var calls = await provider.calls
        XCTAssertEqual(calls.map(\.name), ["ids", "details"])
        XCTAssertEqual(calls.last?.arguments["ids"], .array([.string("west")]))
        manager.runQuery(statementId: "details", tool: "details",
                         args: .object([.init(key: "ids", value: .array([.string("west")]))]), defaults: .array([]))
        await eventually { manager.queryState(for: "details")?.status == .success }
        calls = await provider.calls
        XCTAssertEqual(calls.map(\.name), ["ids", "details", "details"])
        await provider.replaceIDs(.array([.string("refresh")]))
        manager.invalidateQuery(statementId: "first")
        await eventually {
            manager.queryState(for: "details")?.data == .object([.init(key: "ids", value: .array([.string("refresh")]))])
        }
        calls = await provider.calls
        XCTAssertEqual(calls.map(\.name), ["ids", "details", "details", "ids", "details"],
                       "Explicitly retrying a reader must retain its upstream dependency")
        await provider.replaceIDs(nil)
        store.set("$region", value: .string("east"), pristine: false)
        manager.evaluateStatements(result.queryStatements, evaluator: evaluator)
        await eventually {
            manager.queryState(for: "details")?.data == .object([.init(key: "ids", value: .array([.string("east")]))])
        }
        calls = await provider.calls
        XCTAssertEqual(calls.map(\.name), ["ids", "details", "details", "ids", "details", "ids", "details"])
        XCTAssertEqual(calls.last?.arguments["ids"], .array([.string("east")]))
    }

    func testAdHocQueryKeepsActiveStatementDependencyGraph() async {
        let result = createParser(schema: schema).parse("""
            root = Box(details)
            first = Query("ids", {region: "west"}, [])
            details = Query("details", {ids: first}, [])
            """)
        XCTAssertTrue(result.meta.errors.isEmpty)
        let store = createStore()
        let provider = ChainProvider()
        let manager = QueryManager(provider: provider)
        defer { manager.dispose() }
        let evaluator = Evaluator(context: EvaluationContext(getState: { store.get($0) ?? .null },
            resolveRef: { [weak manager] in manager?.queryState(for: $0)?.data ?? .null }), schema: schema)
        manager.evaluateStatements(result.queryStatements, evaluator: evaluator)
        await eventually { manager.queryState(for: "details")?.status == .success }
        manager.runQuery(statementId: "manual", tool: "manual", args: .object([]), defaults: .null)
        await eventually { manager.queryState(for: "manual")?.status == .success }
        XCTAssertEqual(manager.queryState(for: "first")?.data, .array([.string("west")]))
        XCTAssertEqual(manager.queryState(for: "details")?.data,
                       .object([.init(key: "ids", value: .array([.string("west")]))]))
        await provider.replaceIDs(.array([.string("refresh")]))
        manager.invalidateQuery(statementId: "first")
        await eventually {
            manager.queryState(for: "details")?.data == .object([.init(key: "ids", value: .array([.string("refresh")]))])
        }
        let calls = await provider.calls
        XCTAssertEqual(calls.map(\.name), ["ids", "details", "manual", "ids", "details"])
    }

    private func eventually(_ predicate: @escaping () -> Bool) async {
        for _ in 0..<300 {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("Lang 1.1 query dependency did not settle")
    }
}
