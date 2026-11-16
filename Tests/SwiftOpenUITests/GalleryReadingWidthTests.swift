import SwiftLang
#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class GalleryReadingWidthTests: XCTestCase {
  @MainActor private func height(_ source: String, width: CGFloat, streaming: Bool = false,
    typeSize: DynamicTypeSize = .large) throws -> CGFloat {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    if streaming { state.push(source) } else { state.setSource(source) }
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .environment(\.dynamicTypeSize, typeSize).frame(width: width))
    let window = NSWindow(contentRect: .init(x: -10000, y: -10000, width: width, height: 1400),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
    defer { window.close() }
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    return host.fittingSize.height
  }

  @MainActor func testPhotoOnlyGalleryUsesThumbnailWidthsAcrossNarrowContainers() throws {
    let source = "root=Stack([ImageGallery([{src:\"\",alt:\"A\"},{src:\"\",alt:\"B\"},{src:\"\",alt:\"C\"}])])"
    // Validate the real registered renderer, not just the generic grid helper.
    XCTAssertEqual(try height(source, width: 350), 169 * 9 / 16 * 2 + 12, accuracy: 1)
    XCTAssertEqual(try height(source, width: 280), 134 * 9 / 16 * 2 + 12, accuracy: 1)
    XCTAssertEqual(try height(source, width: 530), (530 - 24) / 3 * 9 / 16, accuracy: 1)
    XCTAssertEqual(try height(source, width: 240), 114 * 9 / 16 * 2 + 12, accuracy: 1)
    XCTAssertEqual(try height(source, width: 200), 200 * 9 / 16 * 3 + 24, accuracy: 1)
    XCTAssertEqual(try height(source, width: 280, typeSize: .accessibility3),
      try height(source, width: 280), accuracy: 1,
      "Font preferences must not turn a captionless photo preview into full-width text cards")
  }

  @MainActor func testCaptionedGalleryRetainsReadingWidthAndAccessibilityReflow() throws {
    let source = "root=Stack([ImageGallery([{src:\"\",alt:\"A\",details:\"完整的第一张图片说明\"},{src:\"\",alt:\"B\",details:\"第二张图片的背景说明\"},{src:\"\",alt:\"C\",details:\"第三张图片的补充说明\"}])])"
    let regular = try height(source, width: 350)
    let narrow = try height(source, width: 280)
    XCTAssertGreaterThan(narrow, 280 * 9 / 16 * 3 + 24,
      "Captions retain their own height below full-width photos when reading columns no longer fit")
    XCTAssertGreaterThan(narrow, regular)
    XCTAssertGreaterThan(try height(source, width: 350, typeSize: .accessibility3),
      350 * 9 / 16 * 3 + 24,
      "Captioned galleries use a complete reading column at accessibility sizes")
  }

  @MainActor func testInlinePreviewAllocatesOnlyItsFiveVisibleSlotsWhileReferencesArrive() throws {
    let completed = "root=Stack([ImageGallery([{src:\"\",alt:\"A\"},{src:\"\",alt:\"B\"},{src:\"\",alt:\"C\"},{src:\"\",alt:\"D\"},{src:\"\",alt:\"E\"}])])"
    let partial = "root=Stack([ImageGallery([a,b,c,d,e,f])])\na={src:\"\",alt:\"A\"}\n"
    XCTAssertEqual(try height(partial, width: 1200, streaming: true), try height(completed, width: 1200), accuracy: 1,
      "Future records outside the five-photo preview must not make the first visible photo narrower")
  }

  @MainActor func testAdditionalImagesKeepOneAllPhotosEntryWithoutExpandingThePreview() throws {
    func source(_ count: Int) -> String {
      let images = (1...count).map { "{src:\"\",alt:\"Photo \($0)\"}" }.joined(separator: ",")
      return "root=Stack([ImageGallery([\(images)])])"
    }
    // Only photos beyond the five inline slots need a separate entry. It must
    // remain reachable even when all visible sources are unavailable.
    let five = try height(source(5), width: 240)
    let six = try height(source(6), width: 240)
    XCTAssertEqual(six - five,
      OpenUIThemeValues().spaceM + OpenUIPresentation().minimumControlTargetSize, accuracy: 1)
    XCTAssertEqual(try height(source(9), width: 240), six, accuracy: 1,
      "Additional photos belong in the viewer, not extra inline rows or controls")
  }
}
#endif
