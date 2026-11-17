import SwiftLang
#if os(macOS)
import AppKit
import Combine
import SwiftUI
import XCTest
@testable import SwiftOpenUI

/// A fixed-width native host exercises fitting without network, Markdown
/// preparation, or client chat-list callbacks. Real client profiling is separate.
final class HostSizingIsolationTests: XCTestCase {
  @MainActor func testRepeatedFittingDoesNotPublishOrReparseStaticContent() throws {
    try checkFitting(replayStreamingBuffer: false)
  }

  @MainActor func testRepeatedStreamingSnapshotAndFittingDoNotRebuildContent() throws {
    try checkFitting(replayStreamingBuffer: true)
  }

  @MainActor private func checkFitting(replayStreamingBuffer: Bool) throws {
    _ = NSApplication.shared
    let mounts = SizingMountLog()
    let standard = try OpenUIComponents.library()
    let definition = try XCTUnwrap(standard.library.components.first { $0.name == "TextContent" })
    let library = try standard.extending(overriding: [OpenUIComponent(definition) { context in
      NativeComponentHost(context: context) { context in
        Text(context.string("text") ?? "")
          .fixedSize(horizontal: false, vertical: true)
          .background(SizingMountMarker(log: mounts))
      }
    }])
    let state = OpenUIState(schema: library.library.toSchema())
    let source = "root=Stack([TextContent(\"Stable prefix\"),TextContent(\"流式内容与尺寸测量保持分离\")])"
    state.setSource(source, streaming: replayStreamingBuffer)
    let hosting = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry).frame(width: 320))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 600),
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
    let expectedSize = hosting.fittingSize
    settle()
    let initialMounts = mounts.created
    let initialRemovals = mounts.removed
    let root = try XCTUnwrap(state.root)
    let revision = state.sourceRevision
    var parses = 0, publications = 0, actions = 0
    state.onParseResult = { _ in parses += 1 }
    state.onAction = { _ in actions += 1 }
    let subscription = state.objectWillChange.sink { publications += 1 }
    defer { subscription.cancel() }

    XCTAssertGreaterThan(initialMounts, 0)
    XCTAssertGreaterThan(expectedSize.height, 0)
    for _ in 0..<100 {
      if replayStreamingBuffer { state.setSource(source, streaming: true) }
      let size = hosting.fittingSize
      XCTAssertTrue(size.width.isFinite && size.height.isFinite)
      XCTAssertEqual(size.width, expectedSize.width, accuracy: 0.5)
      XCTAssertEqual(size.height, expectedSize.height, accuracy: 0.5)
      hosting.layoutSubtreeIfNeeded()
    }
    settle()
    XCTAssertEqual(parses, 0)
    XCTAssertEqual(publications, 0)
    XCTAssertEqual(actions, 0)
    XCTAssertEqual(state.sourceRevision, revision)
    XCTAssertTrue(state.root === root)
    XCTAssertEqual(mounts.created, initialMounts)
    XCTAssertEqual(mounts.removed, initialRemovals)
    // We intentionally do not assert body/layout counts are zero. SwiftUI may
    // probe multiple proposals; fitting must not create new semantic updates.
  }
}

@MainActor private final class SizingMountLog {
  var created = 0
  var removed = 0
}

private enum SizingFailure: Error { case timeout }

private struct SizingMountMarker: NSViewRepresentable {
  let log: SizingMountLog
  func makeCoordinator() -> SizingMountLog { log }
  func makeNSView(context: Context) -> NSView {
    log.created += 1
    return NSView()
  }
  func updateNSView(_ view: NSView, context: Context) {}
  static func dismantleNSView(_ view: NSView, coordinator: SizingMountLog) {
    coordinator.removed += 1
  }
}


extension HostSizingIsolationTests {
  @MainActor func testCompletedMixedLongDocumentKeepsStateAndMountsAcrossFittingAndWidthChanges() async throws {
    _ = NSApplication.shared
    let fixture = try XCTUnwrap(Bundle.module.url(forResource: "mixed-long-document",
      withExtension: "openui", subdirectory: "Fixtures"))
    let source = try String(contentsOf: fixture, encoding: .utf8)
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource(source)
    XCTAssertTrue(state.isComplete)
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")

    // Count reachable language elements by identity, not SwiftUI views. The
    // fixture has no private data, network resources, or asynchronous Queries.
    var visited = Set<ObjectIdentifier>(), composition: [String: Int] = [:]
    func visit(_ value: Value) {
      switch value {
      case .element(let element):
        guard visited.insert(ObjectIdentifier(element)).inserted else { return }
        composition[element.typeName, default: 0] += 1
        for (_, child) in element.props { visit(child) }
      case .array(let values): for child in values { visit(child) }
      case .object(let fields): for field in fields { visit(field.value) }
      default: break
      }
    }
    visit(.element(try XCTUnwrap(state.root)))
    XCTAssertTrue((180...210).contains(visited.count), "Unexpected fixture scale: \(visited.count)")
    for kind in ["Card", "TextContent", "MarkDownRenderer", "Table", "Form", "Input"] {
      XCTAssertGreaterThan(composition[kind, default: 0], 0, "Missing \(kind) workload")
    }

    // Instrument the real TextContent renderer without substituting plain Text.
    let mounts = SizingMountLog()
    var registry = library.registry
    let renderText = try XCTUnwrap(registry["TextContent"])
    registry["TextContent"] = { element, registry in
      AnyView(renderText(element, registry).background(SizingMountMarker(log: mounts)))
    }
    func content(width: CGFloat) -> some View {
      OpenUIContentView(state: state, registry: registry).frame(width: width)
    }
    let hosting = NSHostingView(rootView: content(width: 390))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 844),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = hosting
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close(); state.reset() }
    // Observe geometry convergence while letting native async work progress.
    // This does not establish that every Markdown preparation has completed;
    // the document-specific test below checks that separate contract.
    func settledSize(width: CGFloat) async throws -> CGSize {
      let deadline = Date().addingTimeInterval(8)
      var candidate: CGSize?, stableSince: Date?
      repeat {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let now = Date()
        if size.width.isFinite && size.height.isFinite && size.height > 0
            && abs(size.width - width) <= 0.5 {
          if let candidate, abs(size.width - candidate.width) <= 0.5,
              abs(size.height - candidate.height) <= 0.5 {
            if let stableSince, now.timeIntervalSince(stableSince) >= 0.25 { return size }
          } else {
            candidate = size; stableSince = now
          }
        } else {
          candidate = nil; stableSince = nil
        }
        try await Task.sleep(nanoseconds: 50_000_000)
      } while Date() < deadline
      XCTFail("Long-document fitting did not settle at width \(width): \(hosting.fittingSize)")
      throw SizingFailure.timeout
    }
    _ = try await settledSize(width: 390)
    state.setFieldValue(form: "synthetic-notes", name: "notes", value: .string("Retained local draft"), componentType: "Input")
    let expected = try await settledSize(width: 390)
    let root = try XCTUnwrap(state.root), revision = state.sourceRevision
    let created = mounts.created, removed = mounts.removed
    var parses = 0, publications = 0
    state.onParseResult = { _ in parses += 1 }
    let subscription = state.objectWillChange.sink { publications += 1 }
    defer { state.onParseResult = nil; subscription.cancel() }
    XCTAssertGreaterThan(created, 0)
    XCTAssertTrue(expected.width.isFinite && expected.height.isFinite)
    XCTAssertGreaterThan(expected.height, 0)
    for _ in 0..<8 {
      let size = hosting.fittingSize
      XCTAssertEqual(size.width, expected.width, accuracy: 0.5)
      XCTAssertEqual(size.height, expected.height, accuracy: 0.5)
      hosting.layoutSubtreeIfNeeded()
    }

    hosting.rootView = content(width: 320)
    let narrow = try await settledSize(width: 320)
    XCTAssertEqual(narrow.width, 320, accuracy: 0.5)
    XCTAssertGreaterThan(narrow.height, expected.height, "Long text must respond to the narrower proposal")
    hosting.rootView = content(width: 390)
    let restored = try await settledSize(width: 390)
    XCTAssertEqual(restored.width, expected.width, accuracy: 0.5)
    XCTAssertEqual(restored.height, expected.height, accuracy: 0.5)
    XCTAssertTrue(state.root === root)
    XCTAssertEqual(state.sourceRevision, revision)
    XCTAssertEqual(state.fieldValue(form: "synthetic-notes", name: "notes"), .string("Retained local draft"))
    XCTAssertEqual(parses, 0)
    XCTAssertEqual(publications, 0)
    XCTAssertEqual(mounts.created, created)
    XCTAssertEqual(mounts.removed, removed)

    if let directory = ProcessInfo.processInfo.environment["OPENUI_SNAPSHOT_DIR"] {
      let report: [String: Any] = ["case": "completed-mixed-long-document", "sourceUTF16": source.utf16.count,
        "reachableElementIdentities": visited.count, "componentCounts": composition,
        "wideWidth": expected.width, "wideHeight": expected.height,
        "narrowWidth": narrow.width, "narrowHeight": narrow.height, "restoredHeight": restored.height,
        "sampledTextMounts": created, "additionalParses": parses, "additionalPublications": publications,
        "additionalTextMounts": mounts.created - created, "additionalTextRemovals": mounts.removed - removed,
        "build": _isDebugAssertConfiguration() ? "debug" : "release",
        "note": "Public synthetic host-fitting workload; not a Muse replay, scrolling trace, or SwiftUI view count"]
      try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
      try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        .write(to: URL(fileURLWithPath: directory).appendingPathComponent("mixed-long-document-\(_isDebugAssertConfiguration() ? "debug" : "release").json"))
    }
  }

  @MainActor func testActualMarkdownHostFittingDoesNotRepeatPreparationOrSemanticUpdates() async throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    let document = NativeMarkdownDocument()
    let definition = try XCTUnwrap(library.library.components.first { $0.name == "TextContent" })
    let measured = try library.extending(overriding: [OpenUIComponent(definition) { context in
      NativeComponentHost(context: context) { context in
        MainActor.assumeIsolated { NativeMarkdownText(text: context.string("text") ?? "", document: document) }
      }
    }])
    let text = "## 原生 Markdown 测量\n\n" + String(repeating: "**强调**与普通中文保持稳定。A link is [readable](https://example.com).\n\n", count: 20)
    let literal = String(data: try JSONEncoder().encode(text), encoding: .utf8)!
    let source = "root=TextContent(\(literal))"
    state.setSource(source, streaming: true)
    let hosting = NSHostingView(rootView: OpenUIContentView(state: state, registry: measured.registry).frame(width: 320))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 600),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = hosting
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close(); document.cancel() }
    hosting.layoutSubtreeIfNeeded()
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in document.currentSource == OpenUIString(text) }, object: nil)
    await fulfillment(of: [ready], timeout: 8)
    hosting.layoutSubtreeIfNeeded()
    let expected = hosting.fittingSize
    let preparations = document.preparationCount, fallbacks = document.fallbackParseCount
    var semanticUpdates = 0
    let subscription = state.objectWillChange.sink { semanticUpdates += 1 }
    defer { subscription.cancel() }
    var durations: [Double] = []
    for _ in 0..<100 {
      let start = DispatchTime.now().uptimeNanoseconds
      state.setSource(source, streaming: true)
      let size = hosting.fittingSize
      hosting.layoutSubtreeIfNeeded()
      durations.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
      XCTAssertEqual(size.height, expected.height, accuracy: 0.5)
      XCTAssertEqual(size.width, expected.width, accuracy: 0.5)
    }
    XCTAssertEqual(document.preparationCount, preparations)
    XCTAssertEqual(document.fallbackParseCount, fallbacks)
    XCTAssertEqual(semanticUpdates, 0)
    XCTAssertGreaterThan(expected.height, 0)
    if let directory = ProcessInfo.processInfo.environment["OPENUI_SNAPSHOT_DIR"] {
      let ordered = durations.sorted()
      let report: [String: Any] = ["case": "native-markdown-100-identical-fits", "width": 320,
        "sourceUTF16": text.utf16.count, "count": durations.count, "p50Milliseconds": ordered[49],
        "p95Milliseconds": ordered[94], "maxMilliseconds": ordered.last!,
        "additionalSemanticUpdates": semanticUpdates,
        "additionalPreparations": document.preparationCount - preparations,
        "additionalFallbackParses": document.fallbackParseCount - fallbacks,
        "build": _isDebugAssertConfiguration() ? "debug" : "release",
        "note": "SDK native-host fitting probe, not a client FPS or Instruments trace"]
      try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
      try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        .write(to: URL(fileURLWithPath: directory).appendingPathComponent("markdown-fitting-\(_isDebugAssertConfiguration() ? "debug" : "release").json"))
    }
  }
}
#endif
