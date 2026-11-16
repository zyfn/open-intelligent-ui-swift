import SwiftLang
#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import SwiftOpenUI

/// Exercises the actual plain Text and MarkdownUI presentation in a mounted
/// native host. Accessibility text comes from rendered controls, not a source
/// probe or an injected label. This is not a client replay or a frame-time test.
final class MountedStreamingTextProgressTests: XCTestCase {
    @MainActor func testMountedPlainAndMarkdownTextAdvanceBeforeUnrelatedStreamingEnds() async throws {
        _ = NSApplication.shared
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        state.push("root=Stack([CardHeader(\"SHANGHAI → SUZH")
        let host = NSHostingView(rootView: ScrollView {
            OpenUIContentView(state: state, registry: library.registry)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.frame(width: 390, height: 600))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }

        try await waitForRenderedText("SHANGHAI → SUZH", in: host)
        state.push("OU\"),TextContent(\"旅行成员共 3 位成")
        try await waitForRenderedText("旅行成员共 3 位成", in: host)
        let title = "SHANGHAI → SUZHOU"
        let paragraph = "旅行成员共 3 位成人，路线已经全部确定。"
        state.push("人，路线已经全部确定。\"),")
        let children = PropValue.children(try XCTUnwrap(state.root))
        XCTAssertEqual(children.count, 2)
        guard children.count == 2 else { return }
        XCTAssertEqual(PropValue.string(children[0], "title"), title)
        XCTAssertEqual(PropValue.string(children[1], "text"), paragraph,
            "The target field is complete before unrelated nodes keep arriving")

        let revision = state.presentationRevision
        var titleVisibleAt: Int?, paragraphVisibleAt: Int?
        // Yield between real chunks. A synchronous 100-call burst followed by
        // a final wait would not test progress while input is still arriving.
        for chunk in 1...100 {
            state.push("TextContent(\"后续节点 \(chunk)\"),")
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 30_000_000)
            host.layoutSubtreeIfNeeded()
            let rendered = renderedText(in: host)
            if rendered.contains(title), titleVisibleAt == nil { titleVisibleAt = chunk }
            if rendered.contains(paragraph), paragraphVisibleAt == nil { paragraphVisibleAt = chunk }
            XCTAssertFalse(state.isComplete, "Progress must be observable before done")
            if chunk == 50 {
                XCTAssertNotNil(titleVisibleAt, "The plain heading stayed stale during continued input")
                XCTAssertNotNil(paragraphVisibleAt, "Markdown stayed at an old prefix during continued input")
            }
        }
        XCTAssertNotNil(titleVisibleAt)
        XCTAssertNotNil(paragraphVisibleAt)
        XCTAssertEqual(state.presentationRevision, revision, "Streaming must not replace the presentation")
        XCTAssertTrue(state.errors.isEmpty)
        // Terminal correctness remains a separate assertion, not the progress
        // oracle. The assertions above execute while the producer is active.
        state.push("])")
        state.complete()
        try await waitForRenderedText(paragraph, in: host)
    }

    @MainActor private func waitForRenderedText(_ text: String, in host: NSView) async throws {
        let deadline = Date().addingTimeInterval(3)
        repeat {
            host.layoutSubtreeIfNeeded()
            if renderedText(in: host).contains(text) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        } while Date() < deadline
        XCTFail("Mounted accessibility text did not contain \(text); got \(renderedText(in: host))")
    }

    @MainActor private func renderedText(in host: NSView) -> String {
        var visited = Set<ObjectIdentifier>(), text: [String] = []
        // These are public AppKit accessibility getter selectors. Dynamic
        // dispatch also covers SwiftUI accessibility elements without relying
        // on their private classes or on SDK-dependent protocol import names.
        let label = NSSelectorFromString("accessibilityLabel")
        let value = NSSelectorFromString("accessibilityValue")
        let children = NSSelectorFromString("accessibilityChildren")
        func read(_ object: NSObject, _ selector: Selector) -> AnyObject? {
            object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
        }
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 128, visited.count < 8_192,
                  visited.insert(ObjectIdentifier(object)).inserted else { return }
            for content in [read(object, label), read(object, value)].compactMap({ $0 }) {
                if let string = content as? String { text.append(string) }
                else if let attributed = content as? NSAttributedString { text.append(attributed.string) }
            }
            let accessible = read(object, children) as? [Any] ?? []
            for child in accessible {
                if let child = child as? NSObject { visit(child, depth: depth + 1) }
            }
            if accessible.isEmpty, let view = object as? NSView {
                for child in view.subviews { visit(child, depth: depth + 1) }
            }
        }
        visit(host, depth: 0)
        return text.joined(separator: "\n")
    }
}
#endif
