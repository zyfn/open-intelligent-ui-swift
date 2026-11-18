import SwiftLang
import SwiftUI

enum NativeChartHeight {
  static func value(explicit: Double?, defaultHeight: Double, scale: CGFloat, minimumHeight: Double = 100) -> CGFloat {
    if let explicit, explicit.isFinite, explicit > 0 { return CGFloat(explicit) }
    return CGFloat(max(minimumHeight, defaultHeight * Double(max(1, scale))))
  }
}

/// The first child is the plot; horizontal category labels are subsequent
/// children. Measuring the real labels before placing the plot lets it grow
/// without a geometry-to-state feedback loop or a second set of label views.
struct NativeChartPlotLayout: Layout {
  let drawing: NativeChartDrawing
  let explicitHeight: Double?
  let defaultHeight: Double

  private func categoryGutter(width: CGFloat, subviews: Subviews) -> CGFloat {
    guard drawing.name == "HorizontalBarChart", subviews.count > 1 else { return 0 }
    let gap = 8 * max(1, drawing.axisScale)
    let measuredWidth = subviews.dropFirst().reduce(CGFloat.zero) {
      max($0, $1.sizeThatFits(.unspecified).width)
    }
    // Reserve at least half the width for data. A longer category wraps in
    // the remaining column instead of hiding itself or every other label.
    return min(measuredWidth + gap, max(0, width / 2))
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let offeredWidth = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
    let width = offeredWidth ?? subviews.first?.sizeThatFits(.unspecified).width ?? 0
    let height = NativeChartHeight.value(explicit: explicitHeight, defaultHeight: defaultHeight,
      scale: drawing.axisScale, minimumHeight: drawing.name == "SingleStackedBarChart" ? 0 : 100)
    let size = CGSize(width: width, height: height)
    guard drawing.name == "HorizontalBarChart", subviews.count > 1,
      !(explicitHeight.map { $0.isFinite && $0 > 0 } ?? false) else { return size }

    let gutter = categoryGutter(width: width, subviews: subviews)
    let layout = drawing.layout(CGSize(width: max(0, width - gutter), height: height))
    let labelWidth = max(1, gutter - 8 * layout.scale)
    let labelProposal = ProposedViewSize(width: labelWidth, height: nil)
    let labelHeight = subviews.dropFirst().reduce(layout.lineHeight) {
      max($0, $1.sizeThatFits(labelProposal).height)
    }
    let rowsHeight = CGFloat(subviews.count - 1) * (labelHeight + 12 * layout.scale)
    let axisHeight = height - layout.rect.height
    return CGSize(width: width, height: max(height, axisHeight + rowsHeight))
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    guard let plot = subviews.first else { return }
    let gutter = categoryGutter(width: bounds.width, subviews: subviews)
    let plotSize = CGSize(width: max(0, bounds.width - gutter), height: bounds.height)
    plot.place(at: CGPoint(x: bounds.minX + gutter, y: bounds.minY), anchor: .topLeading,
      proposal: ProposedViewSize(plotSize))
    guard drawing.name == "HorizontalBarChart", subviews.count > 1 else { return }
    let layout = drawing.layout(plotSize)
    let labelWidth = max(1, gutter - 8 * layout.scale)
    let pitch = layout.rect.height / CGFloat(subviews.count - 1)
    for (index, label) in subviews.dropFirst().enumerated() {
      label.place(at: CGPoint(x: bounds.minX + labelWidth,
        y: bounds.minY + layout.rect.minY + pitch * (CGFloat(index) + 0.5)), anchor: .trailing,
        proposal: ProposedViewSize(width: labelWidth, height: nil))
    }
  }
}

/// Axis numbers have bounded regions; complete category names live in a
/// wrapping key below the plot instead of being squeezed beside its vertices.
enum NativeRadarLabelPlacement {
  static func frames(size: CGSize, count: Int, sizes: [Int: CGSize], scale: CGFloat,
                     lineHeight: CGFloat) -> [CGRect] {
    guard count > 0 else { return [] }
    let geometry = NativeRadarGeometry(size: size, scale: scale)
    return (0..<count).map { index in
      let point = geometry.point(index: index, count: count, fraction: 1.12)
      let measured = sizes[index] ?? CGSize(width: CGFloat(String(index + 1).count) * lineHeight * 0.65, height: lineHeight)
      let width = min(size.width, max(1, measured.width + 4 * scale))
      let height = min(size.height, max(lineHeight, measured.height))
      return CGRect(x: min(max(0, point.x - width / 2), max(0, size.width - width)),
        y: min(max(0, point.y - height / 2), max(0, size.height - height)), width: width, height: height)
    }
  }
}

enum NativeChartTooltipPlacement {
  static func frame(size: CGSize, anchor: CGPoint, bounds: CGSize) -> CGRect {
    let margin: CGFloat = 8
    let width = min(size.width, max(1, bounds.width - 2 * margin))
    // Fixed-size reading content must not be proposed the strip's tiny height:
    // it would paint outside that proposal and collide with later siblings.
    let height = max(1, size.height)
    let verticalMargin = min(margin, max(0, (bounds.height - height) / 2))
    let x = max(margin, min(anchor.x - width / 2, bounds.width - width - margin))
    let above = anchor.y - height - verticalMargin
    let y = max(verticalMargin, min(above >= verticalMargin ? above : anchor.y + verticalMargin,
      bounds.height - height - verticalMargin))
    return CGRect(x: x, y: y, width: width, height: height)
  }
}

struct NativeChartAxisMeasurements: Equatable {
  var leftWidth: CGFloat = 0
  var bottomWidth: CGFloat = 0
  var lineHeight: CGFloat = 0
  func merging(_ other: Self) -> Self {
    Self(leftWidth: max(leftWidth, other.leftWidth), bottomWidth: max(bottomWidth, other.bottomWidth),
      lineHeight: max(lineHeight, other.lineHeight))
  }
}

/// One layout for drawing and hit testing. Text measurement can expand the
/// axis gutters, while bounded text drawing keeps very long labels contained.
struct NativeChartLayout {
  let rect: CGRect
  let scale: CGFloat
  let lineHeight: CGFloat
  let tickOffset: CGFloat
  let bottomLabelWidth: CGFloat
  let measuredBottomLabelWidth: CGFloat
  let showsBottomLabels: Bool
  let showsLeftLabels: Bool
  let showsXAxisTitle: Bool
  let showsYAxisTitle: Bool
  let categoryLabelLines: Int

  init(size: CGSize, scale: CGFloat = 1, measurements: NativeChartAxisMeasurements = .init(), hasYAxisTitle: Bool = false,
       categoryLabelLines: Int = 1, horizontalCategories: Bool = false) {
    let scale = max(1, scale)
    let lineHeight = max(16 * scale, measurements.lineHeight)
    let tickOffset = max(12 * scale, lineHeight / 2 + 4 * scale)
    let right = min(12 * scale, size.width)
    let idealLeft = max(44 * scale, measurements.leftWidth + 8 * scale)
    // Horizontal categories are real Text children next to this plot. Their
    // measured column is already excluded from the proposed drawing width.
    let left = horizontalCategories ? 0 : min(idealLeft,
      max(0, size.width - right - min(80, size.width)))
    let titleClearance = lineHeight * 1.5 + 10 * scale
    let top = min(hasYAxisTitle ? titleClearance : max(18 * scale, lineHeight + 2 * scale), max(0, size.height - 40))
    let lines = min(2, max(1, categoryLabelLines))
    let labelClearance = max(40 * scale, tickOffset + lineHeight * (CGFloat(lines) + 0.5) + 4 * scale,
      lines > 1 ? lineHeight * 3 + 14 * scale : 0)
    let bottom = min(labelClearance,
      max(0, size.height - top - 40))
    rect = CGRect(x: left, y: top, width: max(1, size.width - left - right),
      height: max(1, size.height - top - bottom))
    self.scale = scale
    self.lineHeight = lineHeight
    self.tickOffset = tickOffset
    self.categoryLabelLines = lines
    // A compact preview can reserve a useful plot while lacking a complete
    // axis gutter. Omit those ticks instead of drawing clipped digit fragments;
    // values remain available through inspection and accessibility rows.
    showsLeftLabels = !horizontalCategories && left >= idealLeft
    bottomLabelWidth = max(56 * scale, measurements.bottomWidth + 12 * scale)
    measuredBottomLabelWidth = measurements.bottomWidth > 0 ? measurements.bottomWidth : 44 * scale
    showsXAxisTitle = bottom >= lineHeight + 2 * scale
    showsYAxisTitle = hasYAxisTitle && top >= titleClearance
    showsBottomLabels = bottom >= labelClearance
  }

  struct CategoryLabel {
    let index: Int
    let x: CGFloat
    let anchor: UnitPoint
    let width: CGFloat
  }

  func categoryLabels(count: Int) -> [CategoryLabel] {
    guard count > 0, showsBottomLabels else { return [] }
    let capacity = max(1, Int(rect.width / max(1, measuredBottomLabelWidth / CGFloat(categoryLabelLines) + 8 * scale)))
    let visibleCount = min(count, capacity)
    let indices = visibleCount == 1 ? [0] : (0..<visibleCount).map {
      Int((Double($0) * Double(count - 1) / Double(visibleCount - 1)).rounded())
    }
    let pitch = rect.width / CGFloat(count)
    let centers = indices.map { rect.minX + pitch * (CGFloat($0) + 0.5) }
    return indices.enumerated().map { offset, index in
      let center = centers[offset]
      let left = offset == 0 ? rect.minX : (centers[offset - 1] + center) / 2 + 2 * scale
      let right = offset == centers.count - 1 ? rect.maxX : (center + centers[offset + 1]) / 2 - 2 * scale
      if offset == 0, measuredBottomLabelWidth / 2 > center - left {
        return CategoryLabel(index: index, x: left, anchor: .leading, width: max(1, right - left))
      }
      if offset == centers.count - 1, measuredBottomLabelWidth / 2 > right - center {
        return CategoryLabel(index: index, x: right, anchor: .trailing, width: max(1, right - left))
      }
      return CategoryLabel(index: index, x: center, anchor: .center,
        width: max(1, min(center - left, right - center) * 2))
    }
  }

}

/// A single geometry source for scatter rendering and pointer inspection.
/// Row indices intentionally match accessibilityRows, independent of labels.
struct NativeScatterProjection {
  struct Point {
    let rowIndex: Int
    let seriesIndex: Int
    let position: CGPoint
    let radius: CGFloat
  }
  let rect: CGRect
  let xMin: Double
  let xMax: Double
  let yMin: Double
  let yMax: Double
  let points: [Point]

  init(data: NativeChartData, size: CGSize) {
    self.init(data: data, layout: NativeChartLayout(size: size))
  }

  init(data: NativeChartData, layout: NativeChartLayout) {
    let rawPoints = data.scatter.flatMap(\.points)
    let rect = layout.rect
    let xMin = min(0, rawPoints.map(\.x).min() ?? 0)
    let yMin = min(0, rawPoints.map(\.y).min() ?? 0)
    let xMax = max(xMin + 1, rawPoints.map(\.x).max() ?? 1)
    let yMax = max(yMin + 1, rawPoints.map(\.y).max() ?? 1)
    let maxZ = max(1, rawPoints.compactMap(\.z).max() ?? 1)
    self.rect = rect
    self.xMin = xMin; self.xMax = xMax
    self.yMin = yMin; self.yMax = yMax
    var projected: [Point] = []
    for (seriesIndex, series) in data.scatter.enumerated() {
      for point in series.points {
        projected.append(Point(
          rowIndex: projected.count, seriesIndex: seriesIndex,
          position: CGPoint(
            x: rect.minX + (point.x - xMin) / (xMax - xMin) * rect.width,
            y: rect.maxY - (point.y - yMin) / (yMax - yMin) * rect.height),
          radius: point.z.map { 3 + 9 * sqrt(max(0, $0) / maxZ) } ?? 4))
      }
    }
    points = projected
  }

  func nearestIndex(to location: CGPoint) -> Int? {
    // Edge points remain reachable, while axes and empty plot space do not
    // report a distant observation as if it had been touched.
    guard rect.insetBy(dx: -16, dy: -16).contains(location) else { return nil }
    var result: (index: Int, distance: CGFloat)?
    for point in points {
      let distance = hypot(location.x - point.position.x, location.y - point.position.y)
      guard distance <= max(22, point.radius + 8) else { continue }
      if let result, distance >= result.distance { continue }
      result = (point.rowIndex, distance)
    }
    return result?.index
  }
}
