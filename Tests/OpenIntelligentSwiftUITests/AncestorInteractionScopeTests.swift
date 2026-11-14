#if os(macOS)
import AppKit
import OpenUICore
import OpenUILang
import SwiftUI
import XCTest
@testable import OpenIntelligentSwiftUI

final class AncestorInteractionScopeTests: XCTestCase {
    @MainActor func testIncompleteCardKeepsMountedReadyChildrenReadOnlyUntilClosure() async throws {
        try await checkMountedScope(container: "Card")
    }

    @MainActor func testIncompleteFormKeepsMountedReadyChildrenReadOnlyUntilClosure() async throws {
        try await checkMountedScope(container: "Form")
    }

    @MainActor private func checkMountedScope(container: String) async throws {
        _ = NSApplication.shared
        let recorder = MountedScopeRecorder()
        let reader = try IntelligentUILibrary().readerComponents
        let overrides = try ["Checkbox", "Button"].map { name -> OpenUIComponent in
            let definition = try XCTUnwrap(reader.library.components.first { $0.name == name })
            // Preserve the real control's schema and the Core registration
            // host. Only replace its visual leaf with a native context probe.
            return OpenUIComponent(definition) { [weak recorder] context in
                MountedScopeMarker(component: context, recorder: recorder).frame(height: 24)
            }
        }
        let library = try reader.extending(overriding: overrides)
        let state = OpenUIState(schema: library.library.toSchema(), functions: library.library.customFunctions())
        var received: [ActionEvent] = []
        state.onAction = { received.append($0) }
        // State and both controls are complete. Only the real ancestor's
        // children array/call remains open; this isolates the inherited gate.
        state.push("""
        $choice = false
        root = Col([\(container)([Checkbox($choice,"Pick"),Button("Apply",Action([@Set($choice,true),@ToAssistant("Applied")])),
        """)
        let hosting = NSHostingView(rootView:
            OpenUICoreView(state: state, registry: library.registry).frame(width: 320))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        defer { window.close() }
        func settle() {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            hosting.layoutSubtreeIfNeeded()
        }
        settle()
        let ancestor = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
        XCTAssertEqual(ancestor.typeName, container)
        XCTAssertFalse(ancestor.isSourceComplete)
        let pendingCheckbox = try XCTUnwrap(recorder.contexts["Checkbox"], "Checkbox must be mounted")
        let pendingButton = try XCTUnwrap(recorder.contexts["Button"], "Button must be mounted")
        XCTAssertTrue(pendingCheckbox.element.isSourceComplete)
        XCTAssertTrue(pendingButton.element.isSourceComplete)
        XCTAssertTrue(try XCTUnwrap(pendingButton.action()).isSourceComplete)
        XCTAssertFalse(pendingCheckbox.canInteract, "A ready child must inherit its unfinished \(container) scope")
        XCTAssertFalse(pendingButton.canInteract)
        XCTAssertEqual(recorder.enabled["Checkbox"], false)
        XCTAssertEqual(recorder.enabled["Button"], false)
        let pendingBinding = try XCTUnwrap(pendingCheckbox.binding("checked"))
        pendingBinding.wrappedValue = .boolean(true)
        XCTAssertEqual(state.stateValue("$choice"), .boolean(false), "The mounted binding must reject an early edit")
        let rejected = await pendingButton.perform(try XCTUnwrap(pendingButton.action()))
        XCTAssertTrue(rejected.isEmpty)
        XCTAssertTrue(received.isEmpty)
        XCTAssertEqual(state.stateValue("$choice"), .boolean(false))

        state.push("Text(\"tail\")])])\n")
        state.complete()
        settle()
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertTrue(try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first).isSourceComplete)
        let readyCheckbox = try XCTUnwrap(recorder.contexts["Checkbox"])
        let readyButton = try XCTUnwrap(recorder.contexts["Button"])
        XCTAssertTrue(readyCheckbox.canInteract, "Completing the ancestor must update the mounted child context")
        XCTAssertTrue(readyButton.canInteract)
        XCTAssertEqual(recorder.enabled["Checkbox"], true)
        XCTAssertEqual(recorder.enabled["Button"], true)
        try XCTUnwrap(readyCheckbox.binding("checked")).wrappedValue = .boolean(true)
        XCTAssertEqual(state.stateValue("$choice"), .boolean(true))
        state.setState("$choice", value: .boolean(false))
        settle()
        let currentButton = try XCTUnwrap(recorder.contexts["Button"])
        let accepted = await currentButton.perform(try XCTUnwrap(currentButton.action()))
        XCTAssertEqual(state.stateValue("$choice"), .boolean(true))
        XCTAssertEqual(accepted.count, 1)
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.humanFriendlyMessage, "Applied")
    }
}

@MainActor private final class MountedScopeRecorder {
    var contexts: [String: OpenUIComponentContext] = [:]
    var enabled: [String: Bool] = [:]
}

private struct MountedScopeMarker: NSViewRepresentable {
    let component: OpenUIComponentContext
    let recorder: MountedScopeRecorder?

    func makeNSView(context: Context) -> NSButton {
        NSButton(title: component.element.typeName, target: nil, action: nil)
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.isEnabled = component.canInteract
        recorder?.contexts[component.element.typeName] = component
        recorder?.enabled[component.element.typeName] = button.isEnabled
    }
}
#endif
