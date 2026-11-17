#if os(macOS)
import AppKit
import SwiftLang
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class TableAppearanceTests: XCTestCase {
  private let appearance = OpenUITableAppearance(
    gridLine: .red, headerBackground: .blue, background: .white, cornerRadius: 16)

  @MainActor private func snapshot(_ source: String, theme: OpenUIThemeValues) throws -> NSBitmapImageRep {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource(source)
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .openUITheme(theme).frame(width: 320).background(Color.white))
    host.frame = CGRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    host.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    return bitmap
  }

  private func bluePixels(_ image: NSBitmapImageRep) -> Int {
    var count = 0
    for y in 0..<image.pixelsHigh {
      for x in 0..<image.pixelsWide {
        guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if color.blueComponent > 0.8 && color.redComponent < 0.2 && color.blueComponent > color.greenComponent + 0.2 { count += 1 }
      }
    }
    return count
  }

  private func blueHeight(_ image: NSBitmapImageRep) -> Int {
    var first = image.pixelsHigh, last = 0
    for y in 0..<image.pixelsHigh {
      for x in 0..<image.pixelsWide {
        guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if color.blueComponent > 0.8 && color.redComponent < 0.2 && color.blueComponent > color.greenComponent + 0.2 {
          first = min(first, y); last = max(last, y)
        }
      }
    }
    return max(0, last - first + 1)
  }

  private func darkInkWidth(_ image: NSBitmapImageRep) -> Int {
    var first = image.pixelsWide, last = 0
    for y in 0..<image.pixelsHigh {
      for x in 0..<image.pixelsWide {
        guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if max(color.redComponent, color.greenComponent, color.blueComponent) < 0.35 {
          first = min(first, x); last = max(last, x)
        }
      }
    }
    return max(0, last - first + 1)
  }

  @MainActor func testThemeReachesStructuredAndMarkdownTablesWithoutChangingDefaults() throws {
    let table = #"root=Table([Col("Place",["Lake"]),Col("Price",["0"])])"#
    let markdown = "| Place | Price |\n| --- | --- |\n| Lake | 0 |"
    let literal = try XCTUnwrap(String(data: JSONEncoder().encode(markdown), encoding: .utf8))
    let text = "root=TextContent(\(literal))"
    var themed = OpenUIThemeValues(); themed.tableAppearance = appearance
    for source in [table, text] {
      let standard = try snapshot(source, theme: OpenUIThemeValues())
      let custom = try snapshot(source, theme: themed)
      XCTAssertLessThan(bluePixels(standard), 10, "The standard theme must retain its previous appearance")
      XCTAssertGreaterThan(bluePixels(custom), 100, "Both table renderers must consume the configured header background")
    }
  }

  func testThemeResolutionKeepsStandardDefaultsAndCustomOverrides() {
    let standard = OpenUITheme().resolved()
    XCTAssertNil(standard.tableAppearance)
    XCTAssertNil(standard.markdownListItemSpacing)
    XCTAssertNil(standard.markdownEmphasisFont)
    var custom = OpenUITheme()
    custom.tableAppearance = appearance
    custom.markdownListItemSpacing = 15
    custom.markdownEmphasisFont = OpenUIFont(size: 17, family: "Menlo")
    let resolved = custom.resolved()
    XCTAssertEqual(resolved.tableAppearance?.gridLine, .red)
    XCTAssertEqual(resolved.tableAppearance?.cornerRadius, 16)
    XCTAssertEqual(resolved.markdownListItemSpacing, 15)
    XCTAssertEqual(resolved.markdownEmphasisFont?.family, "Menlo")
  }

  @MainActor func testMarkdownStrongUsesConfiguredFontFamily() throws {
    let text = "root=TextContent(\"**iiiiiiiiiiii**\")"
    var normal = OpenUIThemeValues(); normal.textNeutralPrimary = .black
    var custom = normal
    custom.markdownEmphasisFont = OpenUIFont(size: 17, family: "Menlo")
    let ordinary = darkInkWidth(try snapshot(text, theme: normal))
    let emphasized = darkInkWidth(try snapshot(text, theme: custom))
    XCTAssertGreaterThan(ordinary, 5)
    XCTAssertGreaterThan(emphasized, ordinary + 25, "Strong text must use the configured font family")
  }

  @MainActor func testThemedStrongDoesNotReplaceInlineCodeFont() throws {
    let source = "root=TextContent(\"**`iiiiiiiiiiii`**\")"
    var standard = OpenUIThemeValues(); standard.textNeutralPrimary = .black
    var themed = standard
    themed.markdownEmphasisFont = OpenUIFont(size: 17, family: "Georgia")
    let original = darkInkWidth(try snapshot(source, theme: standard))
    let modified = darkInkWidth(try snapshot(source, theme: themed))
    XCTAssertGreaterThan(original, 10)
    XCTAssertEqual(modified, original, accuracy: 4, "Strong styling must retain the inline code font")
  }

  func testMarkdownColumnAlignmentRecognizesDelimiterWithoutReadingCellText() {
    let markdown = "| A \\| B | Count | Status |\n| :--- | ---: | :---: |\n| foo | 4 | ok |"
    XCTAssertEqual(NativeMarkdownTableAlignment.columns(in: markdown), [.leading, .trailing, .center])
  }

  @MainActor func testShortThemedMarkdownTableFillsItsContainer() throws {
    let markdown = "| Place | Price |\n| --- | ---: |\n| Lake | 0 |"
    let literal = try XCTUnwrap(String(data: JSONEncoder().encode(markdown), encoding: .utf8))
    var theme = OpenUIThemeValues(); theme.tableAppearance = appearance
    let image = try snapshot("root=TextContent(\(literal))", theme: theme)
    var rightmost = 0
    for y in 0..<image.pixelsHigh {
      for x in 0..<image.pixelsWide {
        guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if color.blueComponent > 0.8 && color.redComponent < 0.2 && color.blueComponent > color.greenComponent + 0.2 {
          rightmost = max(rightmost, x)
        }
      }
    }
    XCTAssertGreaterThan(CGFloat(rightmost), CGFloat(image.pixelsWide) * 0.9,
      "A short table should expand its columns across the available width")
  }

  @MainActor func testTableFontsReachStructuredAndMarkdownTables() throws {
    let table = #"root=Table([Col("Place",["Lake"]),Col("Price",["0"])])"#
    let markdown = "| Place | Price |\n| --- | --- |\n| Lake | 0 |"
    let literal = try XCTUnwrap(String(data: JSONEncoder().encode(markdown), encoding: .utf8))
    var normal = OpenUIThemeValues(); normal.tableAppearance = appearance
    var larger = OpenUIThemeValues()
    larger.tableAppearance = OpenUITableAppearance(gridLine: .red, headerBackground: .blue,
      background: .white, headerFont: OpenUIFont(size: 30), bodyFont: OpenUIFont(size: 28))
    for source in [table, "root=TextContent(\(literal))"] {
      let original = try snapshot(source, theme: normal)
      let custom = try snapshot(source, theme: larger)
      XCTAssertGreaterThan(custom.pixelsHigh, original.pixelsHigh + 8,
        "Configured table typography must affect each renderer")
    }
  }

  @MainActor func testThemedTablesShareTheirRowHeight() throws {
    let table = #"root=Table([Col("Place",["Lake","Park"]),Col("Price",["Free","40"])])"#
    let markdown = "| Place | Price |\n| --- | --- |\n| Lake | Free |\n| Park | 40 |"
    let literal = try XCTUnwrap(String(data: JSONEncoder().encode(markdown), encoding: .utf8))
    var theme = OpenUIThemeValues()
    let font = OpenUIFont(size: 17, lineHeight: 1.5)
    theme.tableAppearance = OpenUITableAppearance(gridLine: .red, headerBackground: .blue,
      background: .white, headerFont: font.weight(.medium), bodyFont: font)
    let structured = blueHeight(try snapshot(table, theme: theme))
    let richText = blueHeight(try snapshot("root=TextContent(\(literal))", theme: theme))
    XCTAssertGreaterThan(structured, 50)
    XCTAssertEqual(structured, richText, accuracy: 5, "Equal content should have matching table row heights")
  }

  @MainActor func testMarkdownListSpacingChangesRenderedListHeight() throws {
    let markdown = "- First\n- Second\n- Third"
    let literal = try XCTUnwrap(String(data: JSONEncoder().encode(markdown), encoding: .utf8))
    let source = "root=TextContent(\(literal))"
    var spaced = OpenUIThemeValues(); spaced.markdownListItemSpacing = 20
    let standard = try snapshot(source, theme: OpenUIThemeValues())
    let custom = try snapshot(source, theme: spaced)
    XCTAssertGreaterThan(custom.pixelsHigh, standard.pixelsHigh + 40,
      "The configured spacing must reach rendered Markdown list items")
  }

  @MainActor func testMarkdownListUsesThemedLineHeightAndGap() throws {
    let first = try XCTUnwrap(String(data: JSONEncoder().encode("- First"), encoding: .utf8))
    let both = try XCTUnwrap(String(data: JSONEncoder().encode("- First\n- Second"), encoding: .utf8))
    let font = OpenUIFont(size: 17, lineHeight: 1.5)
    var theme = OpenUIThemeValues()
    theme.textBodyDefault = font
    theme.markdownListItemSpacing = 15
    let single = try snapshot("root=TextContent(\(first))", theme: theme)
    let double = try snapshot("root=TextContent(\(both))", theme: theme)
    let pixelsPerPoint = CGFloat(single.pixelsWide) / 320
    XCTAssertEqual(CGFloat(double.pixelsHigh - single.pixelsHigh) / pixelsPerPoint,
                   font.measuredLineHeight() + 15, accuracy: 1,
                   "Each additional item uses the same themed line height and gap")
  }

  @MainActor func testThemedWideMarkdownTableCanScrollToTheLastColumn() throws {
    _ = NSApplication.shared
    let markdown = "| One | Two | Three | Four | Five | Six | Seven | Eight |\n| --- | --- | --- | --- | --- | --- | --- | --- |\n| First | Second | Third | Fourth | Fifth | Sixth | Seventh | Last |"
    let literal = try XCTUnwrap(String(data: JSONEncoder().encode(markdown), encoding: .utf8))
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("root=TextContent(\(literal))")
    XCTAssertTrue(state.errors.isEmpty)
    var theme = OpenUIThemeValues(); theme.tableAppearance = appearance
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .openUITheme(theme).frame(width: 320))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 250),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    host.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first {
      ($0.documentView?.frame.width ?? 0) > $0.contentView.bounds.width + 1
    }, "A wide Markdown table must keep a horizontally scrollable document")
    let document = try XCTUnwrap(scroll.documentView)
    scroll.contentView.scroll(to: NSPoint(x: document.frame.width - scroll.contentView.bounds.width, y: 0))
    scroll.reflectScrolledClipView(scroll.contentView)
    XCTAssertGreaterThan(scroll.contentView.bounds.minX, 100, "The last columns must be reachable")
  }
}
#endif
