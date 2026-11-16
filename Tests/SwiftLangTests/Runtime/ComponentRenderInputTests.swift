import Combine
import XCTest
@testable import SwiftLang

final class ComponentRenderInputTests: XCTestCase {
    private func element(_ value: Value, partial: Bool = true, complete: Bool = true,
                         readiness: NativeSourceReadiness? = nil, id: String? = "row") -> EvaluatedElement {
        EvaluatedElement(typeName: "Probe", props: [("value", value)], statementId: id,
            partial: partial, isSourceComplete: complete, sourceReadiness: readiness)
    }

    func testRenderComparisonPreservesPrimitiveAndPresentationDistinctions() {
        XCTAssertTrue(nativePresentationInputsEqual(element(.string("same")), element(.string("same"))))
        XCTAssertFalse(nativePresentationInputsEqual(element(.string("é")), element(.string("e\u{301}"))))
        XCTAssertTrue(nativePresentationInputsEqual(element(.number(.nan)), element(.number(.nan))))
        XCTAssertFalse(nativePresentationInputsEqual(element(.number(0)), element(.number(-0.0))))
        XCTAssertFalse(nativePresentationInputsEqual(element(.null), element(.undefined)))
        XCTAssertFalse(nativePresentationInputsEqual(element(.string("same")), element(.string("same"), partial: false)))
        XCTAssertFalse(nativePresentationInputsEqual(element(.string("same")), element(.string("same"), complete: false)))
        XCTAssertFalse(nativePresentationInputsEqual(element(.string("same"), id: "é"),
                                                     element(.string("same"), id: "e\u{301}")))
        let open = NativeSourceReadiness(complete: true, closed: false,
            children: ["value": .init(complete: false, closed: false)])
        let closed = NativeSourceReadiness(complete: true, closed: true,
            children: ["value": .init(complete: true, closed: true)])
        XCTAssertFalse(nativePresentationInputsEqual(element(.string("same"), readiness: open),
                                                     element(.string("same"), readiness: closed)))
    }

    func testChangedReferencePropsAlwaysReachTheCustomBuilder() {
        let array = Value.array([.string("same")])
        XCTAssertTrue(nativePresentationInputsEqual(element(array), element(array)))
        XCTAssertFalse(nativePresentationInputsEqual(element(array), element(.array([.string("same")]))))
        let object = Value.object([.init(key: "value", value: .string("same"))])
        XCTAssertFalse(nativePresentationInputsEqual(element(object),
            element(.object([.init(key: "value", value: .string("same"))]))))
        let before = ActionPlan(steps: [.continueConversation(messageAST: .str("go"), contextAST: nil)], isSourceComplete: false)
        let after = ActionPlan(steps: [.continueConversation(messageAST: .str("go"), contextAST: nil)], isSourceComplete: true)
        XCTAssertFalse(nativePresentationInputsEqual(element(.actionPlan(before)), element(.actionPlan(after))))
        XCTAssertFalse(nativePresentationInputsEqual(element(.binding("$field")), element(.binding("$field"))))
    }

    @MainActor func testTextChunksDoNotBroadcastAuxiliaryStateButLateDefaultsAndEditsDo() {
        let schema = LibrarySchema(components: ["Probe": [ParamDef(name: "value", required: true)]],
                                   callDefs: builtinCallDefs)
        let state = OpenUIState(schema: schema)
        defer { state.reset() }
        state.push("root=Probe(\"")
        var changes = 0
        let subscription = state.componentUpdates.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        for chunk in ["SHANGHAI", " → ", "SUZHOU", "\")\n"] { state.push(chunk) }
        XCTAssertEqual(changes, 0)
        state.push("$late=\"first\"\n")
        XCTAssertEqual(changes, 1, "A State default arriving in the stream must notify field readers")
        state.setState("$late", value: .string("edited"))
        XCTAssertEqual(changes, 2)
        state.complete()
        XCTAssertEqual(changes, 3)
        state.reset()
        XCTAssertEqual(changes, 4)
        state.push("root=Probe(\"new\")\n$new=1\n")
        XCTAssertEqual(changes, 5, "The replacement Store must have its own live subscription")
    }

    func testAuxiliaryQueryComparisonKeepsMissingDataAndErrorChangesObservable() {
        XCTAssertTrue(nativeQueryStatesEqual(["q": .init(status: .idle, data: .string("default"))],
                                            ["q": .init(status: .idle, data: .string("default"))]))
        XCTAssertFalse(nativeQueryStatesEqual(["q": .init(status: .idle)],
                                             ["q": .init(status: .idle, data: .undefined)]))
        XCTAssertFalse(nativeQueryStatesEqual(["q": .init(status: .idle, data: .undefined)],
                                             ["q": .init(status: .idle, data: .null)]))
        let first = Value.array([.number(1)]), second = Value.array([.number(1)])
        XCTAssertFalse(nativeQueryStatesEqual(["q": .init(status: .success, data: first)],
                                             ["q": .init(status: .success, data: second)]))
        let before = OpenUIError(source: .query, code: .toolError, message: "same", hint: "first")
        let after = OpenUIError(source: .query, code: .toolError, message: "same", hint: "second")
        XCTAssertFalse(nativeQueryStatesEqual(["q": .init(status: .error, error: before)],
                                             ["q": .init(status: .error, error: after)]))
        XCTAssertTrue(nativeMutationStatesEqual(["m": .init(status: .idle)], ["m": .init(status: .idle)]))
        XCTAssertFalse(nativeMutationStatesEqual(["m": .init(status: .idle)], ["m": .init(status: .loading)]))
    }

    func testAnonymousScalarCandidatesAreNarrowedWithoutDiscardingAmbiguity() {
        var index = NativeLiveElementIndex()
        for number in 0..<200 { index.insert(element(.string(OpenUIString("row \(number)")), id: nil)) }
        var candidates = 0
        for number in 0..<200 {
            candidates += index.candidates(for: element(.string(OpenUIString("row \(number)")), id: nil)).count
        }
        XCTAssertEqual(candidates, 200, "Each old scalar leaf searches one candidate, not all 200 anonymous leaves")
        index.insert(element(.string("row 0"), complete: false, id: nil))
        XCTAssertEqual(index.candidates(for: element(.string("row 0"), id: nil)).count, 2,
                       "Readiness ambiguity remains for the existing live-element check to resolve")
    }

    func testQueryNotificationKeepsNewReadinessEvenForTheSameLangReference() throws {
        let shared = Value.array([.element(EvaluatedElement(typeName: "Probe", props: [("value", .string("ready"))]))])
        let schema = LibrarySchema(components: [
            "Box": [ParamDef(name: "value", required: true)],
            "Probe": [ParamDef(name: "value", required: true)]
        ], callDefs: builtinCallDefs)
        let evaluator = Evaluator(context: EvaluationContext(getState: { _ in shared }, resolveRef: { _ in .null }), schema: schema)
        let parser = createParser(schema: schema)
        func sharedValue(_ root: EvaluatedElement) throws -> Value {
            let value = try XCTUnwrap(PropValue.value(root, "value"))
            guard case .array(let outer) = value else {
                XCTFail("Expected Each output")
                return .null
            }
            return try XCTUnwrap(outer.first)
        }
        let pending = try sharedValue(XCTUnwrap(evaluator.evaluateRoot(parser.parse("root=Box(@Each([1],item,$shared"))))
        let complete = try sharedValue(XCTUnwrap(evaluator.evaluateRoot(parser.parse("root=Box(@Each([1],item,$shared))"))))
        XCTAssertTrue(pending.isSameValue(as: complete))
        XCTAssertFalse(nativeQueryStatesEqual(["q": .init(status: .success, data: pending)],
                                             ["q": .init(status: .success, data: complete)]))
    }

    func testScalarIndexMatchesStructuralNumberAndUTF16Semantics() {
        var index = NativeLiveElementIndex()
        let values: [Value] = [.number(0), .number(-0.0), .number(.nan), .number(-Double.nan),
                               .string("é"), .string("e\u{301}"), .null, .undefined]
        for value in values {
            index.insert(element(value, id: nil))
        }
        XCTAssertEqual(index.candidates(for: element(.number(0), id: nil)).count, 2)
        XCTAssertEqual(index.candidates(for: element(.number(.nan), id: nil)).count, 2)
        XCTAssertEqual(index.candidates(for: element(.string("é"), id: nil)).count, 1)
        XCTAssertEqual(index.candidates(for: element(.string("e\u{301}"), id: nil)).count, 1)
        XCTAssertEqual(index.candidates(for: element(.null), id: nil)).count, 1)
        XCTAssertEqual(index.candidates(for: element(.undefined), id: nil)).count, 1)
    }
}
