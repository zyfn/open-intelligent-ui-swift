import SwiftLang
import XCTest
@testable import SwiftOpenUI

@MainActor final class TabsVariantTests: XCTestCase {
    private let sat = "sat=TabItem(\"2026-11-14\",\"周六\",[a])\n"
    private let sun = "sun=TabItem(\"2026-11-15\",\"周日\",[b])\n"
    private let mon = "mon=TabItem(\"2026-11-16\",\"周一\",[c])\n"
    private let texts = "a=TextContent(\"Sat\")\nb=TextContent(\"Sun\")\nc=TextContent(\"Mon\")\n"

    private func read(_ state: OpenUIState, _ library: OpenUIComponentLibrary,
                      _ selection: inout NativeTabsSelection) throws -> (NativeTabsVariant, [NativeTabPanel]) {
        let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.registry, state: state)
        let variant = NativeTabsVariant(context)
        let children = context.children("items")
        let panels = NativeTabPanel.read(children, variant: variant)
        selection.reconcile(.read(context, children: children, panels: panels, variant: variant))
        return (variant, panels)
    }

    func testOnlyAnOptionalTabsVariantIsExportedAndHistoricalCallsStillParse() throws {
        let library = try OpenUIComponents.library()
        let spec = library.toSpec()
        let component = try XCTUnwrap(spec.components.first { $0.name == "Tabs" })
        XCTAssertEqual(component.signature, "Tabs(items: TabItem[], variant?: \"default\" | \"date\")")
        XCTAssertNil(library.registry["DateTabs"])
        XCTAssertTrue(library.prompt().contains(component.signature))
        for schema in [library.library.toSchema(), compileLibrarySchema(spec)] {
            XCTAssertEqual(schema.components["Tabs"]?.map(\.name), ["items", "variant"])
            XCTAssertEqual(schema.components["TabItem"]?.map(\.name), ["value", "trigger", "content"])
            let state = OpenUIState(schema: schema)
            state.setSource("root=Stack([Card([Tabs([sat,sun],\"date\")]),Tabs([sat,sun]),Tabs([sat,sun],\"default\")])\n" + sat + sun + texts)
            XCTAssertNotNil(state.root)
            XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        }
    }

    func testAllStylesWaitForTheDeclaredFirstItemAndKeepTheUserSelection() throws {
        let library = try OpenUIComponents.library()
        for (tail, expected) in [("", NativeTabsVariant.standard), (",\"default\"", .standard), (",\"date\"", .date)] {
            let state = OpenUIState(schema: library.library.toSchema())
            var selection = NativeTabsSelection()
            state.push("root=Tabs([sat,sun,mon]\(tail))\n" + texts + sun)
            let (style, later) = try read(state, library, &selection)
            XCTAssertEqual(style, expected)
            XCTAssertEqual(later.map(\.id), ["2026-11-15"])
            XCTAssertNil(selection.selected, "A later reference resolving first cannot claim the initial page")
            state.push(sat)
            let (_, days) = try read(state, library, &selection)
            XCTAssertEqual(selection.selected, "2026-11-14")
            XCTAssertEqual(days.map(\.dayNumber), expected == .date ? [14, 15] : [nil, nil])
            selection.choose("2026-11-15")
            state.push(mon)
            _ = try read(state, library, &selection)
            state.complete()
            _ = try read(state, library, &selection)
            XCTAssertEqual(selection.selected, "2026-11-15")
            XCTAssertTrue(state.snapshotState().isEmpty)
        }
    }

    func testExplicitHostBindingKeepsItsPublishedPositionWithEitherReader() throws {
        let standard = try OpenUIComponents.library()
        let renderer = try XCTUnwrap(OpenUIComponents.components.first { $0.definition.name == "Tabs" })
        let pinned = try XCTUnwrap(OpenUIReference.definitions.first { $0.name == "Tabs" })
        let variantParam = try XCTUnwrap(renderer.definition.params.first { $0.name == "variant" })
        for includesVariant in [false, true] {
            var definition = pinned
            definition.params.append(OpenUIParameter.selection("value", required: false))
            if includesVariant { definition.params.append(variantParam) }
            let host = try standard.extending(overriding: [renderer.replacingDefinition(definition)])
            let state = OpenUIState(schema: compileLibrarySchema(host.toSpec()))
            let suffix = includesVariant ? ",\"date\"" : ""
            state.setSource("$choice=\"2026-11-15\"\nroot=Tabs([sat,sun],$choice\(suffix))\n" + sat + sun + texts)
            XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
            let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: host.registry, state: state)
            XCTAssertEqual(NativeTabsVariant(context), includesVariant ? .date : .standard)
            let binding = try XCTUnwrap(context.presentationBinding("value"))
            XCTAssertEqual(binding.wrappedValue, .string("2026-11-15"))
            binding.wrappedValue = .string("2026-11-14")
            XCTAssertEqual(state.stateValue("$choice"), .string("2026-11-14"))
        }
    }

    func testUnresolvedTailKeepsReadableContentAndLateStyleKeepsTheTappedTab() throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        var selection = NativeTabsSelection()
        state.push("root=Tabs([TabItem(\"2026-11-14")
        XCTAssertTrue(try read(state, library, &selection).1.isEmpty)
        state.push("\",\"周六\",[TextContent(\"沿湖")
        let (pending, first) = try read(state, library, &selection)
        XCTAssertEqual(pending, .pending)
        XCTAssertEqual(selection.selected, "2026-11-14")
        guard let child = first.first.flatMap({ OpenUIRenderChild.children(of: $0.content).first }),
              case .element(let text) = child.value else { return XCTFail("Missing readable first page") }
        XCTAssertEqual(PropValue.string(text, "text"), "沿湖")
        state.push("散步\")]),TabItem(\"2026-11-15\",\"周日\",[])],\"da")
        XCTAssertEqual(try read(state, library, &selection).0, .pending)
        selection.choose("2026-11-15")
        state.push("te\")")
        let (date, panels) = try read(state, library, &selection)
        XCTAssertEqual(date, .date)
        XCTAssertEqual(panels.map(\.dayNumber), [14, 15])
        XCTAssertEqual(selection.selected, "2026-11-15")
    }

    func testInterruptFallsBackToOrdinaryStyleAndFirstSurvivingItem() throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        var selection = NativeTabsSelection()
        state.push("root=Tabs([missing,TabItem(\"2026-11-15\",\"周日\",[])],\"da")
        _ = try read(state, library, &selection)
        XCTAssertNil(selection.selected)
        state.interrupt()
        let (variant, panels) = try read(state, library, &selection)
        XCTAssertEqual(variant, .standard)
        XCTAssertEqual(panels.map(\.dayNumber), [nil])
        XCTAssertEqual(selection.selected, "2026-11-15")
    }

    func testReorderingKeepsTheSelectedKeyAndSettledRemovalUsesTheFirstSurvivor() throws {
        let library = try OpenUIComponents.library()
        for tail in ["", ",\"date\""] {
            let state = OpenUIState(schema: library.library.toSchema())
            state.setSource("$reverse=false\n$remove=false\nroot=Tabs($remove?[sat,sun]:($reverse?[mon,sat,sun]:[sat,sun,mon])\(tail))\n" + texts + sat + sun + mon)
            var selection = NativeTabsSelection()
            _ = try read(state, library, &selection)
            XCTAssertEqual(selection.selected, "2026-11-14")
            selection.choose("2026-11-16")
            state.setState("$reverse", value: .boolean(true))
            XCTAssertEqual(try read(state, library, &selection).1.map(\.id), ["2026-11-16", "2026-11-14", "2026-11-15"])
            XCTAssertEqual(selection.selected, "2026-11-16")
            state.setState("$remove", value: .boolean(true))
            _ = try read(state, library, &selection)
            XCTAssertEqual(selection.selected, "2026-11-14")
        }
        XCTAssertNil(NativeTabPanel.dayOfMonth("2026-02-29"))
        XCTAssertNil(NativeTabPanel.dayOfMonth("2026-1-5"))
        XCTAssertEqual(NativeTabPanel.dayOfMonth("2024-02-29"), 29)
    }
}
