#if os(macOS)
import AppKit
import Combine
import OpenUICore
import OpenUILang
import SwiftUI
import XCTest

final class CoreHostIsolationTests: XCTestCase {
    @MainActor func testCustomComponentHostFitsWithoutReparsingPublishingOrRemounting() throws {
        _ = NSApplication.shared
        let mounts = CoreMountLog()
        let library = try OpenUIComponentLibrary(components: [
            OpenUIComponent(name: "ProbeCaption", description: "Application-owned caption",
                            params: [OpenUIParameter.string("text")]) { context in
                Text(context.string("text") ?? "")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(CoreMountMarker(log: mounts))
            }
        ], root: "ProbeCaption")
        let state = OpenUIState(schema: library.library.toSchema())
        let source = "$label = \"Shared Core has no component-library theme\"\nroot = ProbeCaption($label)"
        state.setSource(source, streaming: true)
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
        let size = hosting.fittingSize
        settle()
        let original = try XCTUnwrap(state.root)
        let revision = state.sourceRevision
        let created = mounts.created, removed = mounts.removed
        var parses = 0, publications = 0
        state.onParseResult = { _ in parses += 1 }
        let subscription = state.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }
        XCTAssertGreaterThan(created, 0)
        XCTAssertGreaterThan(size.height, 0)
        for _ in 0..<60 {
            state.setSource(source, streaming: true)
            let fitted = hosting.fittingSize
            XCTAssertTrue(fitted.width.isFinite && fitted.height.isFinite)
            XCTAssertEqual(fitted.width, size.width, accuracy: 0.5)
            XCTAssertEqual(fitted.height, size.height, accuracy: 0.5)
            hosting.layoutSubtreeIfNeeded()
        }
        settle()
        XCTAssertEqual(parses, 0)
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(state.sourceRevision, revision)
        XCTAssertTrue(state.root === original)
        XCTAssertEqual(mounts.created, created)
        XCTAssertEqual(mounts.removed, removed)
        state.complete()
        state.setState("$label", value: .string("A real state edit still reaches the custom component"))
        settle()
        XCTAssertEqual(PropValue.string(try XCTUnwrap(state.root), "text"),
                       "A real state edit still reaches the custom component")
        XCTAssertGreaterThan(publications, 0)
        XCTAssertEqual(mounts.created, created)
    }
}

@MainActor private final class CoreMountLog {
    var created = 0
    var removed = 0
}

private struct CoreMountMarker: NSViewRepresentable {
    let log: CoreMountLog
    func makeCoordinator() -> CoreMountLog { log }
    func makeNSView(context: Context) -> NSView {
        log.created += 1
        return NSView()
    }
    func updateNSView(_ view: NSView, context: Context) {}
    static func dismantleNSView(_ view: NSView, coordinator: CoreMountLog) {
        coordinator.removed += 1
    }
}
#endif
