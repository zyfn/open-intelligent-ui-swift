import OpenUICore
import OpenUILang
import SwiftUI
import XCTest

final class RegistryIdentityTests: XCTestCase {
    private func component(identity: [String]) -> OpenUIComponent {
        OpenUIComponent(name: "ProbeOption", description: "A client-owned option", params: [
            OpenUIParameter.string("selectedKey"), OpenUIParameter.string("id")
        ]) { _ in EmptyView() }.presentation(identityFields: identity)
    }

    private func value(_ selectedKey: String, id: String) -> Value {
        .element(EvaluatedElement(typeName: "ProbeOption", props: [
            ("selectedKey", .string(OpenUIString(selectedKey))),
            ("id", .string(OpenUIString(id)))
        ]))
    }

    func testCustomIdentitySurvivesReorderingWithNoComponentNameSpecialCase() throws {
        let library = try OpenUIComponentLibrary(components: [component(identity: ["selectedKey"])])
        let a = value("a", id: "record-a"), b = value("b", id: "record-b")
        let original = OpenUIRenderChild.children(of: .array([a, b]), registry: library.registry)
        let reordered = OpenUIRenderChild.children(of: .array([b, a]), registry: library.registry)
        XCTAssertEqual(original[0].id, reordered[1].id)
        XCTAssertEqual(original[1].id, reordered[0].id)
        let refreshed = OpenUIRenderChild.children(
            of: .array([value("a", id: "new-server-record")]), registry: library.registry)
        XCTAssertEqual(original[0].id, refreshed[0].id,
                       "Library-selected identity must take precedence over generic id")
    }

    func testSameComponentNameCanHaveDifferentIdentityInSeparateLibraries() throws {
        let first = try OpenUIComponentLibrary(components: [component(identity: ["selectedKey"])])
        let second = try OpenUIComponentLibrary(components: [component(identity: ["id"])])
        let item = value("selection", id: "record")
        XCTAssertEqual(first.registry.identityFields(for: "ProbeOption"), ["selectedKey"])
        XCTAssertEqual(second.registry.identityFields(for: "ProbeOption"), ["id"])
        XCTAssertNotEqual(OpenUIRenderChild.children(of: item, registry: first.registry).first?.id,
                          OpenUIRenderChild.children(of: item, registry: second.registry).first?.id)
    }

    func testDefinitionReplacementAndExtensionPreserveOnlyDeclaredIdentityFields() throws {
        let original = component(identity: ["selectedKey", "notAParameter", "selectedKey"])
        let library = try OpenUIComponentLibrary(components: [original])
        XCTAssertEqual(library.registry.identityFields(for: "ProbeOption"), ["selectedKey"])
        let replacement = original.replacingDefinition(defineComponent(
            name: "ProbeOption", description: "Only the record id remains",
            params: [OpenUIParameter.string("id")]))
        let replaced = try library.extending(overriding: [replacement])
        XCTAssertFalse(replaced.registry.identityFields(for: "ProbeOption").contains("selectedKey"))
        let overridden = try library.extending(overriding: [component(identity: ["id"])])
        XCTAssertEqual(overridden.registry.identityFields(for: "ProbeOption"), ["id"])
        XCTAssertEqual(library.registry.identityFields(for: "ProbeOption"), ["selectedKey"],
                       "An extension must not mutate the original registry")
    }
}
