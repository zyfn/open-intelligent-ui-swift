import XCTest
@testable import SwiftLang

final class SourceSnapshotBridgeTests: XCTestCase {
    private func schema(functions: [String: CallDef] = [:]) -> LibrarySchema {
        LibrarySchema(components: [
            "Box": [ParamDef(name: "value", required: true)],
            "Button": [ParamDef(name: "label", required: true), ParamDef(name: "action", required: false)]
        ], callDefs: builtinCallDefs.merging(functions) { _, new in new })
    }

    private func fixture() -> (shared: Value, child: EvaluatedElement, plan: ActionPlan) {
        let plan = ActionPlan(steps: [.reset(targets: ["$x"])])
        let child = EvaluatedElement(typeName: "Button", props: [
            ("label", .string("Go")), ("action", .actionPlan(plan))
        ])
        return (.array([.element(child), .array([.element(child)]),
            .object([.init(key: "child", value: .element(child))])]), child, plan)
    }

    private func firstShared(_ root: EvaluatedElement, file: StaticString = #filePath, line: UInt = #line) throws -> OpenUIArray {
        guard case .array(let outer) = PropValue.value(root, "value"),
              case .array(let shared) = outer.first else {
            XCTFail("Expected Each to retain the shared array", file: file, line: line)
            throw NSError(domain: "SourceSnapshotBridgeTests", code: 1)
        }
        return shared
    }

    private func firstChild(_ values: OpenUIArray, file: StaticString = #filePath, line: UInt = #line) throws -> EvaluatedElement {
        guard case .element(let child) = values.first else {
            XCTFail("Expected a shared native element", file: file, line: line)
            throw NSError(domain: "SourceSnapshotBridgeTests", code: 2)
        }
        return child
    }

    func testSharedContainerRefreshesMetadataWithoutChangingLangIdentityOrOldSnapshots() throws {
        let input = fixture(), librarySchema = schema()
        let evaluator = Evaluator(context: EvaluationContext(getState: { name in
            name == "$shared" ? input.shared : .null
        }, resolveRef: { _ in .null }), schema: librarySchema)
        let parser = createParser(schema: librarySchema)
        let pending = try XCTUnwrap(evaluator.evaluateRoot(parser.parse("root=Box(@Each([1,2],item,$shared")))
        let pendingArray = try firstShared(pending), pendingChild = try firstChild(pendingArray)
        XCTAssertFalse(pendingChild.isSourceComplete)
        XCTAssertFalse(try XCTUnwrap(PropValue.actionPlan(pendingChild, "action")).isSourceComplete)
        XCTAssertTrue(input.child.isSourceComplete, "Projection must not mutate the host value")
        XCTAssertTrue(input.plan.isSourceComplete)
        guard case .array(let siblings) = PropValue.value(pending, "value"),
              case .array(let sameOccurrence) = siblings[1],
              case .array(let nested) = pendingArray[1], case .element(let nestedChild) = nested[0],
              case .object(let record) = pendingArray[2], case .element(let objectChild) = record["child"] else {
            return XCTFail("Expected repeated nested shared references")
        }
        XCTAssertTrue(sameOccurrence === pendingArray, "A projection visits each shared container once")
        XCTAssertTrue(nestedChild === pendingChild)
        XCTAssertTrue(objectChild === pendingChild, "Cached objects must refresh the same shared child too")
        XCTAssertTrue(Value.array(pendingArray).isSameValue(as: input.shared))
        XCTAssertTrue(Value.element(pendingChild).isSameValue(as: .element(input.child)))

        let complete = try XCTUnwrap(evaluator.evaluateRoot(parser.parse("root=Box(@Each([1,2],item,$shared))")))
        let completeArray = try firstShared(complete), completeChild = try firstChild(completeArray)
        XCTAssertTrue(completeChild.isSourceComplete)
        XCTAssertTrue(try XCTUnwrap(PropValue.actionPlan(completeChild, "action")).isSourceComplete)
        XCTAssertFalse(pendingChild.isSourceComplete, "A later evaluation cannot rewrite an older snapshot")
        XCTAssertTrue(Value.array(completeArray).isSameValue(as: .array(pendingArray)))

        let core = SharedCore.shared
        core.sync {
            XCTAssertTrue(core.call("equal", [core.encode(input.shared), core.encode(.array(pendingArray))]).toBool(),
                          "Re-encoding a presentation snapshot must preserve the original JS object")
            guard case .array(let baseline) = core.decode(core.encode(input.shared)) else {
                return XCTFail("Expected the shared baseline")
            }
            XCTAssertTrue((try? firstChild(baseline))?.isSourceComplete == true)
        }
    }

    func testSharedQueryDependenciesRemainInTheirOwnPresentation() throws {
        let input = fixture(), librarySchema = schema()
        let evaluator = Evaluator(context: EvaluationContext(getState: { name in
            name == "$shared" ? input.shared : .null
        }, resolveRef: { _ in .array([.number(1)]) }), schema: librarySchema)
        let parser = createParser(schema: librarySchema)
        let first = try XCTUnwrap(evaluator.evaluateRoot(parser.parse("root=Box(@Each(q,item,$shared))\nq=Query(\"load\",{},[])")))
        let firstChild = try self.firstChild(firstShared(first))
        XCTAssertEqual(firstChild.sourceReadiness.queryDependencies, ["q"])
        let second = try XCTUnwrap(evaluator.evaluateRoot(parser.parse("root=Box(@Each([1],item,$shared))")))
        let secondChild = try self.firstChild(firstShared(second))
        XCTAssertTrue(secondChild.sourceReadiness.queryDependencies.isEmpty)
        XCTAssertEqual(firstChild.sourceReadiness.queryDependencies, ["q"], "Keep the old dependency snapshot")
        XCTAssertTrue(Value.element(firstChild).isSameValue(as: .element(secondChild)))
        XCTAssertTrue(input.child.sourceReadiness.queryDependencies.isEmpty)
    }

    func testPlainDataKeepsTheExistingNativeIdentityFastPath() {
        let record = Value.object([.init(key: "id", value: .number(1)), .init(key: "title", value: .string("data"))])
        let shared = Value.array([record, record])
        let evaluator = Evaluator(context: EvaluationContext(getState: { _ in shared }, resolveRef: { _ in .null }), schema: schema())
        for _ in 0..<3 {
            guard case .array(let actual) = evaluator.evaluate(.stateRef("$data")),
                  case .array(let original) = shared else { return XCTFail("Expected ordinary data") }
            XCTAssertTrue(actual === original)
            XCTAssertFalse(actual.containsSourceMetadata)
        }
        XCTAssertFalse(shared.isSameValue(as: .array([record, record])), "Separate ordinary containers remain distinct")
    }

    func testNativeFunctionReadsItsArgumentsInTheCurrentSourceSnapshot() throws {
        let input = fixture(), params = [ParamDef(name: "value", required: true)]
        let librarySchema = schema(functions: ["Inspect": CallDef(kind: .function, params: params)])
        let evaluator = Evaluator(context: EvaluationContext(getState: { name in
            name == "$shared" ? input.shared : .array([.number(1)])
        }, resolveRef: { _ in .null }, functions: ["Inspect": CustomFunction(params: params, fn: { values in
            guard case .array(let outer) = values["value"], case .array(let shared) = outer.first,
                  case .element(let child) = shared.first else { return .undefined }
            return .boolean(child.isSourceComplete)
        })]), schema: librarySchema)
        let parsed = createParser(schema: librarySchema).parse("root=Box(@Inspect(@Each($items,item,$shared)))\n$items=[1")
        XCTAssertTrue(parsed.meta.errors.isEmpty)
        XCTAssertEqual(PropValue.value(try XCTUnwrap(evaluator.evaluateRoot(parsed)), "value"), .boolean(false))
        XCTAssertTrue(input.child.isSourceComplete)
    }

    @MainActor func testAnIncompleteNativeSharedControlCannotInteract() throws {
        let input = fixture()
        let librarySchema = schema(functions: ["Shared": CallDef(kind: .function, params: [])])
        let state = OpenUIState(schema: librarySchema, functions: [
            "Shared": CustomFunction(params: [], fn: { _ in input.shared })
        ])
        state.setSource("root=Box(@Each([1],item,@Shared()", streaming: true)
        let child = try firstChild(firstShared(XCTUnwrap(state.root)))
        let context = OpenUIComponentContext(element: child, registry: [:], state: state)
        XCTAssertFalse(child.isSourceComplete)
        XCTAssertFalse(context.canInteract, "Generic hosts cannot rely on a built-in container to block a stale complete child")
        XCTAssertTrue(input.child.isSourceComplete)
    }
}
