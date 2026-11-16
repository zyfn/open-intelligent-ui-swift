import SwiftLang
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class DataReadingPresentationTests: XCTestCase {
  func testStackedBarInspectionUsesTheVisibleScaledThickness() {
    var data = NativeChartData()
    data.labels = ["First", "Second"]
    data.slices = [20, 80]
    var drawing = NativeChartDrawing(data: data, name: "SingleStackedBarChart",
      variant: nil, semi: false, palette: [.blue, .orange], secondary: .gray, border: .gray)
    let size = CGSize(width: 200, height: 100)
    drawing.singleStackedBarThickness = 56
    XCTAssertEqual(drawing.inspectionIndex(at: CGPoint(x: 20, y: 25), size: size), 0)
    XCTAssertEqual(drawing.inspectionIndex(at: CGPoint(x: 100, y: 75), size: size), 1)
    XCTAssertNil(drawing.inspectionIndex(at: CGPoint(x: 20, y: 15), size: size))
    drawing.singleStackedBarThickness = 12
    XCTAssertNil(drawing.inspectionIndex(at: CGPoint(x: 20, y: 35), size: size))
    XCTAssertEqual(drawing.inspectionIndex(at: CGPoint(x: 20, y: 50), size: size), 0)
    drawing.singleStackedBarThickness = 400
    XCTAssertEqual(drawing.inspectionIndex(at: CGPoint(x: 100, y: 5), size: size), 1)
  }

  func testZeroTotalIsARealCompletedPolarDataState() {
    var data = NativeChartData()
    XCTAssertFalse(data.hasZeroTotal(for: "PieChart"))
    data.labels = ["Food", "Travel"]
    data.slices = [0, 0]
    for name in ["PieChart", "RadialChart", "SingleStackedBarChart"] {
      XCTAssertTrue(data.hasContent(for: name))
      XCTAssertTrue(data.hasZeroTotal(for: name))
      XCTAssertEqual(data.inspection(at: 0, locale: Locale(identifier: "en"))?.rows.first?.value, "0")
    }
    XCTAssertFalse(data.hasZeroTotal(for: "LineChart"))
    data.slices = [-1, -2]
    XCTAssertFalse(data.hasZeroTotal(for: "PieChart"), "Negative input is not relabeled as literal zero")
    data.slices = [0, 1]
    XCTAssertFalse(data.hasZeroTotal(for: "PieChart"))
  }

  func testLinePatternKeepsSourceIdentityAcrossFiltering() {
    var data = NativeChartData()
    data.labels = ["One", "Two"]
    data.series = [
      .init(name: "A", values: [1, 2]),
      .init(name: "B", values: [3, 4]),
      .init(name: "C", values: [5, 6]),
    ]
    let prepared = data.prepared(for: "LineChart")
    let filtered = prepared.excluding(["A"], for: "LineChart")
    XCTAssertEqual(NativeChartSeriesStyle.dash(for: filtered.colorIndex(at: 0)),
      NativeChartSeriesStyle.dash(for: prepared.colorIndex(at: 1)))
    XCTAssertNotEqual(NativeChartSeriesStyle.dash(for: 0), NativeChartSeriesStyle.dash(for: 8),
      "The next default palette cycle must not repeat both color and line pattern")
  }

  func testEditableDefaultWidthScalesWithoutChangingExplicitWidths() {
    XCTAssertEqual(NativeEditableColumn.width(nil, scale: 2), 320)
    XCTAssertEqual(NativeEditableColumn.width(80, scale: 2), 80)
    XCTAssertEqual(NativeEditableColumn.width(900, scale: 3), 900)
    XCTAssertEqual(NativeEditableColumn.width(nil, scale: .nan), 160)
  }

  func testEmptyScatterDatasetHasNoInventedInspectionRow() {
    var data = NativeChartData()
    data.scatter = [.init(name: "No samples yet", points: [])]
    XCTAssertEqual(data.inspectionCount, 0)
    XCTAssertNil(data.inspection(at: 0, locale: Locale(identifier: "en")))
    data.scatter.append(.init(name: "One sample", points: [.init(x: 3, y: 8, z: 2)]))
    XCTAssertEqual(data.inspectionCount, 1)
    let details = data.inspection(at: 0, locale: Locale(identifier: "en"))
    XCTAssertEqual(details?.title, "One sample")
    XCTAssertEqual(details?.rows.map(\.value), ["3", "8", "2"])
  }
}
