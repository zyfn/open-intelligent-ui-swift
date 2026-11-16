import SwiftLang
#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class BoundaryIdentityTests: XCTestCase {
  @MainActor func testUnavailableUpdateKeepsTheMountedLastGoodView() throws {
    _ = NSApplication.shared
    let input = BoundaryInput()
    let hosting = NSHostingView(rootView: BoundaryTestSurface(input: input))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 100),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close() }
    func settle() {
      hosting.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    func marker(_ view: NSView) -> NSView? {
      if view.identifier?.rawValue == "boundary.mount" { return view }
      return view.subviews.lazy.compactMap(marker).first
    }
    settle()
    let first = try XCTUnwrap(marker(hosting))
    input.element = nil
    settle()
    XCTAssertTrue(marker(hosting) === first, "Fallback must keep the loaded native subtree, not create a second branch")
    input.element = EvaluatedElement(typeName: "TextContent", props: [("text", .string("Later"))])
    settle()
    XCTAssertTrue(marker(hosting) === first)
  }

  @MainActor func testFallbackRetainsTheLatestReadinessOnlySnapshot() throws {
    _ = NSApplication.shared
    let input = BoundaryInput()
    let pending = EvaluatedElement(typeName: "TextContent", props: [("text", .string("Same"))], isSourceComplete: false)
    let ready = EvaluatedElement(typeName: "TextContent", props: pending.props, isSourceComplete: true)
    XCTAssertEqual(pending, ready, "Language equality deliberately excludes native readiness")
    input.element = pending
    let hosting = NSHostingView(rootView: BoundaryReadinessSurface(input: input))
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 240, height: 100),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = hosting; window.orderFront(nil)
    defer { window.close() }
    func settle() {
      hosting.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      hosting.layoutSubtreeIfNeeded()
    }
    func marker(_ view: NSView) -> BoundaryReadinessView? {
      if let view = view as? BoundaryReadinessView { return view }
      return view.subviews.lazy.compactMap(marker).first
    }
    settle()
    let mounted = try XCTUnwrap(marker(hosting))
    XCTAssertTrue(mounted.element === pending)
    input.element = ready
    settle()
    XCTAssertTrue(mounted.element === ready)
    // Let the new input finish onChange before testing its retained fallback.
    settle()
    input.element = nil
    settle()
    XCTAssertTrue(marker(hosting) === mounted)
    XCTAssertTrue(mounted.element === ready)
    XCTAssertTrue(try XCTUnwrap(mounted.element).isSourceComplete)
  }
}
@MainActor private final class BoundaryInput: ObservableObject {
  @Published var element: EvaluatedElement? = EvaluatedElement(typeName: "TextContent")
}
private struct BoundaryTestSurface: View {
  @ObservedObject var input: BoundaryInput
  var body: some View { ElementErrorBoundary(element: input.element) { _ in BoundaryMarker() } }
}
private struct BoundaryMarker: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView(); view.identifier = NSUserInterfaceItemIdentifier("boundary.mount"); return view
  }
  func updateNSView(_ view: NSView, context: Context) {}
}

private struct BoundaryReadinessSurface: View {
  @ObservedObject var input: BoundaryInput
  var body: some View {
    ElementErrorBoundary(element: input.element) { BoundaryReadinessMarker(element: $0) }
  }
}
private final class BoundaryReadinessView: NSView {
  var element: EvaluatedElement?
}
private struct BoundaryReadinessMarker: NSViewRepresentable {
  let element: EvaluatedElement
  func makeNSView(context: Context) -> BoundaryReadinessView { BoundaryReadinessView() }
  func updateNSView(_ view: BoundaryReadinessView, context: Context) { view.element = element }
}
#endif
