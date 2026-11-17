#if os(macOS)
import AppKit
import SwiftLang
import SwiftUI
import XCTest
@testable import SwiftIntelligentUI

final class AncestorInteractionScopeTests: XCTestCase {
    @MainActor func testIncompleteCardKeepsMountedReadyChildrenReadOnlyUntilClosure() async throws {
        try await checkMountedScope(container: "Card")
    }

    @MainActor func testIncompleteFormKeepsMountedReadyChildrenReadOnlyUntilClosure() async throws {
        try await checkMountedScope(container: "Form")
    }

    @MainActor func testStandaloneActionObservesItsOwnerAndRetainsItsOriginalEpoch() throws {
        _ = NSApplication.shared
        let library = try OpenIntelligentUIComponents()
        let owner = library.makeState(), ambient = library.makeState()
        defer { owner.reset(); ambient.reset() }
        owner.push("root=Text(\"Owner\"")
        ambient.setSource("root=Text(\"Ambient\")")
        let original = OpenUIComponentContext(element: try XCTUnwrap(owner.root),
            registry: library.readerComponents.registry, state: owner)
        let log = ActionMountLog()
        // Hold the Context fixed and supply a different ambient State. The
        // action must observe the Context owner, including delimiter-only updates.
        let host = NSHostingView(rootView: OpenIntelligentUIActionSurface(context: original,
            action: OpenUIActions.continueConversation("Apply")) {
            ActionMountMarker(log: log).frame(width: 160, height: 32)
        }.environmentObject(ambient))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 240, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        func settle() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            host.layoutSubtreeIfNeeded()
        }
        settle()
        let marker = try XCTUnwrap(log.button)
        XCTAssertEqual(log.mounts, 1)
        XCTAssertFalse(marker.isEnabled)
        owner.push(")")
        settle()
        XCTAssertFalse(owner.isComplete)
        XCTAssertTrue(marker.isEnabled, "The owner closing must enable the retained action without an ambient update")
        owner.complete()
        settle()
        let updates = log.updates
        owner.setFieldValue(form: nil, name: "unobserved", value: .string("unrelated owner field"))
        ambient.setFieldValue(form: nil, name: "unobserved", value: .string("unrelated ambient field"))
        settle()
        let unrelatedUpdates = log.updates - updates
        XCTAssertEqual(log.mounts, 1)
        XCTAssertEqual(unrelatedUpdates, 0, "Unrelated fields need not update the native action label")
        XCTAssertTrue(log.button === marker)
        XCTAssertTrue(marker.isEnabled)
        owner.setSource("root=Text(\"Replacement\")")
        settle()
        XCTAssertEqual(log.mounts, 1)
        XCTAssertFalse(marker.isEnabled, "Observation cannot renew a retained event Context's source epoch")
        XCTAssertFalse(original.canInteract)
        print("IUI standalone action: mounts=\(log.mounts), unrelated native label updates=\(unrelatedUpdates)")
    }

    @MainActor private func checkMountedScope(container: String) async throws {
        _ = NSApplication.shared
        let recorder = MountedScopeRecorder()
        let reader = try OpenIntelligentUIComponents().readerComponents
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
            SwiftLangView(state: state, registry: library.registry).frame(width: 320))
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

@MainActor private final class ActionMountLog {
    var mounts = 0
    var updates = 0
    weak var button: NSButton?
}

/// Counts the actual native label's lifecycle, not a reconstructed model or
/// SwiftUI body execution. The effective enabled value comes from the Button.
private struct ActionMountMarker: NSViewRepresentable {
    let log: ActionMountLog
    @Environment(\.isEnabled) private var enabled
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "Apply", target: nil, action: nil)
        log.mounts += 1; log.button = button
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        log.updates += 1; button.isEnabled = enabled
    }
}
#endif
