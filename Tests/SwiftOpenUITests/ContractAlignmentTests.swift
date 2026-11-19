import SwiftLang
import SwiftUI
import XCTest

@testable import SwiftOpenUI

final class ContractAlignmentTests: XCTestCase {
    func testReferenceNamesAndCardArityAreCanonical() throws {
        let library = try OpenUIComponents.library()
        let schema = library.library.toSchema()
        XCTAssertEqual(schema.components["TabItem"]?.map(\.name), ["value", "trigger", "content"])
        XCTAssertEqual(schema.components["Tabs"]?.map(\.name), ["items", "variant"])
        XCTAssertEqual(schema.components["Card"]?.map(\.name), ["children", "variant", "direction", "gap", "align", "justify", "wrap"])
        let upstream = LibrarySpec(json: OpenUIReference.catalog.field("spec")!)
        for expected in upstream.components where !["Card", "TabItem", "AccordionItem"].contains(expected.name) {
            let signature: String
            switch expected.name {
            case "Tabs": signature = "Tabs(items: TabItem[], variant?: \"default\" | \"date\")"
            case "Steps": signature = "Steps(items: StepsItem[], variant?: \"default\" | \"timeline\")"
            case "StepsItem": signature = "StepsItem(title: string, details: string, time?: string)"
            default: signature = expected.signature
            }
            XCTAssertEqual(library.toSpec().components.first { $0.name == expected.name }?.signature, signature, expected.name)
        }
    }

    @MainActor func testUpstreamTableCellsRetainNestedComponentValues() throws {
        let library = try OpenUIComponents.library()
        let runtime = OpenUIState(schema: library.library.toSchema())
        runtime.setSource("""
            root=Table([
              Col("Category",[Stack([Icon("chart"),TextContent("Charts")],"row"),TextContent("Media")]),
              Col("Preview",[BarChart(["A","B"],[Series("Visits",[2,3])]),Image("Photo","https://example.invalid/photo.jpg")])
            ])
            """)
        XCTAssertTrue(runtime.errors.isEmpty, "\(runtime.errors)")
        let table = try XCTUnwrap(runtime.root)
        let columns = PropValue.children(table, "columns")
        XCTAssertEqual(columns.map(\.typeName), ["Col", "Col"])
        let first = try XCTUnwrap(PropValue.value(columns[0], "data"))
        let second = try XCTUnwrap(PropValue.value(columns[1], "data"))
        XCTAssertEqual(OpenUIRenderChild.children(of: first).compactMap { child in
            if case .element(let element) = child.value { return element.typeName }
            return nil
        }, ["Stack", "TextContent"])
        XCTAssertEqual(OpenUIRenderChild.children(of: second).compactMap { child in
            if case .element(let element) = child.value { return element.typeName }
            return nil
        }, ["BarChart", "Image"])
    }

    @MainActor func testUpstreamTabsNeedNoBindingAndCardComposesChildren() throws {
        let library = try OpenUIComponents.library()
        let runtime = OpenUIState(schema: library.library.toSchema())
        runtime.setSource(
            "root=Stack([Tabs([TabItem(\"a\",\"Alpha\",[TextContent(\"A\")]),TabItem(\"b\",\"Beta\",[TextContent(\"B\")])]),Card([TextContent(\"Heading\"),Image(\"Photo\"),Buttons([Button(\"Continue\")])])])"
        )
        XCTAssertTrue(runtime.errors.isEmpty, "\(runtime.errors)")
        let tabs = try XCTUnwrap(PropValue.children(runtime.root!).first)
        XCTAssertNil(runtime.binding(for: tabs, prop: "value"))
        let context = OpenUIComponentContext(element: tabs, registry: library.registry, state: runtime)
        let children = context.children("items")
        let panels = NativeTabPanel.read(children)
        let choices = NativeTabChoices.read(context, children: children, panels: panels, variant: .standard)
        var local = NativeTabsSelection()
        local.reconcile(choices)
        XCTAssertEqual(local.selected, "a")
        local.choose("b")
        local.reconcile(choices)
        XCTAssertEqual(local.selected, "b", "A user's choice must survive the next update")
        XCTAssertTrue(
            runtime.snapshotState().isEmpty, "Uncontrolled Tabs must not allocate a shared variable")
    }

    @MainActor func testNativeOnlyRegistrationsAreRemoved() throws {
        let library = try OpenUIComponents.library()
        for name in ["Tab", "Section", "AdaptiveGroup", "NavigationLink", "WebView", "Popover"] {
            XCTAssertNil(library.registry[name], name)
            XCTAssertFalse(library.library.components.contains { $0.name == name })
        }
        let runtime = OpenUIState(schema: library.library.toSchema())
        runtime.setSource("root=Tab(\"a\",\"Old\",[])")
        XCTAssertFalse(runtime.errors.isEmpty)
    }

    @MainActor func testTypedAuthoringUsesPinnedCoreParameterOrder() throws {
        let bad = defineComponent(
            name: "Bad", description: "",
            params: [OpenUIParameter.string("optional", required: false), OpenUIParameter.string("required")])
        let ordered = try createLibrary(components: [bad])
        XCTAssertEqual(ordered.components.first?.params.map(\.name), ["optional", "required"])
        let library = try OpenUIComponents.library()
        let invalid = OpenUIComponent(bad) { _ in EmptyView() }
        let extended = try library.extending(adding: [invalid])
        XCTAssertNotNil(extended.registry["Bad"], "Do not add native-only required-first validation")
        let runtime = OpenUIState(
            schema: compileLibrarySchema(try LibrarySpec(jsonString: library.toSpec().jsonString())))
        runtime.setSource(
            "root=Stack([SwitchGroup(\"preferences\",[SwitchItem(null,null,\"updates\",true)])])")
        XCTAssertTrue(runtime.errors.isEmpty, "\(runtime.errors)")
        let group = PropValue.children(runtime.root!)[0]
        let field = NativeFieldState(
            context: OpenUIComponentContext(element: group, registry: library.registry, state: runtime))
        field.initialize()
        XCTAssertTrue(field.toggle("updates").wrappedValue)
    }
}
