import XCTest
@testable import SwiftLang

final class FeedbackAuditSchemaProbeTests: XCTestCase {
    private func library() throws -> Library {
        try createLibrary(components: [defineComponent(name: "Box", description: "", params: [ParamDef(name: "text", required: true)])])
    }
    func testOfficialComponentAdditionAndRemovalReachCompiledSnapshots() throws {
        let base = try library()
        let added = try base.extend(LibraryExtension(addComponents: [defineComponent(name: "Extra", description: "",
            params: [ParamDef(name: "value", required: true)])]))
        XCTAssertEqual(createParser(schema: added.toSchema()).parse("root=Extra(7)").root?.typeName, "Extra")
        XCTAssertNil(base.toSchema().components["Extra"])
        let removed = try added.extend(LibraryExtension(removeComponents: ["Box"]))
        XCTAssertTrue(createParser(schema: removed.toSchema()).parse("root=Box(\"old\")").meta.errors.contains { $0.code == .unknownComponent })
    }
    func testOfficialOverrideAndCompileEntryKeepTheOriginalIndependent() throws {
        let base = try library()
        let changed = try base.extend(LibraryExtension(overrideComponents: [defineComponent(name: "Box", description: "",
            params: [ParamDef(name: "renamed", required: true)])]))
        XCTAssertEqual(createParser(schema: compileLibrarySchema(changed.toSpec())).parse("root=Box(7)").root?.props.first?.key, "renamed")
        XCTAssertEqual(createParser(schema: base.toSchema()).parse("root=Box(\"old\")").root?.props.first?.key, "text")
    }
    func testOfficialFunctionAdditionIsVisibleToParser() throws {
        let base = try library()
        let changed = try base.extend(LibraryExtension(addFunctions: [defineFunction(name: "Upper", description: "",
            params: [ParamDef(name: "text", required: true)]) { $0["text"] ?? .null }]))
        XCTAssertFalse(createParser(schema: changed.toSchema()).parse("root=Box(@Upper(\"hello\"))").meta.errors.contains { $0.code == .unknownFunction })
    }
    func testResourceExhaustionIsDistinctFromOrdinaryPatternMismatch() {
        let text = String(repeating: "a", count: 1_048_577)
        XCTAssertEqual(testRegExp("^a+$", value: OpenUIString(text)), .resourceError)
        let rules = parseStructuredRules(try! parseJSONPreservingOrder(#"{"pattern":"^a+$"}"#))
        let exhausted = validate(.string(OpenUIString(text)), rules: rules)
        let ordinary = validate(.string("b"), rules: rules)
        print("AUDIT pattern exhausted=\(String(describing: exhausted)), mismatch=\(String(describing: ordinary))")
        XCTAssertNotEqual(exhausted, ordinary, "Resource exhaustion must not be indistinguishable from a nonmatching value")
    }
    func testInvalidPatternKeepsOfficialLenientBehavior() throws {
        let rules = parseStructuredRules(try parseJSONPreservingOrder(#"{"pattern":"["}"#))
        XCTAssertNil(validate(.string("abc"), rules: rules))
    }
}
