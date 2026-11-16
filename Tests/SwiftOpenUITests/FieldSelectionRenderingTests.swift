#if os(macOS)
import AppKit
import SwiftLang
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class FieldSelectionRenderingTests: XCTestCase {
    @MainActor func testStoreOnlySelectionsRefreshTheMountedNativeControls() throws {
        _ = NSApplication.shared
        let examples: [(String, String, Value)] = [
            (#"root=Select("choice",[SelectItem("walk","步行"),SelectItem("bike","骑行")],"请选择")"#, "choice", .string("walk")),
            (#"root=RadioGroup("pace",[RadioItem("轻松","","easy"),RadioItem("充实","","full")],"easy")"#, "pace", .string("full")),
            (#"root=CheckBoxGroup("interests",[CheckBoxItem("自然","","nature",false)])"#, "interests", .object([.init(key: "nature", value: .boolean(true))])),
            (#"root=SwitchGroup("settings",[SwitchItem("行程提醒","","reminders",false)])"#, "settings", .object([.init(key: "reminders", value: .boolean(true))]))
        ]
        for (source, name, value) in examples {
            let library = try OpenUIComponents.library()
            let state = OpenUIState(schema: library.library.toSchema())
            state.setSource(source)
            let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
                .frame(width: 360, height: 160).background(Color.white))
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 360, height: 160),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            pump(host)
            let before = try pixels(host)
            let beforeSwitch = name == "settings" ? try XCTUnwrap(nativeSwitch(in: host)).state : nil
            let originalRoot = try XCTUnwrap(state.root)
            state.setFieldValue(form: nil, name: OpenUIString(name), value: value)
            pump(host)
            XCTAssertEqual(state.fieldValue(form: nil, name: OpenUIString(name)), value)
            XCTAssertEqual(state.root, originalRoot, "The control props do not carry its Store-only selection")
            if name == "settings" {
                // cacheDisplay omits the composited NSSwitch. Assert its actual
                // mounted native state rather than treating that bitmap as UI.
                XCTAssertEqual(beforeSwitch, .off)
                XCTAssertEqual(try XCTUnwrap(nativeSwitch(in: host)).state, .on)
            } else {
                XCTAssertNotEqual(try pixels(host), before, "Mounted native \(name) must redraw its selection without replacing the host")
            }
        }
    }

    @MainActor func testStandaloneFieldTracksItsFormAndKeepsTheMountedInputAndFocus() throws {
        _ = NSApplication.shared
        let library = try OpenUIComponents.library()
        let owner = OpenUIState(schema: library.library.toSchema())
        let ambient = OpenUIState(schema: library.library.toSchema())
        defer { owner.reset(); ambient.reset() }
        owner.setSource("root=Input(\"draft\",null,\"text\",null,\"initial\")")
        ambient.setSource("root=Input(\"draft\",null,\"text\",null,\"ambient\")")
        let context = OpenUIComponentContext(element: try XCTUnwrap(owner.root), registry: library.registry,
            state: owner, formName: "contact")
        let host = NSHostingView(rootView: OpenUINativeField(context: context, kind: .input)
            .environmentObject(ambient).frame(width: 320, height: 100))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        func input(_ view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap(input).first
        }
        pump(host)
        let mounted = try XCTUnwrap(input(host))
        XCTAssertEqual(mounted.stringValue, "initial")
        mounted.selectText(nil)
        let editor = try XCTUnwrap(mounted.currentEditor())
        owner.setFieldValue(form: "other", name: "draft", value: .string("unrelated"))
        ambient.setFieldValue(form: "contact", name: "draft", value: .string("wrong owner"))
        pump(host)
        XCTAssertTrue(input(host) === mounted)
        XCTAssertTrue(mounted.currentEditor() === editor)
        XCTAssertEqual(mounted.stringValue, "initial")
        window.makeFirstResponder(nil)
        owner.setFieldValue(form: "contact", name: "draft", value: .string("updated owner value"))
        pump(host)
        XCTAssertTrue(input(host) === mounted)
        XCTAssertEqual(mounted.stringValue, "updated owner value")
        XCTAssertEqual(owner.fieldValue(form: "contact", name: "draft"), .string("updated owner value"))
    }

    @MainActor private func pump(_ view: NSView) {
        for _ in 0..<6 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
    }

    @MainActor private func pixels(_ view: NSView) throws -> Data {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return Data(bytes: try XCTUnwrap(bitmap.bitmapData), count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    @MainActor private func nativeSwitch(in view: NSView) -> NSSwitch? {
        if let control = view as? NSSwitch { return control }
        return view.subviews.lazy.compactMap { self.nativeSwitch(in: $0) }.first
    }
}
#endif
