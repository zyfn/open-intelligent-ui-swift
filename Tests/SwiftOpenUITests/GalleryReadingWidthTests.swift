import SwiftLang
#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class GalleryReadingWidthTests: XCTestCase {
  @MainActor private func height(_ source: String, width: CGFloat, streaming: Bool = false,
    sizeClass: UserInterfaceSizeClass = .compact, typeSize: DynamicTypeSize = .large,
    viewportHeight: CGFloat? = nil) throws -> CGFloat {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    if streaming { state.push(source) } else { state.setSource(source) }
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    var presentation = OpenUIPresentation()
    presentation.viewportHeight = viewportHeight
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .openUIPresentation(presentation)
      .environment(\.dynamicTypeSize, typeSize).environment(\.horizontalSizeClass, sizeClass).frame(width: width))
    let window = NSWindow(contentRect: .init(x: -10000, y: -10000, width: width, height: 1400),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
    defer { window.close() }
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    return host.fittingSize.height
  }

  @MainActor func testThreePhotoPreviewMatchesTheCoverHeightAndFitsItsViewport() throws {
    let source = "root=Stack([ImageGallery([{src:\"\",alt:\"A\"},{src:\"\",alt:\"B\"},{src:\"\",alt:\"C\"}])])"
    // Validate the real registered renderer, not just the generic grid helper.
    for width in [CGFloat(280), 390, 600] {
      let expected = width * 9 / 16
      XCTAssertEqual(try height(source, width: width), expected, accuracy: 1)
      XCTAssertEqual(try height(source, width: width, sizeClass: .regular), expected, accuracy: 1)
    }
    XCTAssertEqual(try height(source, width: 350, typeSize: .accessibility3),
      350 * 9 / 16, accuracy: 1,
      "The accessible inline preview fits one full-width image within the same height budget")
    XCTAssertEqual(try height(source, width: 350, viewportHeight: 120), 120, accuracy: 1)
  }

  @MainActor func testClosedGalleryReservesItsFinalHeightBeforeReferencesResolve() throws {
    let prefix = "root=Stack([ImageGallery([a,b,c])])\n"
    let third = "c={src:\"\",alt:\"C\"}\n"
    let completed = prefix + third + "a={src:\"\",alt:\"A\"}\nb={src:\"\",alt:\"B\"}\n"
    for sizeClass in [UserInterfaceSizeClass.compact, .regular] {
      let finalHeight = try height(completed, width: 390, sizeClass: sizeClass, viewportHeight: 568)
      XCTAssertEqual(try height(prefix, width: 390, streaming: true, sizeClass: sizeClass, viewportHeight: 568),
        finalHeight, accuracy: 1)
      XCTAssertEqual(try height(prefix + third, width: 390, streaming: true, sizeClass: sizeClass, viewportHeight: 568),
        finalHeight, accuracy: 1)
    }
  }

  @MainActor func testDetailsDoNotChangeTheInlineGalleryGeometry() throws {
    let source = "root=Stack([ImageGallery([{src:\"\",alt:\"A\",details:\"完整的第一张图片说明\"},{src:\"\",alt:\"B\",details:\"第二张图片的背景说明\"},{src:\"\",alt:\"C\",details:\"第三张图片的补充说明\"}])])"
    let uncaptioned = "root=Stack([ImageGallery([{src:\"\",alt:\"A\"},{src:\"\",alt:\"B\"},{src:\"\",alt:\"C\"}])])"
    for width in [CGFloat(280), 350] {
      XCTAssertEqual(try height(source, width: width), try height(uncaptioned, width: width), accuracy: 1)
    }
    XCTAssertEqual(try height(source, width: 350, typeSize: .accessibility3),
      try height(uncaptioned, width: 350, typeSize: .accessibility3), accuracy: 1)
  }

  @MainActor func testInlinePreviewAllocatesOnlyItsFiveVisibleSlotsWhileReferencesArrive() throws {
    let completed = "root=Stack([ImageGallery([{src:\"\",alt:\"A\"},{src:\"\",alt:\"B\"},{src:\"\",alt:\"C\"},{src:\"\",alt:\"D\"},{src:\"\",alt:\"E\"}])])"
    let partial = "root=Stack([ImageGallery([a,b,c,d,e,f])])\na={src:\"\",alt:\"A\"}\n"
    XCTAssertEqual(try height(partial, width: 800, streaming: true, sizeClass: .regular),
      try height(completed, width: 800, sizeClass: .regular), accuracy: 1,
      "Future records outside the five-photo preview must not make the first visible photo narrower")
  }

  @MainActor func testShowAllOverlayDoesNotAddRowsToTheInlinePreview() throws {
    func source(_ count: Int) -> String {
      let images = (1...count).map { "{src:\"\",alt:\"Photo \($0)\"}" }.joined(separator: ",")
      return "root=Stack([ImageGallery([\(images)])])"
    }
    let five = try height(source(5), width: 240)
    XCTAssertEqual(try height(source(6), width: 240), five, accuracy: 1)
    XCTAssertEqual(try height(source(9), width: 240), five, accuracy: 1,
      "The Show All overlay preserves the five-photo collage's height")
  }

  @MainActor func testNarrowGalleryUsesOneCoverAndKeepsAccessToTheCollection() async throws {
    _ = NativeAccessibilityTestSupport.application
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("""
      root=Stack([ImageGallery([{src:"",alt:"First"},{src:"",alt:"Second"},{src:"",alt:"Third"},{src:"",alt:"Fourth"}])])
      """)
    var presentation = OpenUIPresentation()
    presentation.minimumControlTargetSize = 44
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .openUIPresentation(presentation).frame(width: 160))
    let window = NSWindow(contentRect: .init(x: -10000, y: -10000, width: 160, height: 300),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer { window.close() }
    try await NativeAccessibilityTestSupport.activate(in: host)
    let ids = NativeAccessibilityTestSupport.elements(in: host).compactMap {
      NativeAccessibilityTestSupport.stringAttribute("accessibilityIdentifier", of: $0)
    }
    XCTAssertEqual(Set(ids.filter { $0.hasPrefix("openui.gallery.image.") }), ["openui.gallery.image.0"])
    XCTAssertTrue(ids.contains("openui.gallery.showAll"))
  }
}
#endif
