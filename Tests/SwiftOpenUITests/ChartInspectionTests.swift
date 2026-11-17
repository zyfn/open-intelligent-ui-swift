import SwiftLang
import SwiftUI
import XCTest
#if os(macOS)
import AppKit
#endif

@testable import SwiftOpenUI

final class ChartInspectionTests: XCTestCase {
  func testRadarNumberRegionsStayInsideNarrowPlotsAtLargeTextSizes() {
    for width: CGFloat in [160, 240, 320] {
      for scale: CGFloat in [1, 2, 3] {
        let size = CGSize(width: width, height: 250 * scale)
        let measured = Dictionary(uniqueKeysWithValues: (0..<20).map {
          ($0, CGSize(width: CGFloat(String($0 + 1).count) * 14 * scale, height: 22 * scale))
        })
        let frames = NativeRadarLabelPlacement.frames(size: size, count: 20, sizes: measured,
          scale: scale, lineHeight: 22 * scale)
        XCTAssertEqual(frames.count, 20)
        let bounds = CGRect(origin: .zero, size: size)
        XCTAssertTrue(frames.allSatisfy { bounds.contains($0) })
        for (index, frame) in frames.enumerated() {
          XCTAssertGreaterThanOrEqual(frame.width, measured[index]!.width)
          XCTAssertGreaterThanOrEqual(frame.height, measured[index]!.height)
        }
      }
    }
  }

  func testDeclaredChartHeightAndEditableColumnWidthAreNotSilentlyClamped() {
    XCTAssertEqual(NativeChartHeight.value(explicit: 60, defaultHeight: 250, scale: 2), 60)
    XCTAssertEqual(NativeChartHeight.value(explicit: 1500, defaultHeight: 250, scale: 1), 1500)
    for invalid in [Double.nan, .infinity, -1, 0] {
      XCTAssertEqual(NativeChartHeight.value(explicit: invalid, defaultHeight: 250, scale: 2), 500)
      XCTAssertEqual(NativeEditableColumn.width(invalid), 160)
    }
    XCTAssertEqual(NativeEditableColumn.width(80), 80)
    XCTAssertEqual(NativeEditableColumn.width(900), 900)
    XCTAssertEqual(NativeEditableColumn.width(nil), 160)
  }

  #if os(macOS)
  @MainActor func testMountedPieRetainsCompletedValuesUntilReplacementDataCloses() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.push("root=PieChart([\"A\",\"B\"],values)\nvalues=[1,3]\n")
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .openUITheme { $0.pieChartPalette = [.blue, .orange] }
      .environment(\.colorScheme, .light).frame(width: 320).background(Color.white))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: host.fittingSize),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.setFrameOrigin(.init(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close() }
    var captureNumber = 0
    func blueFraction() throws -> Double {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      host.layoutSubtreeIfNeeded()
      let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: image)
      var blue = 0, orange = 0
      for y in 0..<image.pixelsHigh {
        for x in 0..<image.pixelsWide {
          guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
          if color.blueComponent > color.redComponent + 0.3,
            color.blueComponent > color.greenComponent + 0.2 { blue += 1 }
          if color.redComponent > 0.6, color.greenComponent > 0.2,
            color.blueComponent < 0.3 { orange += 1 }
        }
      }
      captureNumber += 1
      print("OPENUI_PIE_FRAME", captureNumber, host.bounds, host.fittingSize, blue, orange)
      if let directory = ProcessInfo.processInfo.environment["OPENUI_SNAPSHOT_DIR"],
        let png = image.representation(using: .png, properties: [:]) {
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("pie-\(captureNumber).png"))
      }
      XCTAssertGreaterThan(blue + orange, 100, "A blank or loading chart cannot pass data retention")
      return Double(blue) / Double(max(1, blue + orange))
    }

    let initial = try blueFraction()
    XCTAssertEqual(initial, 0.25, accuracy: 0.03)
    if initial == 0 {
      host.displayIfNeeded()
      print("OPENUI_PIE_SECOND_FRAME", try blueFraction())
    }
    state.push("values=[3")
    XCTAssertFalse(state.isComplete)
    XCTAssertEqual(try blueFraction(), initial, accuracy: 0.02,
      "An open replacement token must keep the last completed chart on screen")
    state.push(",1]\n")
    state.complete()
    XCTAssertEqual(try blueFraction(), 0.75, accuracy: 0.03,
      "The same mounted chart must present the completed replacement values")
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
  }
  #endif

  @MainActor func testChartCacheDoesNotPublishAnOpenNumericTokenOrReuseStagedDataAfterReset() throws {
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    let cache = NativeChartPresentationCache()
    func values() throws -> (current: NativeChartData, staged: NativeChartData?) {
      cache.values(.init(element: try XCTUnwrap(state.root), registry: library.registry, state: state))
    }
    state.push("root=PieChart([\"Only\"],[4")
    let open = try values()
    XCTAssertEqual(open.current.slices, [4], "The parser has a provisional numeric value")
    XCTAssertNil(open.staged, "The production cache must not stage an unfinished total")
    state.push("0])")
    state.complete()
    XCTAssertEqual(try values().staged?.slices, [40])
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    state.reset()
    state.push("root=PieChart([\"Only\"],[2")
    XCTAssertEqual(try values().current.slices, [2])
    XCTAssertNil(try values().staged, "A new document must not reuse the previous cache's completed chart")
  }

  func testYAxisTitleDoesNotOverlapTheHighestTick() {
    let measurements = NativeChartAxisMeasurements(lineHeight: 18)
    let layout = NativeChartLayout(size: CGSize(width: 318, height: 220), measurements: measurements, hasYAxisTitle: true)
    XCTAssertTrue(layout.showsYAxisTitle)
    let titleBottom = 2 + layout.lineHeight
    let tickTop = layout.rect.minY - layout.lineHeight / 2
    XCTAssertGreaterThanOrEqual(tickTop - titleBottom, 8)
    let untitled = NativeChartLayout(size: CGSize(width: 318, height: 220), measurements: measurements)
    XCTAssertLessThan(untitled.rect.minY, layout.rect.minY)
  }

  @MainActor func testPieChartPlucksSlicePropsIntoRealValues() throws {
    let drawing = try chart(
      "slices=[Slice(\"阅读\",9.5),Slice(\"创作\",9.5),Slice(\"整理\",3)]\nroot=PieChart(slices.props.category,slices.props.value,\"donut\")",
      name: "PieChart")
    XCTAssertEqual(drawing.data.labels, ["阅读", "创作", "整理"])
    XCTAssertEqual(drawing.data.slices, [9.5, 9.5, 3])
    XCTAssertEqual(drawing.data.slices.reduce(0, +), 22)
    XCTAssertEqual(drawing.data.accessibilityRows.count, 3)
  }

  @MainActor private func chart(_ source: String, name: String) throws -> NativeChartDrawing {
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource(source)
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    let data = NativeChartData(context: OpenUIComponentContext(
      element: try XCTUnwrap(state.root), registry: library.registry, state: state))
    return NativeChartDrawing(
      data: data, name: name, variant: nil, semi: false,
      palette: [.blue, .orange], secondary: .secondary, border: .gray)
  }

  @MainActor func testScatterInspectionUsesCoordinatesWithoutCategoricalLabels() throws {
    let drawing = try chart(
      "root=ScatterChart([ScatterSeries(\"Alpha\",[Point(-2,3,2),Point(4,-1,6)]),ScatterSeries(\"Beta\",[Point(1,2),Point(3,5)])],\"Distance\",\"Value\")",
      name: "ScatterChart")
    XCTAssertTrue(drawing.data.labels.isEmpty, "Scatter has datasets, not categorical labels")
    let size = CGSize(width: 300, height: 250)
    // Domain x = -2...4, y = -1...5; plot x = 44...288, y = 18...210.
    XCTAssertEqual(drawing.inspectionIndex(at: CGPoint(x: 44, y: 82), size: size), 0)
    XCTAssertEqual(drawing.inspectionIndex(at: CGPoint(x: 288, y: 210), size: size), 1)
    XCTAssertEqual(drawing.inspectionIndex(at: CGPoint(x: 166, y: 114), size: size), 2)
    XCTAssertEqual(drawing.inspectionIndex(at: CGPoint(x: 247.33, y: 18), size: size), 3)
    XCTAssertTrue(drawing.data.accessibilityRows[2].contains("Beta: x 1.0, y 2.0"))
    XCTAssertTrue(drawing.data.accessibilityRows[0].contains("z 2.0"))
    XCTAssertNil(drawing.inspectionIndex(at: CGPoint(x: 150, y: 180), size: size),
      "Empty chart space must not select the nearest distant observation")
    XCTAssertNil(drawing.inspectionIndex(at: CGPoint(x: 0, y: 82), size: size),
      "The axis label area must not select a point")
  }

  @MainActor func testScatterInspectionAllowsNearbyTouchesAndDegenerateData() throws {
    let drawing = try chart(
      "root=ScatterChart([ScatterSeries(\"Origin\",[Point(0,0)])])", name: "ScatterChart")
    let size = CGSize(width: 240, height: 200)
    XCTAssertEqual(drawing.inspectionIndex(at: CGPoint(x: 44, y: 160), size: size), 0)
    XCTAssertEqual(drawing.inspectionIndex(at: CGPoint(x: 59, y: 160), size: size), 0)
    XCTAssertNil(drawing.inspectionIndex(at: CGPoint(x: 68, y: 160), size: size))
    let empty = try chart("root=ScatterChart([])", name: "ScatterChart")
    XCTAssertNil(empty.inspectionIndex(at: CGPoint(x: 44, y: 160), size: size))
  }

  @MainActor func testHorizontalBarInspectionFollowsRowsInsteadOfXPosition() throws {
    let drawing = try chart(
      "root=HorizontalBarChart([\"First\",\"Second\"],[Series(\"Count\",[2,5])])",
      name: "HorizontalBarChart")
    let size = CGSize(width: 300, height: 250)
    XCTAssertEqual(drawing.inspectionIndex(at: CGPoint(x: 200, y: 66), size: size), 0)
    XCTAssertEqual(drawing.inspectionIndex(at: CGPoint(x: 200, y: 162), size: size), 1)
    XCTAssertNil(drawing.inspectionIndex(at: CGPoint(x: 200, y: 235), size: size))
  }

  func testCompactChartsRequireACompleteAxisGutterBeforeDrawingLabels() {
    let measurements = NativeChartAxisMeasurements(leftWidth: 32, bottomWidth: 12, lineHeight: 16)
    let compact = NativeChartLayout(size: CGSize(width: 100, height: 180), measurements: measurements)
    XCTAssertFalse(compact.showsLeftLabels, "A table preview must not display partial axis digits")
    XCTAssertGreaterThanOrEqual(compact.rect.width, 80, "Keep the data plot usable in the compact preview")
    let expanded = NativeChartLayout(size: CGSize(width: 240, height: 180), measurements: measurements)
    XCTAssertTrue(expanded.showsLeftLabels)
    let longLabels = NativeChartAxisMeasurements(leftWidth: 88, bottomWidth: 12, lineHeight: 16)
    XCTAssertFalse(NativeChartLayout(size: CGSize(width: 170, height: 180), measurements: longLabels).showsLeftLabels)
    XCTAssertTrue(NativeChartLayout(size: CGSize(width: 240, height: 180), measurements: longLabels).showsLeftLabels)
  }

  func testChartLayoutPreservesRegularProjectionAndSeparatesLargeTypeAxes() {
    let regular = NativeChartLayout(size: CGSize(width: 300, height: 250))
    XCTAssertEqual(regular.rect, CGRect(x: 44, y: 18, width: 244, height: 192))
    let size = CGSize(width: 320, height: 250)
    let large = NativeChartLayout(size: size, scale: 2,
      measurements: .init(leftWidth: 110, bottomWidth: 90, lineHeight: 34))
    XCTAssertGreaterThanOrEqual(large.rect.minX, 110 + 16,
      "A measured negative/scientific tick needs room in addition to the axis gap")
    let tickBottom = large.rect.maxY + large.tickOffset + large.lineHeight / 2
    let titleTop = size.height - 2 * large.scale - large.lineHeight
    XCTAssertLessThanOrEqual(tickBottom + 4, titleTop,
      "Category ticks and the axis title occupy separate bands at larger text sizes")
    XCTAssertTrue(large.showsBottomLabels)
    let short = NativeChartLayout(size: CGSize(width: 240, height: 100), scale: 3,
      measurements: .init(leftWidth: 110, bottomWidth: 90, lineHeight: 48))
    XCTAssertFalse(short.showsBottomLabels,
      "Explicitly short charts omit crowded axis labels instead of overlapping; VoiceOver retains the data")
    XCTAssertGreaterThan(short.rect.width, 0)
    XCTAssertGreaterThan(short.rect.height, 0)
  }

  @MainActor func testScatterUsesMeasuredLargeTypePlotForDrawingAndInspection() throws {
    var drawing = try chart(
      "root=ScatterChart([ScatterSeries(\"Alpha\",[Point(-2,3),Point(4,-1)]),ScatterSeries(\"Beta\",[Point(1,2),Point(3,5)])])",
      name: "ScatterChart")
    drawing.axisScale = 2
    drawing.axisMeasurements = .init(leftWidth: 110, bottomWidth: 90, lineHeight: 34)
    let size = CGSize(width: 320, height: 250)
    let projection = NativeScatterProjection(data: drawing.data, layout: drawing.layout(size))
    XCTAssertEqual(projection.points[0].position.x, 126)
    for point in projection.points {
      XCTAssertEqual(drawing.inspectionIndex(at: point.position, size: size), point.rowIndex)
    }
    XCTAssertNil(drawing.inspectionIndex(at: CGPoint(x: 44, y: 82), size: size),
      "The regular-size coordinate must not remain an invisible touch target")
    let abbreviated = try chart(
      "root=BarChart([\"A\"],[Series(\"Count\",[-100000])])", name: "BarChart")
    XCTAssertTrue(abbreviated.axisLabels.left.contains("-100K"),
      "Upstream numberTickFormatter abbreviates thousands with K, including negative values")
  }


  func testSparseCategoryLabelsUseSkippedTickSpaceAndKeepEndpoints() throws {
    let layout = NativeChartLayout(size: CGSize(width: 300, height: 250), scale: 2,
      measurements: .init(leftWidth: 50, bottomWidth: 72, lineHeight: 32))
    let labels = layout.categoryLabels(count: 5)
    XCTAssertEqual(labels.map(\.index), [0, 4])
    let first = try XCTUnwrap(labels.first)
    let last = try XCTUnwrap(labels.last)
    XCTAssertEqual(first.anchor, .leading)
    XCTAssertEqual(last.anchor, .trailing)
    XCTAssertEqual(first.x, layout.rect.minX)
    XCTAssertEqual(last.x, layout.rect.maxX)
    XCTAssertGreaterThanOrEqual(first.width, 72,
      "The first label can use space freed by skipped ticks instead of being limited to one bar group")
    XCTAssertGreaterThanOrEqual(last.width, 72)
    XCTAssertLessThanOrEqual(first.x + first.width, last.x - last.width,
      "Allocated label regions never overlap")
  }

  func testNarrowCategoryAxisKeepsACompleteLabelWithoutMovingData() throws {
    let layout = NativeChartLayout(size: CGSize(width: 240, height: 250), scale: 2,
      measurements: .init(leftWidth: 50, bottomWidth: 72, lineHeight: 32))
    let labels = layout.categoryLabels(count: 5)
    XCTAssertEqual(labels.map(\.index), [0])
    XCTAssertEqual(try XCTUnwrap(labels.first).anchor, .leading)
    XCTAssertGreaterThanOrEqual(try XCTUnwrap(labels.first).width, 72)
    XCTAssertEqual(layout.rect, CGRect(x: 88, y: 36, width: 128, height: 134),
      "Only label placement changes; the plotted geometry and hit coordinates remain the same")
  }




}

extension ChartInspectionTests {
  @MainActor func testIncompleteAndInvalidCompletedSeriesCannotBecomeRealZeros() throws {
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("root=TextContent(\"Ready\")")
    func data(_ values: [Value]) -> NativeChartData {
      let series = EvaluatedElement(typeName: "Series", props: [
        ("category", .string("Count")), ("values", .array(values))])
      let chart = EvaluatedElement(typeName: "LineChart", props: [
        ("labels", .array([.string("A"), .string("B")])), ("series", .array([.element(series)]))])
      return NativeChartData(context: .init(element: chart, registry: library.registry, state: state))
    }
    for samples: [Value] in [[.number(12)], [.number(12), .null], [.number(12), .string("invalid")],
                             [.number(12), .number(.infinity)]] {
      let invalid = data(samples)
      XCTAssertTrue(invalid.invalidData)
      XCTAssertFalse(invalid.hasContent(for: "LineChart"))
      XCTAssertTrue(invalid.accessibilityRows.isEmpty)
      XCTAssertNil(invalid.inspection(at: 1, locale: Locale(identifier: "en_US")))
    }
    let valid = data([.number(12), .number(0)])
    XCTAssertFalse(valid.invalidData)
    XCTAssertTrue(valid.hasValue(0, 1))
    XCTAssertEqual(valid.inspection(at: 1, locale: Locale(identifier: "en_US"))?.rows.first?.value, "0")
  }

  func testChartInspectionRetainsExactLargeAndFractionalValues() {
    var data = NativeChartData()
    data.labels = ["A", "B"]
    data.series = [.init(name: "Value", values: [123456.789, -2555555])]
    XCTAssertEqual(data.inspection(at: 0, locale: Locale(identifier: "en_US"))?.rows.first?.value, "123456.789")
    XCTAssertEqual(data.inspection(at: 1, locale: Locale(identifier: "en_US"))?.rows.first?.value, "-2555555")
    XCTAssertFalse(data.hasValue(0, 2), "A finished chart does not acquire missing zeros")
    XCTAssertFalse(data.hasValue(2, 0))
  }
}

extension ChartInspectionTests {
  @MainActor func testCompletedInvalidSamplesDoNotBecomeZeroDuringAnOpenChart() throws {
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.push("root=LineChart([\"A\",\"B\"],[Series(\"S\",[1,null],")
    if let element = state.root {
      let context = OpenUIComponentContext(element: element, registry: library.registry, state: state)
      if let data = NativeChartStreamingPresentation.staged(context: context) {
        XCTAssertTrue(data.invalidData || !data.hasValue(0, 1))
        XCTAssertFalse(data.accessibilityRows.contains { $0.contains("B: S 0") })
      }
    }
    state.setSource("root=BarChart([\"A\",\"B\"],[Series(\"First\",[-2,4]),Series(\"Second\",[3])],\"stacked\")")
    let data = NativeChartData(context: .init(element: try XCTUnwrap(state.root), registry: library.registry, state: state))
    XCTAssertTrue(data.invalidData, "Completed ragged series are not zero-filled")
    XCTAssertFalse(data.hasContent(for: "BarChart"))
    XCTAssertFalse(data.hasValue(1, 1))
    XCTAssertTrue(data.accessibilityRows.isEmpty)
  }
}


extension ChartInspectionTests {
  func testCategoryLabelsAndInspectionKeepTheirValueAssociation() {
    var data = NativeChartData()
    data.labels = ["五月", "六月", "七月"]
    data.series = [.init(name: "示例", values: [12, 0, -4])]
    for family in ["BarChart", "LineChart", "AreaChart"] {
      let drawing = NativeChartDrawing(data: data, name: family, variant: nil, semi: false,
        palette: [.blue], secondary: .gray, border: .gray)
      let size = CGSize(width: 320, height: 250)
      let layout = drawing.layout(size)
      for label in layout.categoryLabels(count: data.labels.count) {
        let x = layout.rect.minX + layout.rect.width * (CGFloat(label.index) + 0.5) / 3
        XCTAssertEqual(drawing.inspectionIndex(at: CGPoint(x: x, y: layout.rect.midY), size: size), label.index)
        XCTAssertEqual(data.value(0, label.index), [12.0, 0.0, -4.0][label.index])
        XCTAssertLessThanOrEqual(label.x - label.width * label.anchor.x, x)
        XCTAssertGreaterThanOrEqual(label.x + label.width * (1 - label.anchor.x), x)
      }
    }
  }
}
