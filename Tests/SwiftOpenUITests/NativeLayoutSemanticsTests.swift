import SwiftLang
import SwiftUI
import XCTest
@testable import SwiftOpenUI
#if os(macOS)
import AppKit
#endif

final class NativeLayoutSemanticsTests: XCTestCase {
  func testKnownCollectionShapeKeepsTheFirstCardWidthAsReferencesArrive() {
    let first = NativePagerGeometry(width: 320, count: 1, selected: 0,
      maximumPageWidth: 320, minimumPageWidth: 240, peek: 32, spacing: 12, layoutCount: 4)
    let complete = NativePagerGeometry(width: 320, count: 4, selected: 0,
      maximumPageWidth: 320, minimumPageWidth: 240, peek: 32, spacing: 12)
    XCTAssertEqual(first.pageWidth, complete.pageWidth)
    XCTAssertEqual(first.offset, 0, "Unresolved items must not become scrollable pages")
    let grid = NativeCardGrid(maxPerRow: 2, responsive: true, singleColumn: false, spacing: 12)
    let initial = grid.frames(width: 600, count: 4, visibleCount: 1) { index, _ in index == 0 ? 180 : 0 }
    let final = grid.frames(width: 600, count: 4) { _, _ in 180 }
    XCTAssertEqual(initial.first?.width, final.first?.width)
    XCTAssertEqual(initial.first?.height, final.first?.height)
    XCTAssertLessThan(initial.count, 4, "Do not allocate invisible future rows")
  }

  func testWrappedFlexChildrenShareAvailableRowsWithoutResizingIntrinsicControls() {
    let cards = OpenUIWrappedFlexRows.allocate(ideal: [80, 260], minimums: [32, 32],
      growing: [true, true], width: 350, gap: 12)
    XCTAssertEqual(cards.count, 1)
    XCTAssertEqual(cards[0].map(\.width), [169, 169])
    let mixed = OpenUIWrappedFlexRows.allocate(ideal: [80, 260, 280], minimums: [80, 32, 280],
      growing: [false, true, false], width: 350, gap: 12)
    XCTAssertEqual(mixed.count, 2)
    XCTAssertEqual(mixed[0].map(\.width), [80, 258])
    XCTAssertEqual(mixed[1].map(\.width), [280])
    let bounded = OpenUIWrappedFlexRows.allocate(ideal: [240, 90], minimums: [220, 32],
      growing: [true, true], width: 350, gap: 12)
    XCTAssertEqual(bounded[0].map(\.width), [220, 118])
  }

  func testPagerHeightUsesTheTallestFinitePage() {
    XCTAssertEqual(NativePagerContentHeight.measure([40, 240, 80]), 240)
    XCTAssertEqual(NativePagerContentHeight.measure([.nan, -2, .infinity]), 0)
  }

  func testCarouselNavigationFollowsTheVisibleTrackRatherThanTheItemCount() {
    func layout(_ width: CGFloat, _ count: Int, _ selected: Int) -> NativePagerGeometry {
      NativePagerGeometry(width: width, count: count, selected: selected,
        maximumPageWidth: 320, minimumPageWidth: 240, peek: 32, spacing: 12)
    }
    let narrow = layout(350, 3, 0)
    XCTAssertEqual(narrow.pageWidth, 306)
    XCTAssertEqual(narrow.stride, 318)
    XCTAssertNil(narrow.previousIndex)
    XCTAssertEqual(narrow.nextIndex, 1)
    let last = layout(350, 3, 2)
    XCTAssertEqual(last.offset, last.maximumOffset)
    XCTAssertEqual(last.previousIndex, 1)
    XCTAssertNil(last.nextIndex)

    let wideEnd = layout(900, 3, 2)
    XCTAssertEqual(wideEnd.offset, 84)
    XCTAssertEqual(wideEnd.previousIndex, 0,
      "Index 1 has the same final offset; previous must move the actual track")
    XCTAssertNil(wideEnd.nextIndex)
    for (width, count) in [(CGFloat(350), 1), (1000, 3), (350, 0)] {
      let fitting = layout(width, count, 0)
      XCTAssertEqual(fitting.maximumOffset, 0)
      XCTAssertNil(fitting.previousIndex)
      XCTAssertNil(fitting.nextIndex, "Fully visible cards must not advertise another scroll step")
    }
  }

  func testEveryCarouselNavigationTargetMovesInTheRequestedDirection() {
    for width in [CGFloat(180), 240, 320, 333.3, 650, 781.123, 900, 1200] {
      for count in 1...6 {
        func layout(_ selected: Int) -> NativePagerGeometry {
          NativePagerGeometry(width: width, count: count, selected: selected,
            maximumPageWidth: 320, minimumPageWidth: 240, peek: 32, spacing: 12)
        }
        for selected in 0..<count {
          let current = layout(selected)
          XCTAssertLessThanOrEqual(current.pageWidth, width)
          XCTAssertEqual(current.previousIndex != nil, current.offset > 0)
          XCTAssertEqual(current.nextIndex != nil, current.offset < current.maximumOffset)
          if let previous = current.previousIndex {
            XCTAssertLessThan(layout(previous).offset, current.offset)
          }
          if let next = current.nextIndex {
            XCTAssertGreaterThan(layout(next).offset, current.offset)
          }
        }
      }
    }
  }

  func testFullWidthPagerKeepsItsExistingPageAllocationAndNavigation() {
    for selected in 0..<3 {
      let layout = NativePagerGeometry(width: 350, count: 3, selected: selected,
        maximumPageWidth: nil, minimumPageWidth: 240, peek: 0, spacing: 0)
      XCTAssertEqual(layout.pageWidth, 350)
      XCTAssertEqual(layout.offset, CGFloat(selected) * 350)
      XCTAssertEqual(layout.previousIndex, selected > 0 ? selected - 1 : nil)
      XCTAssertEqual(layout.nextIndex, selected < 2 ? selected + 1 : nil)
    }
  }

  func testGalleryThreeImageArrangementKeepsOneCoverHeightAndBalancedTileProportions() {
    for isCompact in [true, false] {
      let layout = NativeGalleryGridLayout(isCompact: isCompact, fallbackWidth: 160, gap: 1, aspectRatio: 16.0 / 9)
      for width in [CGFloat(280), 390, 600] {
        let frames = layout.frames(width: width, count: 3)
        XCTAssertEqual(frames[0].width, 2 * frames[1].width, accuracy: 0.001)
        XCTAssertEqual(frames[1].minY, 0)
        XCTAssertEqual(frames[1].minX, frames[2].minX)
        XCTAssertEqual(frames[1].maxY + 1, frames[2].minY, accuracy: 0.001)
        XCTAssertEqual(frames[0].maxY, frames[2].maxY, accuracy: 0.001)
        XCTAssertEqual(frames[2].maxY, width * 9 / 16, accuracy: 0.001)
        XCTAssertEqual(frames[2].maxX, width, accuracy: 0.001)
      }
    }
  }

  func testGalleryBoundsEveryTemplateToTheAvailableViewport() {
    for isCompact in [true, false] {
      let tall = NativeGalleryGridLayout(isCompact: isCompact, fallbackWidth: 160,
        gap: 1, aspectRatio: 16.0 / 9, viewportHeight: 844)
      let short = NativeGalleryGridLayout(isCompact: isCompact, fallbackWidth: 160,
        gap: 1, aspectRatio: 16.0 / 9, viewportHeight: 120)
      for count in 1...5 {
        let tallHeight = tall.frames(width: 350, count: count).map(\.maxY).max() ?? 0
        let shortHeight = short.frames(width: 350, count: count).map(\.maxY).max() ?? 0
        XCTAssertLessThanOrEqual(tallHeight, 350 * 9.0 / 16)
        XCTAssertEqual(shortHeight, 120, accuracy: 0.001)
      }
    }
    let fallback = NativeGalleryGridLayout(isCompact: false, fallbackWidth: 160,
      gap: 1, aspectRatio: 16.0 / 9, isVerticallyCompact: true, compactThumbnailSize: 72)
    XCTAssertEqual(fallback.frames(width: 720, count: 3)[2].maxY, 144, accuracy: 0.001)
  }

  func testGalleryTwoPhotosUseSquareTilesUpToTheHeightLimit() {
    let layout = NativeGalleryGridLayout(isCompact: true, fallbackWidth: 160, gap: 1, aspectRatio: 16.0 / 9)
    let pair = layout.frames(width: 350, count: 2)
    XCTAssertEqual(pair[0].height, pair[0].width)
    XCTAssertEqual(pair[0].size, pair[1].size)
    XCTAssertEqual(pair[1].minX, pair[0].maxX + 1)
    XCTAssertEqual(pair[1].maxX, 350)
    var short = layout
    short.viewportHeight = 120
    XCTAssertEqual(short.frames(width: 350, count: 2)[0].height, 120)
  }

  func testGalleryFiveImageArrangementFollowsTheDeviceSizeClass() {
    let compact = NativeGalleryGridLayout(isCompact: true, fallbackWidth: 160, gap: 1, aspectRatio: 16.0 / 9)
    let regular = NativeGalleryGridLayout(isCompact: false, fallbackWidth: 160, gap: 1, aspectRatio: 16.0 / 9)
    let narrow = compact.frames(width: 390, count: 5)
    XCTAssertEqual(narrow[0].width, narrow[1].width)
    XCTAssertEqual(narrow[2].width, narrow[4].width)
    XCTAssertEqual(narrow[4].maxX, 390, accuracy: 0.001)

    let wide = regular.frames(width: 390, count: 5)
    XCTAssertEqual(wide[0].width, 2 * wide[1].width)
    XCTAssertEqual(wide[4].maxX, 390, accuracy: 0.001)
    XCTAssertEqual(wide[0].maxY, wide[4].maxY)
  }

  func testGalleryFourImagesShareTwoRows() {
    let layout = NativeGalleryGridLayout(isCompact: false, fallbackWidth: 160, gap: 8, aspectRatio: 16.0 / 9)
    for width in [CGFloat(390), 820] {
      let frames = layout.frames(width: width, count: 4)
      XCTAssertEqual(frames[0].maxY, frames[3].maxY)
      XCTAssertEqual(frames[1].width, frames[0].width)
      XCTAssertEqual(frames[3].maxX, width)
    }
  }

  #if os(macOS)
  @MainActor func testChoiceColumnsDependOnWidthRatherThanCopyHeight() {
    _ = NSApplication.shared
    func height(width: CGFloat, secondHeight: CGFloat, single: Bool = false) -> CGFloat {
      NSHostingView(rootView: NativeChoiceCardsLayout(minimumWidth: 136, gap: 12, singleColumn: single) {
        Color.clear.frame(height: 40)
        Color.clear.frame(height: secondHeight)
        Color.clear.frame(height: 60)
      }.frame(width: width)).fittingSize.height
    }
    XCTAssertEqual(height(width: 320, secondHeight: 40), 112, accuracy: 1)
    XCTAssertEqual(height(width: 320, secondHeight: 200), 272, accuracy: 1,
      "A taller cell grows its row, without collapsing the two-column structure")
    XCTAssertEqual(height(width: 600, secondHeight: 200), 200, accuracy: 1)
    XCTAssertEqual(height(width: 240, secondHeight: 200), 324, accuracy: 1)
    XCTAssertEqual(height(width: 320, secondHeight: 200, single: true), 324, accuracy: 1)
  }

  @MainActor func testMountedPagerReservesTheSameTrackInBothReadingDirections() {
    _ = NSApplication.shared
    for direction in [LayoutDirection.leftToRight, .rightToLeft] {
      for selected in [0, 1] {
        let pager = NativePager(ids: [0, 1], selection: .constant(selected), enabled: true,
          identifier: "track") { index in
            Color.clear.frame(height: index == 0 ? 40 : 200)
          }
          .environment(\.layoutDirection, direction).frame(width: 300)
        XCTAssertEqual(NSHostingView(rootView: pager).fittingSize.height, 200, accuracy: 1)
      }
    }
  }

  @MainActor func testStandardCarouselUsesCardSpacingAndKeepsMountedContentAcrossStreamingAndResize() async throws {
    _ = NativeAccessibilityTestSupport.application
    let log = CarouselLayoutLog()
    let library = try carouselLayoutLibrary(log)
    let state = OpenUIState(schema: library.library.toSchema())
    state.push("root=Carousel([[a,ad],[b,bd]],\"card\")\na=TextContent(\"a\")\nad=TextContent(\"a-detail\")\nb=TextContent(\"b\")\nbd=TextContent(\"b-detail")
    let viewport = CarouselLayoutViewport()
    let host = NSHostingView(rootView: CarouselLayoutHost(state: state, registry: library.registry, viewport: viewport))
    let window = NSWindow(contentRect: .init(x: -10000, y: -10000, width: 1100, height: 300),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
    defer { window.close() }
    func settle() {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.12))
      host.layoutSubtreeIfNeeded()
    }
    func accessibleIDs() -> Set<String> {
      Set(NativeAccessibilityTestSupport.elements(in: host).compactMap {
        NativeAccessibilityTestSupport.stringAttribute("accessibilityIdentifier", of: $0)
      })
    }
    settle()
    try await NativeAccessibilityTestSupport.activate(in: host)
    settle()
    let inset = OpenUIThemeValues.defaults.componentStyle.panelInset
    let first = try XCTUnwrap(log.frames["a"]), second = try XCTUnwrap(log.frames["b"])
    XCTAssertEqual(first.width + 2 * inset, 306, accuracy: 1)
    XCTAssertEqual(second.minX - first.maxX - 2 * inset, 12, accuracy: 1)
    XCTAssertEqual(try XCTUnwrap(log.frames["a-detail"]).minY - first.maxY, 12, accuracy: 1,
      "Standard Carousel uses the same m token within each card and between cards")
    XCTAssertTrue(accessibleIDs().contains("carousel.content.a"))
    XCTAssertFalse(accessibleIDs().contains("carousel.content.b"),
      "The portion of the next card that is visible is a preview, not a full reading target")
    XCTAssertFalse(accessibleIDs().contains("openui.carousel.next"))
    let tokens = log.tokens
    XCTAssertEqual(tokens.count, 4, "Each inner array stays a separate card containing both mounted children")

    state.push(" grows as tokens arrive.\")"); state.complete(); settle()
    XCTAssertEqual(log.copies["b-detail"], "b-detail grows as tokens arrive.")
    XCTAssertEqual(log.tokens, tokens)
    for width in [CGFloat(1000), 180, 350] {
      viewport.width = width; settle()
      let expectedCardWidth: CGFloat = width == 1000 ? 320 : width == 180 ? 180 : 306
      XCTAssertEqual(try XCTUnwrap(log.frames["a"]).width + 2 * inset, expectedCardWidth, accuracy: 1)
      XCTAssertEqual(accessibleIDs().contains("carousel.content.b"), width == 1000)
      XCTAssertFalse(accessibleIDs().contains("openui.carousel.previous"))
      XCTAssertFalse(accessibleIDs().contains("openui.carousel.next"))
      XCTAssertEqual(log.tokens, tokens, "Container resizing must not replace the mounted page contents")
    }
    viewport.direction = .rightToLeft; settle()
    let rtlFirst = try XCTUnwrap(log.frames["a"]), rtlSecond = try XCTUnwrap(log.frames["b"])
    XCTAssertEqual(rtlFirst.minX - rtlSecond.maxX - 2 * inset, 12, accuracy: 1)
    XCTAssertTrue(accessibleIDs().contains("carousel.content.a"))
    XCTAssertFalse(accessibleIDs().contains("carousel.content.b"))
    XCTAssertEqual(log.tokens, tokens, "Reading direction only changes placement of the same mounted pages")
    XCTAssertEqual(log.mounts, ["a": 1, "a-detail": 1, "b": 1, "b-detail": 1])
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
  }

  @MainActor func testCarouselKeepsTheVisiblePageWhenEitherReferenceArrivesLate() throws {
    _ = NSApplication.shared
    for (pages, referencedPages) in [("[a,b]", true), ("[[a],[b]]", false)] {
      func definition(_ name: String) -> String {
        let content = "TextContent(\"\(name)\")"
        return "\(name)=\(referencedPages ? "[\(content)]" : content)\n"
      }

      for firstReady in ["a", "b"] {
        let late = firstReady == "a" ? "b" : "a"
        let log = CarouselLayoutLog()
        let library = try carouselLayoutLibrary(log)
        let state = OpenUIState(schema: library.library.toSchema())
        state.push("root=Carousel(\(pages),\"card\")\n" + definition(firstReady))
        let viewport = CarouselLayoutViewport()
        let host = NSHostingView(rootView: CarouselLayoutHost(state: state, registry: library.registry, viewport: viewport))
        let window = NSWindow(contentRect: .init(x: -10000, y: -10000, width: 350, height: 300),
          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        func settle() {
          host.layoutSubtreeIfNeeded()
          RunLoop.main.run(until: Date().addingTimeInterval(0.2))
          host.layoutSubtreeIfNeeded()
        }

        settle()
        let before = try XCTUnwrap(log.frames[firstReady])
        XCTAssertLessThanOrEqual(before.maxX, viewport.width,
          "A page without available content must not be selected before a ready source slot")
        let token = try XCTUnwrap(log.tokens[firstReady])
        let inset = OpenUIThemeValues.defaults.componentStyle.panelInset
        XCTAssertEqual(before.width + 2 * inset, 306, accuracy: 1,
          "The closed source already declares two page slots")

        state.push(definition(late))
        settle()
        let after = try XCTUnwrap(log.frames[firstReady])
        XCTAssertEqual(after.width, before.width, accuracy: 1)
        XCTAssertEqual(log.tokens[firstReady], token)
        XCTAssertEqual(log.mounts[firstReady], 1)
        XCTAssertGreaterThanOrEqual(after.minX, 0)
        XCTAssertLessThanOrEqual(after.maxX, viewport.width,
          "The current page remains visible when an earlier source slot resolves")

        state.complete()
        settle()
        XCTAssertEqual(log.tokens[firstReady], token)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
      }
    }
  }

  @MainActor private func carouselLayoutLibrary(_ log: CarouselLayoutLog) throws -> OpenUIComponentLibrary {
    let standard = try OpenUIComponents.library()
    let definition = try XCTUnwrap(standard.library.components.first { $0.name == "TextContent" })
    return try standard.extending(overriding: [OpenUIComponent(definition) { context in
      let copy = context.string("text") ?? ""
      let key = String(copy.split(separator: " ").first ?? "")
      CarouselLayoutMarker(key: key, copy: copy, log: log)
        .frame(height: 20).frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy)
        .accessibilityIdentifier("carousel.content." + key)
        .background(GeometryReader { geometry in
          Color.clear.onAppear { log.frames[key] = geometry.frame(in: .named("carousel-layout")) }
            .onChange(of: geometry.frame(in: .named("carousel-layout"))) { log.frames[key] = $0 }
        })
    }])
  }
  #endif
  func testAroundAndEvenlyHaveDifferentEdgeSpaceWithoutChangingContentSize() {
    let sizes = [CGSize(width: 40, height: 20), CGSize(width: 40, height: 20)]
    let around = OpenUIFlowPlacement.frames(sizes: sizes, width: 200, gap: 8, align: "start", justify: "around", wrap: false)
    let evenly = OpenUIFlowPlacement.frames(sizes: sizes, width: 200, gap: 8, align: "start", justify: "evenly", wrap: false)
    XCTAssertNotEqual(around[0].minX, evenly[0].minX)
    XCTAssertEqual(around[0].minX * 2, around[1].minX - around[0].maxX - 8, accuracy: 0.001)
    XCTAssertEqual(evenly[0].minX, evenly[1].minX - evenly[0].maxX - 8, accuracy: 0.001)
    for row in [around, evenly] {
      XCTAssertEqual(row[0].minX, 200 - row[1].maxX, accuracy: 0.001)
      XCTAssertEqual(row.map(\.size), sizes)
    }
  }
  func testMixedFontBaselinesAlignWithinEachWrappedLine() {
    let sizes = [CGSize(width: 80, height: 28), CGSize(width: 80, height: 50), CGSize(width: 100, height: 32)]
    let baselines: [CGFloat] = [21, 37, 24]
    for width in [CGFloat(180), CGFloat(500)] {
      let frames = OpenUIFlowPlacement.frames(sizes: sizes, width: width, gap: 12, align: "baseline", justify: "start", baselines: baselines)
      XCTAssertEqual(frames[0].minY + baselines[0], frames[1].minY + baselines[1], accuracy: 0.001)
      if width == 180 { XCTAssertGreaterThanOrEqual(frames[2].minY, max(frames[0].maxY, frames[1].maxY) + 12) }
      else { XCTAssertEqual(frames[2].minY + baselines[2], frames[0].minY + baselines[0], accuracy: 0.001) }
    }
  }
  func testStretchFollowsMeasuredLineHeightAndParentCrossExtent() {
    let sizes = [CGSize(width: 60, height: 20), CGSize(width: 90, height: 70)]
    let row = OpenUIFlowPlacement.frames(sizes: sizes, width: 300, gap: 12, align: "stretch", justify: "start", wrap: false, crossExtent: 100)
    XCTAssertEqual(row.map(\.height), [100, 100])
    let narrow = OpenUIFlowPlacement.frames(sizes: sizes, width: 100, gap: 12, align: "stretch", justify: "start")
    XCTAssertEqual(narrow.map(\.height), [20, 70])
    XCTAssertEqual(narrow[1].minY, 32)
  }
  func testPinnedLucideNamesAndCategoryFallbacksHaveDrawablePaths() {
    XCTAssertEqual(NativeIconCatalog.catalog.version, "0.562.0")
    XCTAssertEqual(NativeIconCatalog.catalog.icons.count, 1912)
    for name in ["utensils-crossed", "soup", "wheat"] {
      XCTAssertEqual(NativeIconCatalog.resolvedName(name, category: nil), name)
    }
    XCTAssertEqual(NativeIconCatalog.resolvedName("not-an-icon", category: " FOOD-BEVERAGE "), "cooking-pot")
    XCTAssertEqual(NativeIconCatalog.resolvedName("not-an-icon", category: nil), "circle-dot")
    for (name, primitives) in NativeIconCatalog.catalog.icons {
      XCTAssertFalse(primitives.isEmpty, name)
      XCTAssertTrue(primitives.allSatisfy { !$0.path.isEmpty && !$0.path.boundingRect.isInfinite }, name)
    }
  }
}

extension NativeLayoutSemanticsTests {
    func testLastPeekingPageStaysWithinTheViewportWithoutADeadTrailingArea() {
        let first = NativePagerGeometry(
            width: 350, count: 3, selected: 0,
            maximumPageWidth: 320, minimumPageWidth: 240, peek: 32, spacing: 16)
        let last = NativePagerGeometry(
            width: 350, count: 3, selected: 2,
            maximumPageWidth: 320, minimumPageWidth: 240, peek: 32, spacing: 16)
        XCTAssertEqual(first.offset, 0)
        XCTAssertLessThan(first.pageWidth, first.width)
        XCTAssertEqual(2 * last.stride - last.offset + last.pageWidth, last.width, accuracy: 0.01)
        XCTAssertGreaterThan(2 * last.stride - last.offset, 0, "The previous page remains visible beside the last card")
        let single = NativePagerGeometry(
            width: 300, count: 1, selected: 0,
            maximumPageWidth: 320, minimumPageWidth: 240, peek: 32, spacing: 16)
        XCTAssertEqual(single.pageWidth, 300)
    }
}

extension NativeLayoutSemanticsTests {
  func testWrappedRowsSeparateHorizontalAndVerticalSpacing() {
    let sizes = [CGSize(width: 70, height: 44), CGSize(width: 70, height: 60),
                 CGSize(width: 70, height: 44), CGSize(width: 70, height: 44)]
    let original = OpenUIFlowPlacement.frames(sizes: sizes, width: 160, gap: 16, align: "start", justify: "start")
    let dense = OpenUIFlowPlacement.frames(sizes: sizes, width: 160, gap: 16, align: "start", justify: "start", rowGap: 0)
    let spaced = OpenUIFlowPlacement.frames(sizes: sizes, width: 160, gap: 16, align: "start", justify: "start", rowGap: 4)
    XCTAssertEqual(dense.map(\.minX), original.map(\.minX), "Changing row spacing must not change horizontal wrapping")
    XCTAssertEqual(dense.map(\.size), sizes, "Control targets keep their measured sizes")
    XCTAssertEqual(dense[1].minX - dense[0].maxX, 16)
    XCTAssertEqual(original[2].minY, 76, "Existing callers retain gap on both axes")
    XCTAssertEqual(dense[2].minY, 60, "The next row follows the tallest item, without an extra row gap")
    XCTAssertEqual(spaced[2].minY, 64)
    let oneRow = Array(sizes.prefix(2))
    XCTAssertEqual(
      OpenUIFlowPlacement.frames(sizes: oneRow, width: 320, gap: 16, align: "start", justify: "start"),
      OpenUIFlowPlacement.frames(sizes: oneRow, width: 320, gap: 16, align: "start", justify: "start", rowGap: 0))
  }

  func testDenseRowsKeepMeasuredControlsOrderedAndNonoverlappingAtPhoneWidths() {
    let measured = [CGSize(width: 140, height: 44), CGSize(width: 80, height: 70),
                    CGSize(width: 170, height: 44), CGSize(width: 100, height: 56),
                    CGSize(width: 150, height: 44), CGSize(width: 200, height: 68)]
    for width in [CGFloat(280), CGFloat(320), CGFloat(350)] {
      for count in [2, 4, 6] {
        let sizes = Array(measured.prefix(count))
        let frames = OpenUIFlowPlacement.frames(sizes: sizes, width: width, gap: 16,
                                                align: "start", justify: "start", rowGap: 0)
        XCTAssertEqual(frames.map(\.size), sizes)
        XCTAssertTrue(frames.allSatisfy { $0.minX >= 0 && $0.maxX <= width })
        for index in frames.indices.dropFirst() {
          let prior = frames[index - 1], current = frames[index]
          XCTAssertGreaterThanOrEqual(current.minY, prior.minY, "Wrapping preserves source order")
          if current.minY == prior.minY { XCTAssertEqual(current.minX - prior.maxX, 16) }
        }
        for first in frames.indices {
          for second in frames.indices where second > first {
            XCTAssertTrue(frames[first].intersection(frames[second]).isEmpty, "Distinct touch targets never overlap")
          }
        }
        let rowTops = Array(Set(frames.map(\.minY))).sorted()
        for index in rowTops.indices.dropFirst() {
          let previousBottom = frames.filter { $0.minY == rowTops[index - 1] }.map(\.maxY).max()!
          XCTAssertEqual(rowTops[index], previousBottom, "Row height comes from real measured item heights")
        }
      }
    }
  }
}

#if os(macOS)
@MainActor private final class CarouselLayoutViewport: ObservableObject {
  @Published var width: CGFloat = 350
  @Published var direction = LayoutDirection.leftToRight
}

private struct CarouselLayoutHost: View {
  let state: OpenUIState
  let registry: OpenUIComponentRegistry
  @ObservedObject var viewport: CarouselLayoutViewport
  var body: some View {
    OpenUIContentView(state: state, registry: registry)
      .environment(\.layoutDirection, viewport.direction)
      .frame(width: viewport.width).coordinateSpace(name: "carousel-layout")
  }
}

@MainActor private final class CarouselLayoutLog {
  var frames: [String: CGRect] = [:]
  var tokens: [String: UUID] = [:]
  var mounts: [String: Int] = [:]
  var copies: [String: String] = [:]
}

private final class CarouselLayoutMarkerView: NSView { let token = UUID() }

private struct CarouselLayoutMarker: NSViewRepresentable {
  let key: String
  let copy: String
  let log: CarouselLayoutLog
  func makeNSView(context: Context) -> CarouselLayoutMarkerView {
    log.mounts[key, default: 0] += 1
    return CarouselLayoutMarkerView()
  }
  func updateNSView(_ view: CarouselLayoutMarkerView, context: Context) {
    log.tokens[key] = view.token
    log.copies[key] = copy
  }
}
#endif
