import XCTest
@testable import SwiftLang

final class SchemaAuthoringTests: XCTestCase {
    private func wire(_ schema: LibrarySchema) -> JSONValue { SharedCore.shared.sync { SharedCore.shared.schemaJSON(schema) } }
    private func box(_ params: [ParamDef]) -> DefinedComponent { defineComponent(name: "Box", description: "", params: params) }

    func testImmutableSnapshotPreservesSharedReferencesConstraintsAndOrder() throws {
        let document = try parseJSONPreservingOrder(##"{"$defs":{"Shared":{"type":"string","enum":["a","b"]},"Box":{"type":"object","description":"keep","additionalProperties":false,"allOf":[{"minProperties":1}],"properties":{"zeta":{"type":"number","minimum":0,"maximum":10},"alpha":{"anyOf":[{"type":"string","minLength":2},{"type":"number"}]},"reference":{"$ref":"#/$defs/Shared"}},"required":["zeta"]}},"properties":{"Box":{"$ref":"#/$defs/Box"}}}"##)
        let original = compileLibrarySchema(document), copy = original
        XCTAssertEqual(wire(copy), document)
        XCTAssertEqual(copy.components["Box"]?.map(\.name), ["zeta", "alpha", "reference"])
        XCTAssertEqual(wire(copy).field("$defs")?.field("Shared"), document.field("$defs")?.field("Shared"))
        XCTAssertEqual(wire(copy).field("$defs")?.field("Box"), document.field("$defs")?.field("Box"))
    }
    func testOfficialOverrideControlsOrderDefaultsAndConstraintChanges() throws {
        let number = try parseJSONPreservingOrder(#"{"type":"number","minimum":2}"#)
        let text = try parseJSONPreservingOrder(#"{"type":"string"}"#)
        let base = try createLibrary(components: [box([
            ParamDef(name: "first", required: true, schema: number),
            ParamDef(name: "second", required: false, hasDefault: true, defaultValue: .string("old"), schema: text)
        ])])
        let schema = try base.extend(LibraryExtension(overrideComponents: [box([
            ParamDef(name: "second", required: false, hasDefault: true, defaultValue: .string("new"), schema: text),
            ParamDef(name: "first", required: true, schema: number)
        ])])).toSchema()
        XCTAssertEqual(createParser(schema: schema).parse("root=Box(null,4)").root?.props.map(\.key), ["second", "first"])
        XCTAssertEqual(wire(schema).field("$defs")?.field("Box")?.field("properties")?.field("second")?.field("default"), .string("new"))
        XCTAssertEqual(base.toSchema().components["Box"]?.map(\.name), ["first", "second"])
        let changed = try base.extend(LibraryExtension(overrideComponents: [box([
            ParamDef(name: "second", required: true, schema: text), ParamDef(name: "first", required: true, schema: text)
        ])])).toSchema()
        XCTAssertNil(wire(changed).field("$defs")?.field("Box")?.field("properties")?.field("second")?.field("default"))
        XCTAssertTrue(createParser(schema: changed).parse("root=Box(\"x\",7)").meta.errors.contains { $0.code == .typeMismatch })
        XCTAssertFalse(createParser(schema: changed).parse("root=Box(\"x\",\"okay\")").meta.errors.contains { $0.code == .typeMismatch })
    }
    func testFunctionDefinitionsCompileAndReachTheirMatchingHostCallback() throws {
        let params = [ParamDef(name: "amount", required: true, schema: try parseJSONPreservingOrder(#"{"type":"number"}"#))]
        let component = box([ParamDef(name: "value", required: true)])
        let definition = defineFunction(name: "Format", description: "keep", params: params,
            returns: try parseJSONPreservingOrder(#"{"type":"number"}"#)) { $0["amount"] ?? .null }
        let library = try createLibrary(components: [component], functions: [definition])
        let schema = library.toSchema(), result = createParser(schema: schema).parse("root=Box(@Format(7))")
        let evaluator = Evaluator(context: EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null },
            functions: library.customFunctions()), schema: schema)
        XCTAssertTrue(result.meta.errors.isEmpty)
        XCTAssertEqual(try XCTUnwrap(evaluator.evaluateRoot(result)).props.first?.1, .number(7))
        XCTAssertNotNil(wire(schema).field("functions")?.field("Format")?.field("returns"))
        let removed = try createLibrary(components: [component]).toSchema()
        XCTAssertTrue(createParser(schema: removed).parse("root=Box(@Format(3))").meta.errors.contains { $0.code == .unknownFunction })
    }
    @MainActor func testActionDefinitionReachesBothSchemaAndExecution() async throws {
        let action = defineAction(name: "Notify", description: "", params: [ParamDef(name: "code", required: true)])
        let library = try createLibrary(components: [box([ParamDef(name: "value", required: true)])], actions: [action])
        let schema = library.toSchema(), result = createParser(schema: schema).parse("root=Box(@Notify(7))")
        XCTAssertTrue(result.meta.errors.isEmpty)
        XCTAssertNotNil(wire(schema).field("actions")?.field("Notify")?.field("params")?.field("properties")?.field("code"))
        if let body = wire(schema).field("$defs")?.field("Notify")?.field("properties")?.field("params") {
            XCTAssertNotNil(body.field("properties")?.field("code"))
            XCTAssertNil(body.field("properties")?.field("text"))
        }
        let store = createStore()
        let evaluator = Evaluator(context: EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null },
            actions: schema.callDefs.filter { $0.value.kind == .action }), schema: schema)
        guard case .actionPlan(let plan) = try XCTUnwrap(evaluator.evaluateRoot(result)).props.first?.1 else { return XCTFail("Expected action") }
        let events = await runActionPlan(plan, context: ActionRuntimeContext(store: store, evaluate: { evaluator.evaluate($0) },
            runQuery: { _ in }, runMutation: { _ in .failure }))
        XCTAssertEqual(events.first?.params.first?.0, "code")
        XCTAssertEqual(events.first?.params.first?.1, .number(7))
    }
    func testBooleanParameterConstraintSurvivesCompilation() throws {
        let document = try parseJSONPreservingOrder(##"{"$defs":{"Box":{"type":"object","properties":{"value":false}}},"properties":{"Box":{"$ref":"#/$defs/Box"}}}"##)
        XCTAssertEqual(wire(compileLibrarySchema(document)).field("$defs")?.field("Box")?.field("properties")?.field("value"), .boolean(false))
    }
}
