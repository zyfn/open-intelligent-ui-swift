import SwiftLang
#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class ReadingRhythmTests: XCTestCase {
  @MainActor func testOverviewMetricStartsAlignWhenOnlyOneDescriptionWraps() throws {
    _ = NSApplication.shared
    let frames = OverviewSlotFrames()
    let standard = try OpenUIComponents.library()
    let names = ["IconText", "MetricIndicatorInline"]
    let overrides = try names.map { name -> OpenUIComponent in
      let definition = try XCTUnwrap(standard.library.components.first { $0.name == name })
      return OpenUIComponent(definition) { context in
        NativeComponentHost(context: context) { context in
          Group {
            if name == "IconText" { NativeMediaText(context: context, media: .icon) }
            else { NativeMetric(context: context, inline: true) }
          }.background(GeometryReader { geometry in
            let key = context.string(name == "IconText" ? "title" : "value") ?? ""
            Color.clear.onAppear { frames.values[key] = geometry.frame(in: .named("metric-starts")) }
              .onChange(of: geometry.frame(in: .named("metric-starts"))) { frames.values[key] = $0 }
          })
        }
      }
    }
    let library = try standard.extending(overriding: overrides)
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("""
      root=OverviewCardBlock([
        OverviewCardItem("a",IconText(Icon("footprints"),"soft","m","步行强度","长城线略高"),MetricIndicatorInline("18 km","每日")),
        OverviewCardItem("b",IconText(Icon("leaf"),"soft","m","当季看点","银杏、红叶、清透天"),MetricIndicatorInline("17:05","景山最佳拍照位置"))],"grid",true)
      """)
    XCTAssertTrue(state.errors.isEmpty)
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .frame(width: 350).coordinateSpace(name: "metric-starts"))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 500),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close() }
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    let short = try XCTUnwrap(frames.values["18 km"]), long = try XCTUnwrap(frames.values["17:05"])
    XCTAssertGreaterThan(long.height, short.height + 5, "Only the long description should use another line")
    XCTAssertEqual(short.minY, long.minY, accuracy: 1,
      "The propagated metric-top guide must align the value rows without adding a fake text line")
    XCTAssertEqual(try XCTUnwrap(frames.values["步行强度"]).minY,
      try XCTUnwrap(frames.values["当季看点"]).minY, accuracy: 1)
  }

  @MainActor func testVerticalSummaryCentersItsIcon() throws {
    _ = NSApplication.shared
    let frames = OverviewSlotFrames()
    let standard = try OpenUIComponents.library()
    let icon = try XCTUnwrap(standard.library.components.first { $0.name == "Icon" })
    let library = try standard.extending(overriding: [OpenUIComponent(icon) { context in
      NativeComponentHost(context: context) { context in
        NativeIcon(context: context).background(GeometryReader { geometry in
          Color.clear.onAppear { frames.values["icon"] = geometry.frame(in: .named("summary")) }
            .onChange(of: geometry.frame(in: .named("summary"))) { frames.values["icon"] = $0 }
        })
      }
    }])
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("""
      root=OverviewCardBlock([
        OverviewCardItem("a",IconText(Icon("calendar"),"neutral","m","2 天","行程",true,"vertical")),
        OverviewCardItem("b",IconText(Icon("map-pin"),"neutral","m","11 站","文化景点",true,"vertical"))],"grid",false)
      """)
    XCTAssertTrue(state.errors.isEmpty)
    let element = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root), "items").first)
    let host = NSHostingView(rootView: NativeCardItem(context: .init(element: element,
      registry: library.registry, state: state), kind: "Overview")
      .environmentObject(state).frame(width: 150).coordinateSpace(name: "summary"))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 150, height: 180),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close() }
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    XCTAssertEqual(try XCTUnwrap(frames.values["icon"]).midX, 75, accuracy: 1)
  }

  @MainActor func testIconTextKeepsItsIconAtTheTitleWhenDescriptionWraps() throws {
    _ = NSApplication.shared
    let frames = OverviewSlotFrames()
    let standard = try OpenUIComponents.library()
    let definition = try XCTUnwrap(standard.library.components.first { $0.name == "Icon" })
    let library = try standard.extending(overriding: [OpenUIComponent(definition) { context in
      NativeComponentHost(context: context) { context in
        NativeIcon(context: context).background(GeometryReader { geometry in
          Color.clear.onAppear { frames.values["icon"] = geometry.frame(in: .named("icon-row")) }
            .onChange(of: geometry.frame(in: .named("icon-row"))) { frames.values["icon"] = $0 }
        })
      }
    }])
    let state = OpenUIState(schema: library.library.toSchema())
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .frame(width: 200).coordinateSpace(name: "icon-row"))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 400),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close() }
    func measure(_ description: String) throws -> (icon: CGRect, height: CGFloat) {
      state.setSource("root=IconText(Icon(\"calendar\"),\"soft\",\"m\",\"Duration\",\(jsonStringLiteral(description)))")
      XCTAssertTrue(state.errors.isEmpty)
      host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      return (try XCTUnwrap(frames.values["icon"]), host.fittingSize.height)
    }
    let short = try measure("One day")
    let long = try measure(String(repeating: "A longer description with natural wrapping. ", count: 5))
    XCTAssertGreaterThan(long.height, short.height,
      "The description must grow so this check exercises multiline layout")
    XCTAssertEqual(short.icon.minY, OpenUIThemeValues().space2xs, accuracy: 1,
      "The icon retains its existing inset beside the title")
    XCTAssertEqual(long.icon.minY, short.icon.minY, accuracy: 1,
      "Wrapping the description cannot move the icon away from the title")
  }

  @MainActor func testOverviewMetricsUseTheBottomEdgeOfTheSameGridRow() throws {
    _ = NSApplication.shared
    let frames = OverviewSlotFrames()
    let standard = try OpenUIComponents.library()
    let definition = try XCTUnwrap(standard.library.components.first { $0.name == "MetricIndicatorInline" })
    let library = try standard.extending(overriding: [OpenUIComponent(definition) { context in
      NativeComponentHost(context: context) { context in
        NativeMetric(context: context, inline: true).background(GeometryReader { geometry in
          Color.clear.onAppear { frames.values[context.string("value") ?? ""] = geometry.frame(in: .named("metrics")) }
            .onChange(of: geometry.frame(in: .named("metrics"))) { frames.values[context.string("value") ?? ""] = $0 }
        })
      }
    }])
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("""
      root=OverviewCardBlock([
        OverviewCardItem("a",IconText(Icon("calendar-days"),"soft","md","2 天 1 晚","中轴线与郊野各一天，沿着老城慢慢散步。"),MetricIndicatorInline("48 h","含往返")),
        OverviewCardItem("b",IconText(Icon("footprints"),"soft","md","步行强度","长城线略高"),MetricIndicatorInline("18 km","每日"))],"grid",true)
      """)
    XCTAssertTrue(state.errors.isEmpty)
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .frame(width: 600).coordinateSpace(name: "metrics"))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close() }
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    let first = try XCTUnwrap(frames.values["48 h"]), second = try XCTUnwrap(frames.values["18 km"])
    XCTAssertEqual(first.maxY, second.maxY, accuracy: 1,
      "Different heading heights cannot leave a metric floating above its peer")
  }

  @MainActor func testOverviewMediaAndMetricShareTheContentLeadingEdge() throws {
    _ = NSApplication.shared
    let standard = try OpenUIComponents.library()
    let frames = OverviewSlotFrames()
    let names = ["IconText", "ImageText", "Text", "MetricIndicatorInline"]
    let replacements = try names.map { name -> OpenUIComponent in
      let component = try XCTUnwrap(OpenUIComponents.components.first { $0.definition.name == name })
      return OpenUIComponent(component.definition) { context in
        NativeComponentHost(context: context) { context in
          Group {
            switch name {
            case "IconText": NativeMediaText(context: context, media: .icon)
            case "ImageText": NativeMediaText(context: context, media: .thumbnail)
            case "Text": NativeInlineText(context: context, bold: false)
            default: NativeMetric(context: context, inline: true)
            }
          }.background(GeometryReader { geometry in
            Color.clear.onAppear { frames.values[name] = geometry.frame(in: .named("overview")) }
              .onChange(of: geometry.frame(in: .named("overview"))) { frames.values[name] = $0 }
          })
        }
      }
    }
    let library = try standard.extending(overriding: replacements)
    for (name, header) in [
      ("IconText", "IconText(Icon(\"wallet\"),\"neutral\",\"m\",\"预算\",\"两人合计\")"),
      ("ImageText", "ImageText(\"photo.jpg\",\"Room\",\"住宿\",\"一晚\")"),
      ("Text", "Text(\"text\",\"预算\",\"两人合计\")")
    ] {
      for width in [CGFloat(166), 300] {
        frames.values = [:]
        let state = OpenUIState(schema: library.library.toSchema())
        state.setSource("root=OverviewCardBlock([OverviewCardItem(\"a\",\(header),MetricIndicatorInline(\"¥1200\",\"含餐饮\")),OverviewCardItem(\"b\",Text(\"text\",\"Other\"))])")
        XCTAssertTrue(state.errors.isEmpty)
        let element = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root), "items").first)
        let context = OpenUIComponentContext(element: element, registry: library.registry, state: state)
        let host = NSHostingView(rootView: NativeCardItem(context: context, kind: "Overview")
          .environmentObject(state).frame(width: width).coordinateSpace(name: "overview"))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 240),
          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        let top = try XCTUnwrap(frames.values[name])
        let bottom = try XCTUnwrap(frames.values["MetricIndicatorInline"])
        XCTAssertEqual(top.minX, OpenUIThemeValues().spaceM, accuracy: 1)
        XCTAssertEqual(bottom.minX, top.minX, accuracy: 1,
          "An intrinsic-width metric must align with the top slot at \(width)pt")
        XCTAssertLessThanOrEqual(bottom.maxX, width - OpenUIThemeValues().spaceM + 1)
      }
    }
  }
  @MainActor private func height(_ source: String, theme: OpenUIThemeValues = OpenUIThemeValues(),
    presentation: OpenUIPresentation = OpenUIPresentation()) throws -> CGFloat {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource(source)
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    return NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .openUITheme(theme).environment(\.openUIPresentation, presentation)
      .frame(width: 350)).fittingSize.height
  }

  @MainActor func testPlainEntityValuesDoNotInheritNumericEmphasisOverrides() throws {
    let plain = "root=EntityList([{left:\"Scope\",right:\"A readable sentence\",rightVariant:\"text\"}])"
    let numeric = "root=EntityList([{left:\"Total\",right:\"1234.50\",rightVariant:\"number\"}])"
    var theme = OpenUIThemeValues()
    theme.textNumbersDefaultHeavy = OpenUIFont(size: 40, weight: .bold)
    XCTAssertEqual(try height(plain, theme: theme), try height(plain), accuracy: 1,
      "A theme's numeric emphasis must not turn ordinary explanations into display text")
    XCTAssertGreaterThan(try height(numeric, theme: theme), try height(numeric) + 15)
  }

  @MainActor func testEntityRowsUseTheSharedVerticalSpacingToken() throws {
    let source = #"root=EntityList([{left:"One",right:"First"},{left:"Two",right:"Second"}],"small")"#
    var theme = OpenUIThemeValues()
    theme.spaceM = 26
    XCTAssertGreaterThan(try height(source, theme: theme), try height(source) + 50,
      "The compact list uses spaceM for row padding")
  }

  @MainActor func testEntityListAlignsHeaderTextNumbersAndFooterToTheTrailingEdge() throws {
    for size in ["default", "small"] {
      let decorations = size == "default"
        ? #",{left:"项目",right:"明细"},{left:"合计",right:"¥60",rightVariant:"number"}"# : ""
      let columns = try entityInkBands("""
        root=EntityList([
          {left:"交通",right:"¥60",rightVariant:"number"},
          {left:"景点",right:"已预约"}
        ],"\(size)"\(decorations))
        """)
      let count = size == "default" ? 4 : 2
      XCTAssertEqual(columns.labels.count, count)
      XCTAssertEqual(columns.values.count, count)

      let edge = try XCTUnwrap(columns.values.first).upperBound
      XCTAssertGreaterThan(edge, 290, "The value column should reach the trailing edge")
      for value in columns.values.dropFirst() {
        XCTAssertEqual(value.upperBound, edge, accuracy: 4)
      }
    }
  }

  @MainActor func testEntityListRetainsTheTrailingEdgeAsRowsArrive() throws {
    let prefix = """
      root=EntityList(rows)
      rows=[{left:"景点",right:"已预约"},
      """
    let first = try XCTUnwrap(entityInkBands(prefix, streaming: true).values.first)
    let complete = prefix + #"{left:"机场与航站楼",right:"¥120",rightVariant:"number"}]"#
    let appended = try entityInkBands(complete, streaming: true).values
    let restored = try entityInkBands(complete).values
    XCTAssertEqual(appended.count, 2)
    XCTAssertEqual(restored.count, 2)
    XCTAssertGreaterThan(first.upperBound, 290)
    XCTAssertEqual(try XCTUnwrap(appended.first).upperBound, first.upperBound, accuracy: 3)
    XCTAssertEqual(try XCTUnwrap(restored.first).upperBound, first.upperBound, accuracy: 3)
  }

  @MainActor func testEntityListWrapsBothColumnsInANarrowViewport() throws {
    let label = #"root=EntityList([{left:"特别长的字段名称需要在窄屏上完整换行",right:""}])"#
    let value = #"root=EntityList([{left:"",right:"这段说明也需要在右侧值列内完整换行。"}])"#
    for size in [DynamicTypeSize.large, .xxxLarge] {
      let labels = try entityInkBands(label, width: 180, dynamicType: size)
      let values = try entityInkBands(value, width: 180, dynamicType: size)
      XCTAssertGreaterThanOrEqual(labels.labels.count, 3, "The label must wrap at \(size)")
      XCTAssertTrue(labels.values.isEmpty, "A long label must stay inside its half")
      XCTAssertGreaterThanOrEqual(values.values.count, 3, "The value must wrap at \(size)")
      XCTAssertTrue(values.labels.isEmpty, "A long value must stay inside its half")
    }
  }

  @MainActor private func entityInkBands(
    _ source: String, width: CGFloat = 300, dynamicType: DynamicTypeSize = .large, streaming: Bool = false
  ) throws -> (labels: [ClosedRange<CGFloat>], values: [ClosedRange<CGFloat>]) {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource(source, streaming: streaming)
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    var theme = OpenUIThemeValues()
    theme.textNeutralPrimary = .black
    theme.textNeutralSecondary = .black
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .openUITheme(theme).environment(\.dynamicTypeSize, dynamicType)
      .frame(width: width).padding(10).background(Color.white))
    host.frame = CGRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    host.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width

    func inkBands(in columns: Range<Int>) -> [ClosedRange<CGFloat>] {
      var bands: [(lastY: Int, left: Int, right: Int)] = []
      for y in 0..<bitmap.pixelsHigh {
        let ink = columns.filter { x in
          guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
          return color.alphaComponent > 0.8 && max(color.redComponent, color.greenComponent, color.blueComponent) < 0.4
        }
        guard ink.count >= 2, let left = ink.first, let right = ink.last else { continue }
        if let last = bands.last, y - last.lastY <= 2 {
          bands[bands.count - 1] = (y, min(last.left, left), max(last.right, right))
        } else { bands.append((y, left, right)) }
      }
      return bands.map { CGFloat($0.left) / scale...CGFloat($0.right) / scale }
    }

    let midpoint = bitmap.pixelsWide / 2
    return (inkBands(in: 0..<midpoint), inkBands(in: midpoint..<bitmap.pixelsWide))
  }

  @MainActor func testSingleStackedBarUsesAnIntrinsicCompactPlot() throws {
    let source = "root=SingleStackedBarChart([\"Morning\",\"Afternoon\"],[30,70])"
    XCTAssertLessThan(try height(source), 110,
      "A single distribution strip plus one legend line should not reserve a full plot")
    XCTAssertGreaterThan(try height("root=BarChart([\"A\",\"B\"],[Series(\"Visitors\",[30,70])])"), 200,
      "Charts with axes retain their ordinary plotting area")
  }

  @MainActor func testCodeCopyHonorsTheExistingPlatformHitTargetPolicy() throws {
    let source = "root=CodeBlock(\"let city = 1\",\"swift\")"
    var presentation = OpenUIPresentation()
    presentation.minimumControlTargetSize = 80
    XCTAssertGreaterThan(try height(source, presentation: presentation), try height(source) + 25,
      "The copy control must use the same platform policy as other native controls")
  }
}

@MainActor private final class OverviewSlotFrames { var values: [String: CGRect] = [:] }
#endif
