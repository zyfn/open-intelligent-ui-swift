import JavaScriptCore
import XCTest
@testable import SwiftLang

final class ProjectionBridgeTests: XCTestCase {
    func testCachedOrdinaryContainersDoNotReadSourceMetadata() throws {
        let core = SharedCore.shared
        try core.sync {
            let fixture = try XCTUnwrap(core.context.evaluateScript(#"""
                (() => {
                    let reads = 0;
                    const source = { ready: new WeakMap(), presentation: new WeakMap(),
                        descendants: { get() { reads++; return undefined; } }, scopes: new Map() };
                    return { source, reads: () => reads,
                        values: [{ type: "element", props: { value: "ordinary" } }, [1, { value: 2 }]] };
                })()
                """#))
            let source = try XCTUnwrap(fixture.forProperty("source"))
            for js in core.items(fixture.forProperty("values")) {
                let first = core.decode(js, interpret: false, sourceSnapshot: source)
                XCTAssertFalse(first.containsSourceMetadata)
                let reads = fixture.invokeMethod("reads", withArguments: []).toInt32()
                XCTAssertGreaterThan(reads, 0)
                for _ in 0..<8 {
                    let next = core.decode(js, interpret: false, sourceSnapshot: source)
                    XCTAssertTrue(next.isSameSnapshot(as: first))
                }
                XCTAssertEqual(fixture.invokeMethod("reads", withArguments: []).toInt32(), reads,
                    "Immutable ordinary data must not visit source scopes or recursively reproject its children")
            }
        }
    }

    func testPreviouslyDecodedElementKeepsItsKindWhenReadAsOrdinaryData() {
        let core = SharedCore.shared
        let original = EvaluatedElement(typeName: "Box", props: [("value", .number(1))],
            isSourceComplete: false, sourceReadiness: .init(complete: false, closed: false))
        core.sync {
            let js = core.encode(.element(original))
            guard case .element(let decoded) = core.decode(js, interpret: false) else {
                return XCTFail("A known native reference keeps its previously established kind")
            }
            XCTAssertTrue(decoded === original)
            XCTAssertFalse(decoded.isSourceComplete)
            XCTAssertEqual(decoded.sourceReadiness, original.sourceReadiness)
        }
    }

    func testEntriesPreserveOwnKeyOrderExactStringsAndSharedValues() throws {
        let core = SharedCore.shared
        let object = try core.sync {
            try XCTUnwrap(core.context.evaluateScript(#"""
                (() => {
                    const shared = { text: "shared" };
                    const value = Object.create({ inherited: "not an own key" });
                    value.z = shared;
                    value["10"] = 10;
                    value["2"] = 2;
                    value["é"] = "precomposed";
                    value["e\u0301"] = "decomposed";
                    value["\ud800"] = "\udc00";
                    value.missing = undefined;
                    value.nothing = null;
                    value.again = shared;
                    Object.defineProperty(value, "hidden", { value: true });
                    value[Symbol("symbol")] = true;
                    return value;
                })()
                """#))
        }
        let entries = core.sync { core.entries(object) }
        let expectedKeys: [OpenUIString] = ["2", "10", "z", "é", "e\u{301}",
            OpenUIString(codeUnits: [0xD800]), "missing", "nothing", "again"]
        XCTAssertEqual(entries.map { $0.0 }, expectedKeys)
        guard entries.count == expectedKeys.count else { return }
        // These wrappers have escaped the bridge operation that produced them.
        // Their values must survive before a later operation consumes them.
        XCTAssertEqual(core.sync { core.decode(entries[0].1) }, .number(2))
        XCTAssertEqual(core.sync { core.decode(entries[1].1) }, .number(10))
        XCTAssertEqual(core.sync { core.decode(entries[3].1) }, .string("precomposed"))
        XCTAssertEqual(core.sync { core.decode(entries[4].1) }, .string("decomposed"))
        XCTAssertEqual(core.sync { core.string(entries[5].1) }.codeUnits, [0xDC00])
        XCTAssertEqual(core.sync { core.decode(entries[6].1) }, .undefined)
        XCTAssertEqual(core.sync { core.decode(entries[7].1) }, .null)
        let first = core.sync { core.decode(entries[2].1) }
        let again = core.sync { core.decode(entries[8].1) }
        XCTAssertTrue(first.isSameValue(as: again), "Enumerating entries must not copy shared property values")
    }

    func testReturnedSnapshotsStoreValuesAndActionCapturesSurviveLaterBridgeOperations() throws {
        let core = SharedCore.shared
        let schema = LibrarySchema(components: ["Box": [ParamDef(name: "value", required: true)]],
                                   callDefs: builtinCallDefs)
        let parser = createStreamingParser(schema: schema)
        let heldParse = parser.push("root=Box(\"held")
        let child = EvaluatedElement(typeName: "Box", props: [("value", .string("native child"))],
            partial: false, isSourceComplete: false, sourceReadiness: .init(complete: false, closed: false))
        let shared = Value.object([.init(key: "child", value: .element(child)),
                                   .init(key: "text", value: .string("上海"))])
        let store = createStore()
        store.set("$saved", value: shared, pristine: false)
        let heldJS = core.sync { core.encode(shared) }
        let evaluator = Evaluator(context: EvaluationContext(getState: { store.get($0) ?? .null },
            resolveRef: { _ in .null }), schema: schema)
        let actionRoot = try XCTUnwrap(evaluator.evaluateRoot(
            parser.set("root=Box(@ToAssistant(\"send\",$saved))", complete: true)))
        guard case .actionPlan(let plan) = PropValue.value(actionRoot, "value") else {
            return XCTFail("Expected a parsed action plan with its original captured value")
        }
        let step = try XCTUnwrap(plan.steps.first)
        guard case .continueConversation(let message, let context) = step else {
            return XCTFail("Expected the original continue-conversation step")
        }
        let captured = try XCTUnwrap(context)

        // Exercise successive outer bridge operations without yielding to an
        // App run loop. Only the selected older values remain held by this test.
        for index in 0..<64 {
            let current = parser.set("root=Box(\"later \(index)\")", complete: true)
            let root = try XCTUnwrap(evaluator.evaluateRoot(current))
            XCTAssertEqual(PropValue.string(root, "value"), "later \(index)")
            store.set("$noise", value: .number(Double(index)), pristine: false)
            _ = core.sync { core.entries(core.encode(.object([.init(key: "temporary", value: .number(Double(index)))]))) }
        }

        let retainedRoot = try XCTUnwrap(evaluator.evaluateRoot(heldParse))
        XCTAssertEqual(PropValue.string(retainedRoot, "value"), "held")
        XCTAssertFalse(retainedRoot.isSourceComplete)
        XCTAssertFalse(retainedRoot.sourceReadiness.closed)
        XCTAssertTrue(heldParse.meta.incomplete)
        XCTAssertTrue(try XCTUnwrap(store.get("$saved")).isSameValue(as: shared))
        XCTAssertTrue(core.sync { core.decode(heldJS) }.isSameValue(as: shared))
        XCTAssertEqual(evaluator.evaluate(message), .string("send"))
        let retainedCapture = evaluator.evaluate(captured)
        XCTAssertTrue(retainedCapture.isSameValue(as: shared))
        guard case .object(let fields) = retainedCapture,
              case .element(let retainedChild) = fields["child"] else {
            return XCTFail("The action capture must retain its nested native element")
        }
        XCTAssertTrue(retainedChild === child)
        XCTAssertFalse(retainedChild.isSourceComplete)
        XCTAssertEqual(retainedChild.sourceReadiness, .init(complete: false, closed: false))
        XCTAssertFalse(evaluator.nativeLimitExceeded)
    }
}
