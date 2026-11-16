import SwiftLang
#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class HorizontalChartRenderingTests: XCTestCase {
  @MainActor func testEveryBarKeepsAVisibleCategoryWithMoreRowsLongNamesAndLargerFonts() throws {
    let cases: [(count: Int, width: CGFloat, fontSize: CGFloat, direction: LayoutDirection, long: Bool)] = [
      (7, 350, 13, .leftToRight, false),
      (19, 280, 13, .rightToLeft, false),
      (7, 280, 26, .rightToLeft, true),
    ]
    var shortHeight = 0
    for item in cases {
      let labels = (1...item.count).map { index in
        item.long ? "Category \(index) with a complete description that needs several lines" : "Row \(index)"
      }
      let labelJSON = String(decoding: try JSONEncoder().encode(labels), as: UTF8.self)
      let values = Array(repeating: "1", count: item.count).joined(separator: ",")
      let image = try render("root=HorizontalBarChart(\(labelJSON),[Series(\"Count\",[\(values)])])",
        width: item.width, fontSize: item.fontSize, direction: item.direction)
      let bars = barBands(in: image)
      XCTAssertEqual(bars.rows.count, item.count, "The test must contain every actual plotted bar")
      XCTAssertGreaterThan(bars.leftEdge, 8, "Categories need their own visible column")
      for (index, band) in bars.rows.enumerated() {
        var ink = 0
        for y in band {
          for x in 0..<max(0, bars.leftEdge - 2) {
            guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            if color.redComponent > color.greenComponent + 0.3,
              color.redComponent > color.blueComponent + 0.3 { ink += 1 }
          }
        }
        XCTAssertGreaterThan(ink, 4,
          "Bar \(index + 1) has no visible category; sparse axes and accessibility-only names do not pass")
      }
      if item.long {
        XCTAssertGreaterThan(image.pixelsHigh, shortHeight,
          "Complete wrapped labels must get more space instead of being clipped or truncated")
      } else if item.count == 7 { shortHeight = image.pixelsHigh }
    }
  }

  @MainActor func testPlotLayoutKeepsTheAuthoredHeightOfOtherChartFamilies() throws {
    for height in [60, 420] {
      let image = try render("root=BarChart([\"A\",\"B\"],[Series(\"Count\",[1,2])],null,null,null,\(height))",
        width: 280, fontSize: 26, direction: .leftToRight)
      XCTAssertEqual(image.size.height, CGFloat(height), accuracy: 1,
        "Category fitting must not replace an authored height on another chart family")
    }
  }

  @MainActor private func render(_ source: String, width: CGFloat, fontSize: CGFloat,
                                direction: LayoutDirection) throws -> NSBitmapImageRep {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource(source)
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    var presentation = OpenUIPresentation()
    presentation.chartAxis = .red
    let hosting = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .openUITheme { theme in
        theme.textBodyXs = OpenUIFont(size: fontSize)
        theme.horizontalBarChartPalette = [.blue]
      }
      .openUIPresentation(presentation)
      .environment(\.layoutDirection, direction)
      .environment(\.colorScheme, .light)
      .frame(width: width).background(Color.white))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: hosting.fittingSize),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    window.setFrameOrigin(.init(x: -10000, y: -10000))
    window.orderFront(nil)
    defer { window.close() }
    hosting.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    window.setContentSize(hosting.fittingSize)
    hosting.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    hosting.layoutSubtreeIfNeeded()
    let image = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
    hosting.cacheDisplay(in: hosting.bounds, to: image)
    return image
  }

  /// Find the rendered blue bars first, then inspect the adjacent category
  /// column. This fails for a blank chart as well as missing individual names.
  private func barBands(in image: NSBitmapImageRep) -> (rows: [ClosedRange<Int>], leftEdge: Int) {
    var rows: [ClosedRange<Int>] = []
    var start: Int?
    var left = image.pixelsWide
    for y in 0..<image.pixelsHigh {
      var hasBar = false
      for x in 0..<image.pixelsWide {
        guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if color.blueComponent > color.redComponent + 0.3,
          color.blueComponent > color.greenComponent + 0.2 {
          hasBar = true; left = min(left, x)
        }
      }
      if hasBar, start == nil { start = y }
      if !hasBar, let first = start { rows.append(first...(y - 1)); start = nil }
    }
    if let first = start { rows.append(first...(image.pixelsHigh - 1)) }
    return (rows, left)
  }
}
#endif
