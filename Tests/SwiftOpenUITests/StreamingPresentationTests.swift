import SwiftLang
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class StreamingPresentationTests: XCTestCase {
    @MainActor func testPartialTextIsRenderedByTheSdkBeforeCompletion() throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        state.push("root=Stack([TextContent(\"Paris, at")
        let firstRoot = try XCTUnwrap(state.root)
        let firstText = try XCTUnwrap(PropValue.children(firstRoot).first)
        XCTAssertEqual(PropValue.string(firstText, "text"), "Paris, at")
        XCTAssertNotEqual(PropValue.string(firstText, "size"), "large-heavy",
            "A later positional style argument cannot be known before it arrives")
        XCTAssertFalse(state.isComplete)
        state.push(" your own pace\",\"large-heavy\")],\"column\",\"l\")")
        state.complete()
        let finalRoot = try XCTUnwrap(state.root)
        let finalText = try XCTUnwrap(PropValue.children(finalRoot).first)
        XCTAssertEqual(PropValue.string(finalText, "text"), "Paris, at your own pace")
        XCTAssertEqual(PropValue.string(finalText, "size"), "large-heavy")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    }

    @MainActor func testReferencedStyledTextGrowsWithAnUnfinishedScalarAssignment() throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        state.push("root=Stack([heading],\"column\",\"l\")\nheading=TextContent(title,\"large-heavy\")\ntitle=\"Pa")
        let first = try XCTUnwrap(state.root)
        let heading = try XCTUnwrap(PropValue.children(first).first)
        XCTAssertEqual(PropValue.string(heading, "text"), "Pa")
        XCTAssertEqual(PropValue.string(heading, "size"), "large-heavy")
        state.push("ris")
        let updated = try XCTUnwrap(state.root)
        let growing = try XCTUnwrap(PropValue.children(updated).first)
        XCTAssertEqual(PropValue.string(growing, "text"), "Paris")
        XCTAssertEqual(PropValue.string(growing, "size"), "large-heavy",
            "Declaring typography before leaf text keeps streaming text in one style")
        state.push("\"\n")
        state.complete()
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    }

    @MainActor func testFullBufferStreamingAndItsFinalSnapshotDoNotReplaceNativePresentation() throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        let prefix = "root=Tabs([TabItem(\"a\",\"First\",[TextContent(\"A\")])"
        state.setSource(prefix, streaming: true)
        let generation = state.presentationRevision
        let full = prefix + ",TabItem(\"b\",\"Second\",[TextContent(\"B\")])])"
        state.setSource(full, streaming: true)
        XCTAssertEqual(state.presentationRevision, generation)
        state.setSource(full, streaming: false)
        XCTAssertEqual(state.presentationRevision, generation)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        state.setSource("root=Tabs([TabItem(\"c\",\"Replacement\",[TextContent(\"C\")])])")
        XCTAssertGreaterThan(state.presentationRevision, generation)
    }

    func testTabsKeepTheFirstOrManuallySelectedItemAsOtherContentGrows() {
        let a = NativeTabPanel(id: "a", label: "First", content: .string("First"))
        let b = NativeTabPanel(id: "b", label: "Second", content: .string("Second"))
        var selection = NativeTabsSelection()
        selection.reconcile([])
        XCTAssertNil(selection.selected)
        selection.reconcile([a])
        XCTAssertEqual(selection.selected, "a")
        selection.reconcile([a, b])
        XCTAssertEqual(selection.selected, "a", "An appended item must not replace the current page")
        selection.reconcile([NativeTabPanel(id: "a", label: a.label, content: .string("First grows considerably")), b])
        XCTAssertEqual(selection.selected, "a")
        selection.reconcile([
            NativeTabPanel(id: "a", label: a.label, content: .string("First grows considerably more")),
            NativeTabPanel(id: "b", label: b.label, content: .string("Second grows too")),
        ])
        XCTAssertEqual(selection.selected, "a", "Neither the order nor the amount of incoming text changes the page")
        selection.choose("b")
        selection.reconcile([a, NativeTabPanel(id: "b", label: b.label, content: .string("Second keeps growing"))])
        XCTAssertEqual(selection.selected, "b", "A manual value change pins the chosen item")
        selection.reconcile([a])
        XCTAssertEqual(selection.selected, "a", "A settled removal falls back to the remaining first item")
        selection.reconcile([])
        XCTAssertNil(selection.selected)
    }

    func testCompleteAndIncrementalTabsIgnoreTextSizeWhenSelecting() {
        func panel(_ id: OpenUIString, _ text: OpenUIString) -> NativeTabPanel {
            NativeTabPanel(id: id, label: id.displayString, content: .string(text))
        }
        var selection = NativeTabsSelection()
        selection.reconcile([panel("a", "One"), panel("b", "Two")])
        XCTAssertEqual(selection.selected, "a")
        selection.reconcile([panel("a", "New"), panel("b", "Two")])
        XCTAssertEqual(selection.selected, "a")
        selection.reconcile([panel("a", "New"), panel("b", "🙂🙂")])
        XCTAssertEqual(selection.selected, "a", "A longer UTF-16 payload in another tab does not select it")
    }

    func testTappingTheSelectedNativeTabKeepsItAsLaterPanelsArrive() {
        let first = NativeTabPanel(id: "a", label: "First", content: .string("First"))
        var selection = NativeTabsSelection()
        selection.reconcile([first])
        XCTAssertEqual(selection.selected, "a")
        selection.choose("a")
        let second = NativeTabPanel(id: "b", label: "Second", content: .string("Later streamed content"))
        selection.reconcile([first, second])
        XCTAssertEqual(selection.selected, "a", "A native tap is an explicit choice even if its value was already active")
        selection.reconcile([first, NativeTabPanel(id: "b", label: "Second", content: .string("Later content grows again"))])
        XCTAssertEqual(selection.selected, "a")
    }

    func testChangingComponentMetadataInAnotherPanelDoesNotSelectIt() {
        func panel(_ id: OpenUIString, partial: Bool) -> NativeTabPanel {
            NativeTabPanel(id: id, label: id.displayString, content: .array([
                .element(EvaluatedElement(typeName: "TextContent", props: [("text", .string("Same text"))], partial: partial))
            ]))
        }
        var selection = NativeTabsSelection()
        selection.reconcile([panel("a", partial: true), panel("b", partial: true)])
        XCTAssertEqual(selection.selected, "a")
        selection.reconcile([panel("a", partial: true), panel("b", partial: false)])
        XCTAssertEqual(selection.selected, "a")
    }

    func testAccordionOpensTheNewestArrivalUntilTheUserChangesItsValue() {
        var selection = NativeAccordionSelection()
        selection.reconcile(["a", "b"])
        XCTAssertEqual(selection.selected, "b", "A complete first snapshot opens the last item, as upstream does")
        selection.reconcile(["a"])
        XCTAssertEqual(selection.selected, "b", "A removal does not add a native-only fallback")
        selection.reconcile(["a", "c"])
        XCTAssertEqual(selection.selected, "c")
        selection.choose(nil)
        selection.reconcile(["a", "c", "d"])
        XCTAssertNil(selection.selected, "A manual close stops automatic opening")
        selection.choose("a")
        selection.reconcile(["a", "c", "d", "e"])
        XCTAssertEqual(selection.selected, "a")
    }

    func testConditionalEmptySlotsDoNotChangeLaterAnonymousIdentities() {
        let tabs = Value.element(EvaluatedElement(typeName: "Tabs"))
        let carousel = Value.element(EvaluatedElement(typeName: "Carousel"))
        let before = OpenUIRenderChild.children(of: .array([.null, tabs, .array([.undefined, carousel])]))
        let after = OpenUIRenderChild.children(of: .array([.string("Arrived"), tabs, .array([.string("Also arrived"), carousel])]))
        XCTAssertEqual(before.map(\.id), [after[1].id, after[3].id])
    }

    @MainActor func testAppendCompleteStateAndPatchKeepPresentationWhileReplacementInvalidatesIt() throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        let generation = state.presentationRevision
        state.push("root=Tabs([TabItem(\"a\",\"First\",[TextContent(\"A\")])")
        state.push(",TabItem(\"b\",\"Second\",[TextContent(\"B\")])])")
        state.complete()
        XCTAssertEqual(state.presentationRevision, generation)
        state.setState("$note", value: .string("kept"))
        state.applyPatch("root=Tabs([TabItem(\"a\",\"First\",[TextContent(\"A grows\")]),TabItem(\"b\",\"Second\",[TextContent(\"B\")])])")
        XCTAssertEqual(state.presentationRevision, generation)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        state.setSource("root=Tabs([TabItem(\"a\",\"First\",[TextContent(\"Replacement\")])])")
        XCTAssertGreaterThan(state.presentationRevision, generation)
        let replacement = state.presentationRevision
        state.reset()
        XCTAssertGreaterThan(state.presentationRevision, replacement)
    }

    @MainActor func testIncrementalTabsKeepShowingTheFirstDeclaredItem() throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        let source = "root=Tabs([TabItem(\"a\",\"方案一 · 较长中文标题\",[TextContent(\"第一段正文逐渐增长\")]),TabItem(\"b\",\"方案二 · 另一种选择\",[TextContent(\"第二段\")]),TabItem(\"c\",\"方案三 · 第三种选择\",[TextContent(\"第三段\")])])"
        var selection = NativeTabsSelection()
        var visited = Set<OpenUIString>()
        for character in source {
            state.push(String(character))
            guard let root = state.root else { continue }
            let context = OpenUIComponentContext(element: root, registry: library.registry, state: state)
            let variant = NativeTabsVariant(context)
            let children = context.children("items")
            let panels = NativeTabPanel.read(children, variant: variant)
            selection.reconcile(.read(context, children: children, panels: panels, variant: variant))
            if let selected = selection.selected { visited.insert(selected) }
            XCTAssertFalse(state.isComplete)
        }
        state.complete()
        XCTAssertEqual(visited, Set(["a"]))
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertEqual(selection.selected, "a")
    }
}

private extension NativeTabsSelection {
    mutating func reconcile(_ panels: [NativeTabPanel]) {
        let ids = panels.map(\.id)
        reconcile(NativeTabChoices(ids: ids, first: ids.first, settled: true))
    }
}
