import SwiftLang
#if os(macOS)
import AppKit
import Combine
import SwiftUI
import XCTest
@testable import SwiftOpenUI

/// Exercises mounted native Text and MarkdownUI controls, including their actual accessibility
/// text. Source probes alone cannot detect a view that missed its last update.
/// These regressions are not client replay or frame-time measurements.
final class MountedStreamingTextProgressTests: XCTestCase {
    @MainActor func testStandardMarkdownBuilderStaysStableWhileAnotherTextStreams() async throws {
        let library = try OpenUIComponents.library()
        var registry = library.registry
        let original = try XCTUnwrap(registry["TextContent"])
        // Wrap the actual standard renderer and preserve all of its registration
        // metadata; this test does not replace Markdown with a probe component.
        let placeholder = registry.supportsPresentationPlaceholder("TextContent")
        let layout = registry.presentationLayoutFields("TextContent")
        let labels = registry.ownsFormControlLabel("TextContent")
        let identity = registry.identityFields(for: "TextContent")
        let placeholderFields = registry.presentationPlaceholderFields("TextContent")
        var fixedBuilds = 0
        registry["TextContent"] = { element, registry in
            if element.statementId == "fixed" { fixedBuilds += 1 }
            return original(element, registry)
        }
        registry.setPresentationPlaceholder("TextContent", enabled: placeholder)
        registry.setLayoutFields("TextContent", fields: layout)
        registry.setFormControlLabelOwner("TextContent", enabled: labels)
        registry.setIdentityFields("TextContent", fields: identity)
        registry.setPlaceholderFields("TextContent", fields: placeholderFields)
        let state = OpenUIState(schema: library.library.toSchema())
        defer { state.reset() }
        state.push("root=Stack([fixed,tail])\nfixed=TextContent(\"稳定的正文段落\")\ntail=TextContent(\"")
        let (host, window) = mount(OpenUIContentView(state: state, registry: registry))
        defer { window.close() }
        try await waitForRenderedText("稳定的正文段落", in: host)
        XCTAssertGreaterThan(fixedBuilds, 0)
        let settledBuilds = fixedBuilds
        var text = ""
        for chunk in ["SHANGHAI", " → ", "SUZHOU", " · 2 DAYS", " · 3 位成人"] {
            text += chunk
            state.push(chunk)
            try await waitForRenderedText(text, in: host)
            XCTAssertFalse(state.isComplete)
            XCTAssertEqual(fixedBuilds, settledBuilds,
                "The registered standard Markdown renderer must not rebuild for an unrelated text append")
            XCTAssertTrue(renderedText(in: host).contains("稳定的正文段落"))
        }
        state.push("\")")
        state.complete()
        try await waitForRenderedText(text, in: host)
    }

    @MainActor func testMountedPlainAndMarkdownTextAdvanceBeforeUnrelatedStreamingEnds() async throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        state.push("root=Stack([CardHeader(\"SHANGHAI → SUZH")
        let (host, window) = mount(ScrollView {
            OpenUIContentView(state: state, registry: library.registry)
                .frame(maxWidth: .infinity, alignment: .leading)
        })
        defer { window.close() }

        try await waitForRenderedText("SHANGHAI → SUZH", in: host)
        state.push("OU · 2 DAYS\"),TextContent(\"旅行成员共 3 位成")
        try await waitForRenderedText("旅行成员共 3 位成", in: host)
        let title = "SHANGHAI → SUZHOU · 2 DAYS"
        let paragraph = "旅行成员共 3 位成人，路线已经全部确定。"
        state.push("人，路线已经全部确定。\"),")
        let children = PropValue.children(try XCTUnwrap(state.root))
        XCTAssertEqual(children.count, 2)
        guard children.count == 2 else { return }
        XCTAssertEqual(PropValue.string(children[0], "title"), title)
        XCTAssertEqual(PropValue.string(children[1], "text"), paragraph,
            "Both target fields must be complete before unrelated input arrives")

        let revision = state.presentationRevision
        var settledDuringStream = false
        // Yield between real chunks. One synchronous burst followed by done
        // would allow terminal rendering to hide a missed source delivery.
        for chunk in 1...100 {
            state.push("TextContent(\"后续节点 \(chunk)\"),")
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 30_000_000)
            host.layoutSubtreeIfNeeded()
            let rendered = renderedText(in: host)
            let completeTextVisible = rendered.contains(title) && rendered.contains(paragraph)
            XCTAssertFalse(state.isComplete, "The producer must remain active")
            if chunk == 50 {
                settledDuringStream = completeTextVisible
                XCTAssertTrue(completeTextVisible,
                    "Completed fields stayed at old prefixes while unrelated nodes arrived: \(rendered)")
            } else if chunk > 50, settledDuringStream, !completeTextVisible {
                XCTFail("Completed text regressed after settling while only unrelated nodes changed: \(rendered)")
                return
            }
        }
        XCTAssertEqual(state.presentationRevision, revision,
            "Streaming must preserve the presentation identity")
        XCTAssertTrue(state.errors.isEmpty)
        // Completion is a separate check; it cannot satisfy the assertion
        // above, which runs while the stream is still active.
        state.push("])")
        state.complete()
        try await waitForRenderedText(paragraph, in: host)
    }

    @MainActor func testMountedInputChangesDeliverLatestSourceAndStreamingState() async throws {
        // The first case isolates a source-only update. The other two change
        // source and status in one render, with the same mounted view identity.
        for (before, after) in [(true, true), (true, false), (false, true)] {
            let prefix = before && after ? "SHANGHAI → SUZH" : "行程 👩🏽‍💻 Cafe\u{301}"
            let complete = prefix + (before && after ? "OU · 2 DAYS" : " → 苏州 · 3 位成人")
            let model = MountedTextModel(source: prefix, streaming: before)
            let scheduler = MountedTextScheduler()
            let buffer = NativeStreamingTextBuffer(schedule: scheduler.schedule)
            let document = NativeMarkdownDocument()
            let (host, window) = mount(MountedTextHarness(model: model, buffer: buffer, document: document))
            defer { window.close(); document.cancel(); buffer.cancel() }

            try await waitFor("initial text preparation", in: host) {
                buffer.displayed.map { OpenUIString($0) } == OpenUIString(prefix)
                    && document.currentSource == OpenUIString(prefix)
            }
            try await waitForRenderedText(prefix, in: host)
            XCTAssertEqual(scheduler.deliveryCount, 0)

            // A single Published value prevents the test harness from creating
            // an intermediate old-source/new-status or new-source/old-status frame.
            model.input = .init(source: complete, streaming: after)
            if after {
                try await waitFor("one coalesced delivery for the new source", in: host) {
                    scheduler.deliveryCount == 1
                }
                XCTAssertEqual(buffer.displayed.map { OpenUIString($0) }, OpenUIString(prefix),
                    "An active append must keep its normal coalescing interval")
                scheduler.fire(0)
            }
            try await waitFor("latest source in both buffer and prepared document", in: host) {
                buffer.displayed.map { OpenUIString($0) } == OpenUIString(complete)
                    && document.currentSource == OpenUIString(complete)
            }
            try await waitForRenderedText(complete, in: host)
            XCTAssertEqual(scheduler.deliveryCount, after ? 1 : 0,
                "A terminal update must flush without starting a streaming timer")

            // Checking only the first full accessibility value can pass on a
            // synchronous fallback before an older prepared value arrives.
            // Require actual preparation first, then retain it across renders
            // that change neither the target text nor its streaming status.
            for revision in 1...3 {
                model.unrelatedRevision = revision
                try await waitForRenderedText("Unrelated \(revision)", in: host)
                XCTAssertEqual(buffer.displayed.map { OpenUIString($0) }, OpenUIString(complete))
                XCTAssertEqual(document.currentSource, OpenUIString(complete))
                XCTAssertTrue(renderedText(in: host).contains(complete))
            }
            XCTAssertEqual(model.appearances, 1, "Remounting must not repair a missed onChange")
            XCTAssertEqual(model.disappearances, 0)
        }
    }

    @MainActor func testMountedFinalChunkAndCompleteKeepLatestText() async throws {
        try await checkFinalChunk(interrupted: false)
    }

    @MainActor func testMountedFinalChunkAndInterruptKeepLatestText() async throws {
        try await checkFinalChunk(interrupted: true)
    }

    @MainActor private func checkFinalChunk(interrupted: Bool) async throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        let prefix = "家庭 👨‍👩‍👧，2 位成"
        let complete = prefix + "人，行程已确认。"
        state.push("root=TextContent(\"\(prefix)")
        let (host, window) = mount(OpenUIContentView(state: state, registry: library.registry))
        defer { window.close() }
        try await waitForRenderedText(prefix, in: host)

        // No suspension between the last source chunk and the terminal event.
        // The existing public SDK API must deliver this combined transition.
        state.push("人，行程已确认。\")")
        if interrupted { state.interrupt() } else { state.complete() }
        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(state.isInterrupted, interrupted)
        XCTAssertEqual(PropValue.string(try XCTUnwrap(state.root), "text"), complete)
        try await waitForRenderedText(complete, in: host)
        XCTAssertTrue(state.errors.isEmpty)
    }

    @MainActor private func mount<Content: View>(_ content: Content) -> (NSHostingView<AnyView>, NSWindow) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: AnyView(content.frame(width: 390, height: 600, alignment: .topLeading)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        return (host, window)
    }

    @MainActor private func waitForRenderedText(_ text: String, in host: NSView) async throws {
        try await waitFor("rendered text containing \(text)", in: host) {
            self.renderedText(in: host).contains(text)
        }
    }

    @MainActor private func waitFor(_ description: String, in host: NSView,
        condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            host.layoutSubtreeIfNeeded()
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        } while Date() < deadline
        XCTFail("Timed out waiting for \(description); rendered text: \(renderedText(in: host))")
        throw MountedTextFailure.timeout
    }

    @MainActor private func renderedText(in host: NSView) -> String {
        var visited = Set<ObjectIdentifier>(), text: [String] = []
        // Public AppKit accessibility getters also cover SwiftUI elements;
        // no source value is injected into their labels for this test.
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

private enum MountedTextFailure: Error { case timeout }

@MainActor private final class MountedTextModel: ObservableObject {
    struct Input {
        let source: String
        let streaming: Bool
    }
    @Published var input: Input
    @Published var unrelatedRevision = 0
    var appearances = 0
    var disappearances = 0

    init(source: String, streaming: Bool) {
        input = .init(source: source, streaming: streaming)
    }
}

@MainActor private struct MountedTextHarness: View {
    @ObservedObject var model: MountedTextModel
    let buffer: NativeStreamingTextBuffer
    let document: NativeMarkdownDocument

    var body: some View {
        VStack(alignment: .leading) {
            NativeMarkdownText(text: model.input.source, mode: .textContent,
                streamText: buffer, document: document)
                .environment(\.openUIStreamActive, model.input.streaming)
                .onAppear { model.appearances += 1 }
                .onDisappear { model.disappearances += 1 }
            Text("Unrelated \(model.unrelatedRevision)")
        }
    }
}

@MainActor private final class MountedTextScheduler {
    private var deliveries: [@MainActor () -> Void] = []
    private var cancelled = Set<Int>()
    var deliveryCount: Int { deliveries.count }

    func schedule(_ delivery: @escaping @MainActor () -> Void) -> NativeStreamingTextBuffer.Cancellation {
        let index = deliveries.count
        deliveries.append(delivery)
        return { [weak self] in self?.cancelled.insert(index) }
    }

    func fire(_ index: Int) {
        guard deliveries.indices.contains(index), !cancelled.contains(index) else { return }
        deliveries[index]()
    }
}
#endif
