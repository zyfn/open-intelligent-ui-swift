import XCTest
import SwiftUI
import SwiftLang
@testable import SwiftIntelligentUI
#if os(macOS)
import AppKit
#endif

final class InputTests: XCTestCase {
    func testNumericDraftsDoNotReplaceLastValidValue() {
        XCTAssertNil(InputEditing.numericValue("-"))
        XCTAssertNil(InputEditing.numericValue("1e"))
        XCTAssertNil(InputEditing.numericValue("nan"))
        XCTAssertNil(InputEditing.numericValue("1e9999"))
        XCTAssertEqual(InputEditing.numericValue(""), .null)
        XCTAssertEqual(InputEditing.numericValue("1."), .number(1))
        XCTAssertEqual(InputEditing.numericValue("-1,234.5"), .number(-1234.5))
        XCTAssertEqual(InputEditing.text(.number(12)), "12")
    }

    @MainActor func testInputAndTextAreaBindingsUpdateText() throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource("root = Col([Input($name, \"名称\"), TextArea($note, \"备注\", \"请输入\", 3), Text($name + \" / \" + $note)])\n$name = \"初始\"\n$note = \"\"")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let children = PropValue.children(try XCTUnwrap(state.root))
        try XCTUnwrap(state.binding(for: children[0], prop: "value")).wrappedValue = .string("相机")
        try XCTUnwrap(state.binding(for: children[1], prop: "value")).wrappedValue = .string("第一行\n第二行")
        let text = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).last)
        XCTAssertEqual(PropValue.string(text, "text"), "相机 / 第一行\n第二行")
    }

    @MainActor func testChoiceSchemasBindingsAndDuplicateValues() throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource("root = Col([Select($v, [\"a\", {value: \"b\", label: \"B\"}, {value: \"b\", label: \"Duplicate\"}], \"选择\", \"请选择\"), SegmentedControl($v, [\"a\", \"b\"], true), RadioGroup($v, [{value: \"a\", label: \"A\", description: \"说明\"}, \"b\"], \"模式\", \"cards\"), Text($v)])\n$v = \"unknown\"")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let children = PropValue.children(try XCTUnwrap(state.root))
        let context = OpenUIComponentContext(element: children[0], registry: library.components.registry, state: state)
        let options = ChoiceOption.decode(context.value("options"))
        XCTAssertEqual(options.map(\.id), ["a", "b"])
        XCTAssertEqual(options.last?.label, "B")
        XCTAssertEqual(state.stateValue("$v"), .string("unknown"))
        try XCTUnwrap(context.binding("value")).wrappedValue = .string("b")
        let updated = PropValue.children(try XCTUnwrap(state.root))
        for component in updated.prefix(3) {
            XCTAssertEqual(try XCTUnwrap(state.binding(for: component, prop: "value")).wrappedValue, .string("b"))
        }
        XCTAssertEqual(PropValue.string(updated[3], "text"), "b")
    }

    @MainActor func testAllNewControlsRenderAtAccessibilitySize() throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource("root = Col([Caption(\"说明\"), Label(\"字段\"), Input($v, \"单行\"), TextArea($v, \"多行\"), Select($v, [\"a\", \"b\"]), SegmentedControl($v, [\"a\", \"b\"]), RadioGroup($v, [\"a\", \"b\"], \"单选\", \"pills\"), Link(\"来源\", \"/source\")])\n$v = \"a\"")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let renderer = ImageRenderer(content: OpenIntelligentUIContentView(state: state, library: library)
            .environment(\.dynamicTypeSize, .accessibility2).frame(width: 320))
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertGreaterThan(image.height, 100)
    }

    func testSourceURLRejectsUnsafeSchemesAndKeepsRelativePaths() {
        XCTAssertTrue(SourceURL.isActionable("/products/a?offer=2"))
        XCTAssertTrue(SourceURL.isActionable("https://example.com/a"))
        XCTAssertFalse(SourceURL.isActionable(" javascript:alert(1)"))
        XCTAssertFalse(SourceURL.isActionable("file:///etc/passwd"))
        XCTAssertFalse(SourceURL.isActionable("data:text/html,test"))
        XCTAssertFalse(SourceURL.isActionable(""))
        XCTAssertFalse(SourceURL.isActionable("https://example.com\n/a"))
    }

    @MainActor func testExternalResetReachesInputBinding() async throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource("root = Col([Input($name), Input($amount, \"金额\", \"number\"), Button(\"重置\", Action([@Set($name, \"初始\"), @Set($amount, 12)]))])\n$name = \"修改\"\n$amount = 99")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let children = PropValue.children(try XCTUnwrap(state.root))
        _ = await state.perform(try XCTUnwrap(PropValue.actionPlan(children[2], "action")))
        XCTAssertEqual(state.stateValue("$name"), .string("初始"))
        XCTAssertEqual(state.stateValue("$amount"), .number(12))
    }

    #if os(macOS)
    @MainActor func testMountedInputsKeepEditingIdentityWhileTheirOwnBindingsUpdate() throws {
        _ = NSApplication.shared
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        defer { state.reset() }
        state.setSource("""
        $left="left before"
        $right="right before"
        root=Col([Input($left,"Left"),Input($right,"Right")])
        """)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let host = NSHostingView(rootView: OpenIntelligentUIContentView(state: state, library: library)
            .frame(width: 320, height: 240, alignment: .topLeading))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 240),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        func fields(_ view: NSView) -> [NSTextField] {
            let current = (view as? NSTextField).flatMap { $0.isEditable ? $0 : nil }
            return (current.map { [$0] } ?? []) + view.subviews.flatMap(fields)
        }
        func settle() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            host.layoutSubtreeIfNeeded()
        }
        settle()
        XCTAssertEqual(fields(host).count, 2)
        let left = try XCTUnwrap(fields(host).first { $0.stringValue == "left before" })
        let right = try XCTUnwrap(fields(host).first { $0.stringValue == "right before" })
        left.selectText(nil)
        let editor = try XCTUnwrap(left.currentEditor() as? NSTextView)
        editor.insertText("edited left", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        settle()
        XCTAssertEqual(state.stateValue("$left"), .string("edited left"))

        state.setState("$right", value: .string("right after"))
        state.setFieldValue(form: nil, name: "unobserved", value: .string("unrelated field"))
        settle()
        XCTAssertEqual(fields(host).count, 2)
        XCTAssertTrue(fields(host).contains { $0 === left })
        XCTAssertTrue(fields(host).contains { $0 === right })
        XCTAssertTrue(left.currentEditor() === editor, "An unrelated publication must preserve the active editor")
        XCTAssertEqual(editor.string, "edited left")
        XCTAssertEqual(right.stringValue, "right after", "The existing Context subscription must deliver this input's binding")

        window.makeFirstResponder(nil)
        state.setState("$left", value: .string("external left"))
        settle()
        XCTAssertEqual(left.stringValue, "external left")
        state.setSource("$replacement=\"replacement document\"\nroot=Input($replacement,\"Replacement\")")
        settle()
        let replacement = try XCTUnwrap(fields(host).first)
        XCTAssertEqual(fields(host).count, 1)
        XCTAssertEqual(replacement.stringValue, "replacement document")
        XCTAssertFalse(replacement === left || replacement === right, "Replacement owns a new editing lifetime")
    }

    @MainActor func testMountedInputEnablesWhenItsCallClosesWithoutRemounting() throws {
        _ = NSApplication.shared
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        defer { state.reset() }
        state.push("$name=\"Initial\"\nroot=Input($name,\"Name\"")
        let host = NSHostingView(rootView: OpenIntelligentUIContentView(state: state, library: library)
            .frame(width: 320, height: 100))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        func field(_ view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap(field).first
        }
        func settle() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            host.layoutSubtreeIfNeeded()
        }
        settle()
        let input = try XCTUnwrap(field(host))
        XCTAssertFalse(input.isEnabled)
        state.push(")")
        settle()
        XCTAssertFalse(state.isComplete)
        XCTAssertTrue(input.isEnabled)
        XCTAssertTrue(field(host) === input)
        state.complete()
        state.setState("$name", value: .string("Updated"))
        settle()
        XCTAssertTrue(field(host) === input)
        XCTAssertEqual(input.stringValue, "Updated")
    }
    #endif
}
