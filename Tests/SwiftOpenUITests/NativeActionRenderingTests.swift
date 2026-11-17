import SwiftLang
#if os(macOS)
import AppKit
import SwiftUI
import XCTest

@testable import SwiftOpenUI

final class NativeActionRenderingTests: XCTestCase {
    @MainActor func testComponentContextRefreshesWhenUnchangedSourceBecomesReady() throws {
        _ = NSApplication.shared
        let probe = OpenUIComponent(name: "EligibilityProbe", description: "Test render boundary", params: []) {
            EligibilityProbe(context: $0)
        }
        let library = try OpenUIComponentLibrary(components: [probe])
        let state = OpenUIState(schema: library.library.toSchema())
        let source = "root=EligibilityProbe()"
        state.push(String(source.dropLast()))
        // Hold the element fixed: receiving the real closing delimiter does not
        // change its props. The registered host must propagate readiness.
        let element = try XCTUnwrap(state.root)
        let hosting = NSHostingView(rootView: RenderNode(element: element, registry: library.registry)
            .environmentObject(state))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        defer { window.close() }
        func settle() {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        func marker(in view: NSView) -> NSButton? {
            if let button = view as? NSButton,
               button.identifier?.rawValue == "openui.test.action-enabled" { return button }
            return view.subviews.lazy.compactMap { marker(in: $0) }.first
        }
        settle()
        let button = try XCTUnwrap(marker(in: hosting))
        XCTAssertFalse(button.isEnabled)
        state.push(String(source.suffix(1)))
        settle()
        XCTAssertFalse(state.isComplete)
        XCTAssertTrue(button.isEnabled, "A closed component becomes ready before stream termination")
        state.complete()
        settle()
        XCTAssertTrue(button.isEnabled, "An indirect registered view must refresh without prop changes")
        XCTAssertTrue(marker(in: hosting) === button, "Completion must retain native view identity")
        state.reset()
        settle()
        XCTAssertFalse(try XCTUnwrap(marker(in: hosting)).isEnabled)
    }

    @MainActor func testMountedActionEnablesWhenItsSourceCloses() throws {
        _ = NSApplication.shared
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        let source = "root=Button(\"Save\")"
        state.push(String(source.dropLast()))
        let context = OpenUIComponentContext(
            element: try XCTUnwrap(state.root), registry: library.registry, state: state)
        // Keep the action and context constant: source closure must invalidate the
        // action surface itself, not rely on a parent rebuilding its props.
        let hosting = NSHostingView(rootView: OpenUIActionSurface(
            context: context, action: OpenUIActions.continueConversation("Save"), useNativeStyle: true
        ) { ActionEnabledMarker() }.environmentObject(state))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 100), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        defer { window.close() }

        func settle() {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        func marker(in view: NSView) -> NSButton? {
            if let button = view as? NSButton,
               button.identifier?.rawValue == "openui.test.action-enabled" { return button }
            return view.subviews.lazy.compactMap { marker(in: $0) }.first
        }

        settle()
        let button = try XCTUnwrap(marker(in: hosting))
        XCTAssertFalse(button.isEnabled, "An unfinished component cannot dispatch actions")
        state.push(String(source.suffix(1)))
        settle()
        XCTAssertFalse(state.isComplete)
        XCTAssertTrue(button.isEnabled, "The mounted action enables as soon as its component closes")
        state.complete()
        XCTAssertTrue(context.canInteract)
        settle()
        XCTAssertTrue(button.isEnabled, "A mounted action must enable after streaming completes")
        state.reset()
        settle()
        XCTAssertFalse(button.isEnabled, "Reset must disable an action from the old source")
    }

    @MainActor func testStandaloneActionKeepsItsContextOwnerAndRejectsReplacementEpoch() throws {
        _ = NSApplication.shared
        let library = try OpenUIComponents.library()
        let owner = OpenUIState(schema: library.library.toSchema())
        let ambient = OpenUIState(schema: library.library.toSchema())
        defer { owner.reset(); ambient.reset() }
        owner.push("root=Button(\"Save\"")
        ambient.setSource("root=Button(\"Ambient\")")
        let context = OpenUIComponentContext(element: try XCTUnwrap(owner.root), registry: library.registry, state: owner)
        let hosting = NSHostingView(rootView: OpenUIActionSurface(context: context,
            action: OpenUIActions.continueConversation("Save"), useNativeStyle: true) {
            ActionEnabledMarker()
        }.environmentObject(ambient))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 240, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = hosting; window.orderFront(nil)
        defer { window.close() }
        func settle() {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            hosting.layoutSubtreeIfNeeded()
        }
        func marker(_ view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.identifier?.rawValue == "openui.test.action-enabled" { return button }
            return view.subviews.lazy.compactMap(marker).first
        }
        settle()
        let button = try XCTUnwrap(marker(hosting))
        XCTAssertFalse(button.isEnabled, "An unrelated ready ambient document cannot enable this Context")
        owner.push(")")
        owner.complete()
        settle()
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(marker(hosting) === button)
        ambient.reset()
        settle()
        XCTAssertTrue(button.isEnabled, "Readiness belongs to the Context owner")
        owner.setSource("$replacement=1\nroot=Button(\"Save\")")
        settle()
        XCTAssertFalse(button.isEnabled, "Observing a retained Context must not renew its original event epoch")
        XCTAssertFalse(context.canInteract)
    }
}

private struct EligibilityProbe: View {
    let context: OpenUIComponentContext
    var body: some View {
        ActionEnabledMarker().disabled(!context.canInteract)
    }
}

/// Exposes SwiftUI's effective enabled state on a native control inside the
/// action label, without depending on private SwiftUI button implementations.
private struct ActionEnabledMarker: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "Save", target: nil, action: nil)
        button.identifier = NSUserInterfaceItemIdentifier("openui.test.action-enabled")
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) { button.isEnabled = isEnabled }
}
#endif
