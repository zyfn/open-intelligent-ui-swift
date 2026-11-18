import SwiftLang
import SwiftUI

struct NativeChartDrawing {
  let data: NativeChartData
  let name: String
  let variant: String?
  let semi: Bool
  let palette: [Color]
  let secondary: Color
  let border: Color
  var gridColor: Color? = nil
  var axisColor: Color? = nil
  var canvasColor: Color = .white
  var labelFont: Font = OpenUIThemeValues().textBodySm.nativeFont()
  var inspected: Int? = nil
  var axisScale: CGFloat = 1
  var singleStackedBarThickness: CGFloat = OpenUIPresentation.defaults.singleStackedBarThickness
  var axisMeasurements = NativeChartAxisMeasurements()
  var hasYAxisTitle = false
  private var gridColorValue: Color { gridColor ?? border }
  private var axisColorValue: Color { axisColor ?? secondary }
  private func color(_ index: Int) -> Color {
    let slot = data.colorIndex(at: index)
    return palette.isEmpty ? secondary : palette[slot % palette.count]
  }
  /// Inspection and drawing share the projection, including negative domains
  /// and bubble sizes. A scatter chart does not have categorical labels.
  func inspectionIndex(at location: CGPoint, size: CGSize) -> Int? {
    if name == "ScatterChart" {
      return NativeScatterProjection(data: data, layout: layout(size)).nearestIndex(to: location)
    }
    guard !data.labels.isEmpty else { return nil }
    if ["PieChart", "RadialChart", "SingleStackedBarChart"].contains(name) {
      return NativePolarInspection.index(at: location, size: size, values: data.slices, name: name,
        donut: variant == "donut", semi: semi, singleStackedBarThickness: singleStackedBarThickness)
    }
    if name == "RadarChart" {
      let geometry = NativeRadarGeometry(size: size, scale: axisScale)
      guard hypot(location.x - geometry.center.x, location.y - geometry.center.y) <= geometry.radius else { return nil }
      let angle = (atan2(location.y - geometry.center.y, location.x - geometry.center.x) + .pi / 2 + 2 * .pi)
        .truncatingRemainder(dividingBy: 2 * .pi)
      return Int((angle / (2 * .pi) * Double(data.labels.count)).rounded()) % data.labels.count
    }
    let rect = layout(size).rect
    if ["BarChart", "HorizontalBarChart", "LineChart", "AreaChart"].contains(name),
      !rect.contains(location) { return nil }
    let fraction = name == "HorizontalBarChart"
      ? (location.y - rect.minY) / rect.height
      : (location.x - rect.minX) / rect.width
    return min(data.labels.count - 1, max(0, Int(fraction * CGFloat(data.labels.count))))
  }
  func draw(in canvas: inout GraphicsContext, size: CGSize, xLabel: String?, yLabel: String?) {
    guard !data.invalidData, size.width > 0, size.height > 0 else { return }
    switch name {
    case "PieChart", "RadialChart", "SingleStackedBarChart": circular(&canvas, size)
    case "RadarChart": radar(&canvas, size)
    case "ScatterChart": scatter(&canvas, size)
    default: cartesian(&canvas, size)
    }
    let chartLayout = layout(size)
    if let xLabel, chartLayout.showsXAxisTitle {
      text(
        xLabel, at: CGPoint(x: size.width / 2, y: size.height - 2 * axisScale), canvas: &canvas,
        anchor: .bottom, maxWidth: size.width
      )
    }
    if let yLabel, chartLayout.showsYAxisTitle {
      text(yLabel, at: CGPoint(x: 4, y: 2), canvas: &canvas, anchor: .topLeading,
        maxWidth: max(1, size.width - 8))
    }
  }
  private func text(
    _ value: String, at point: CGPoint, canvas: inout GraphicsContext, anchor: UnitPoint = .center,
    maxWidth: CGFloat? = nil
  ) {
    let label = Text(value).font(labelFont).monospacedDigit().foregroundColor(axisColorValue)
    if let maxWidth {
      let resolved = canvas.resolve(label)
      let available = max(1, maxWidth)
      let measured = resolved.measure(in: CGSize(width: available, height: .greatestFiniteMagnitude))
      let width = min(available, measured.width)
      canvas.draw(resolved, in: CGRect(
        x: point.x - width * anchor.x, y: point.y - measured.height * anchor.y,
        width: width, height: measured.height))
    } else {
      canvas.draw(label, at: point, anchor: anchor)
    }
  }
  private func number(_ value: Double) -> String { NativeChartNumber.tick(value) }
  func layout(_ size: CGSize) -> NativeChartLayout {
    // A small categorical comparison benefits from wrapping before dropping
    // whole categories. Dense axes and numeric domains retain sparse ticks.
    let categorical = ["BarChart", "LineChart", "AreaChart"].contains(name)
    let regular = NativeChartLayout(size: size, scale: axisScale,
      measurements: axisMeasurements, hasYAxisTitle: hasYAxisTitle,
      horizontalCategories: name == "HorizontalBarChart")
    let pitch = regular.rect.width / CGFloat(max(1, data.labels.count))
    let needsWrapping = axisMeasurements.bottomWidth > max(1, pitch - 8 * axisScale)
    let lines = categorical && (1...4).contains(data.labels.count) && needsWrapping ? 2 : 1
    return NativeChartLayout(size: size, scale: axisScale, measurements: axisMeasurements,
      hasYAxisTitle: hasYAxisTitle, categoryLabelLines: lines,
      horizontalCategories: name == "HorizontalBarChart")
  }
  private var domain: (low: Double, high: Double) {
    let stacked = ["BarChart", "HorizontalBarChart"].contains(name) && variant == "stacked"
    var low = 0.0
    var high = 0.0
    for i in data.labels.indices {
      let values = data.series.indices.map { data.value($0, i) }
      low = min(low, stacked ? values.filter { $0 < 0 }.reduce(0, +) : values.min() ?? 0)
      high = max(high, stacked ? values.filter { $0 > 0 }.reduce(0, +) : values.max() ?? 0)
    }
    return (low, high == low ? low + 1 : high)
  }
  var axisLabels: (left: [String], bottom: [String]) {
    func ticks(_ low: Double, _ high: Double) -> [String] {
      // Scatter plots retain their numeric domain, so measure every interval
      // count the grid might show as the available space changes.
      var labels: [String] = []
      for count in 1...4 {
        for index in 0...count {
          let label = number(low + (high - low) * Double(index) / Double(count))
          if !labels.contains(label) { labels.append(label) }
        }
      }
      return labels
    }
    if name == "ScatterChart" {
      let projection = NativeScatterProjection(data: data, size: .zero)
      return (ticks(projection.yMin, projection.yMax), ticks(projection.xMin, projection.xMax))
    }
    guard ["BarChart", "HorizontalBarChart", "LineChart", "AreaChart"].contains(name)
      else { return ([], []) }
    let bounds = domain
    let numeric = NativeChartScale(low: bounds.low, high: bounds.high).ticks.map(number)
    return name == "HorizontalBarChart" ? (data.labels, numeric) : (numeric, data.labels)
  }
  private func grid(
    _ canvas: inout GraphicsContext, rect: CGRect, low: Double, high: Double,
    horizontal: Bool = false, layout: NativeChartLayout, tickValues: [Double]? = nil
  ) {
    let available = horizontal ? rect.width : rect.height
    let spacing = horizontal ? layout.bottomLabelWidth : layout.lineHeight + 10 * layout.scale
    let count = max(1, min(4, Int(available / max(1, spacing))))
    let values = tickValues ?? (0...count).map { low + (high - low) * Double($0) / Double(count) }
    let stride = max(1, Int(ceil(Double(max(1, values.count - 1)) / Double(count))))
    for i in values.indices where i % stride == 0 || i == values.count - 1 {
      let value = values[i]
      let fraction = (value - low) / (high - low)
      guard fraction.isFinite else { continue }
      var line = Path()
      if horizontal {
        let x = rect.minX + rect.width * fraction
        line.move(to: CGPoint(x: x, y: rect.minY))
        line.addLine(to: CGPoint(x: x, y: rect.maxY))
        if layout.showsBottomLabels {
          text(
            number(value), at: CGPoint(x: x, y: rect.maxY + layout.tickOffset),
            canvas: &canvas, anchor: i == 0 ? .leading : i == values.count - 1 ? .trailing : .center,
            maxWidth: rect.width / CGFloat(count))
        }
      } else {
        let y = rect.maxY - rect.height * fraction
        line.move(to: CGPoint(x: rect.minX, y: y))
        line.addLine(to: CGPoint(x: rect.maxX, y: y))
        if layout.showsLeftLabels {
          text(
            number(value), at: CGPoint(x: rect.minX - 6, y: y),
            canvas: &canvas, anchor: .trailing, maxWidth: max(1, rect.minX - 6))
        }
      }
      let isZero = abs(value) < 0.000_001
      canvas.stroke(
        line, with: .color(isZero ? axisColorValue.opacity(0.28) : gridColorValue.opacity(0.65)),
        lineWidth: 0.5)
    }
  }
  private func cartesian(_ canvas: inout GraphicsContext, _ size: CGSize) {
    guard !data.labels.isEmpty, !data.series.isEmpty else { return }
    let layout = self.layout(size)
    let rect = layout.rect
    let count = data.labels.count
    let seriesCount = data.series.count
    let horizontal = name == "HorizontalBarChart"
    let bars = name == "BarChart" || horizontal
    let stacked = bars && variant == "stacked"
    let bounds = domain
    let scale = NativeChartScale(low: bounds.low, high: bounds.high)
    let low = scale.low, high = scale.high
    grid(&canvas, rect: rect, low: low, high: high, horizontal: horizontal,
      layout: layout, tickValues: scale.ticks)
    let numeric = { (v: Double) -> CGFloat in
      let f = CGFloat((v - low) / (high - low))
      return horizontal ? rect.minX + rect.width * f : rect.maxY - rect.height * f
    }
    let pitch = (horizontal ? rect.height : rect.width) / CGFloat(count)
    if let inspected, (0..<count).contains(inspected) {
      let band = horizontal
        ? CGRect(x: rect.minX, y: rect.minY + pitch * CGFloat(inspected), width: rect.width, height: pitch)
        : CGRect(x: rect.minX + pitch * CGFloat(inspected), y: rect.minY, width: pitch, height: rect.height)
      canvas.fill(Path(roundedRect: band, cornerRadius: 4), with: .color(axisColorValue.opacity(0.06)))
    }
    if bars {
      for i in 0..<count {
        var positive = 0.0
        var negative = 0.0
        for s in 0..<seriesCount {
          guard data.hasValue(s, i) else { continue }
          let value = data.value(s, i)
          let base = stacked ? (value >= 0 ? positive : negative) : 0
          let a = numeric(base)
          let b = numeric(base + value)
          let breadth = pitch * 0.75 / CGFloat(stacked ? 1 : seriesCount)
          let category =
            (horizontal ? rect.minY : rect.minX) + pitch * (CGFloat(i) + 0.125)
            + (stacked ? 0 : CGFloat(s) * breadth)
          let bar =
            horizontal
            ? CGRect(x: min(a, b), y: category, width: abs(b - a), height: breadth)
            : CGRect(x: category, y: min(a, b), width: breadth, height: abs(b - a))
          let gap: CGFloat = stacked ? 0 : min(2, breadth * 0.12)
          let insetBar = bar.insetBy(dx: horizontal ? 0 : gap, dy: horizontal ? gap : 0)
          let radius = stacked ? 0 : min(4, breadth * 0.2)
          canvas.fill(
            Path(roundedRect: insetBar, cornerRadius: radius),
            with: .color(color(s).opacity(inspected == nil || inspected == i ? 1 : 0.4)))
          if value >= 0 { positive += value } else { negative += value }
        }
      }
    } else {
      for s in 0..<seriesCount {
        let visibleCount = min(count, data.series[s].values.count)
        let points = (0..<visibleCount).map {
          CGPoint(x: rect.minX + pitch * (CGFloat($0) + 0.5), y: numeric(data.value(s, $0)))
        }
        let line = linePath(points)
        if name == "AreaChart", let first = points.first, let last = points.last {
          var area = line
          area.addLine(to: CGPoint(x: last.x, y: numeric(0)))
          area.addLine(to: CGPoint(x: first.x, y: numeric(0)))
          area.closeSubpath()
          canvas.fill(area, with: .color(color(s).opacity(0.12)))
        }
        canvas.stroke(
          line, with: .color(color(s)),
          style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round,
            dash: NativeChartSeriesStyle.dash(for: data.colorIndex(at: s))))
        if let inspected, points.indices.contains(inspected) {
          let point = points[inspected]
          let marker = Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
          canvas.fill(marker, with: .color(canvasColor))
          canvas.stroke(marker, with: .color(color(s)), lineWidth: 2)
        } else if points.count == 1, let point = points.first {
          canvas.fill(
            Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
            with: .color(color(s)))
        }
      }
    }
  }
  private func linePath(_ points: [CGPoint]) -> Path {
    var line = Path()
    guard let first = points.first else { return line }
    line.move(to: first)
    for i in 1..<points.count {
      let previous = points[i - 1]
      let current = points[i]
      if variant == "step" {
        let middle = (previous.x + current.x) / 2
        line.addLine(to: CGPoint(x: middle, y: previous.y))
        line.addLine(to: CGPoint(x: middle, y: current.y))
        line.addLine(to: current)
      } else if variant == "natural" {
        let before = points[max(0, i - 2)]
        let after = points[min(points.count - 1, i + 1)]
        line.addCurve(
          to: current,
          control1: CGPoint(
            x: previous.x + (current.x - before.x) / 6, y: previous.y + (current.y - before.y) / 6),
          control2: CGPoint(
            x: current.x - (after.x - previous.x) / 6, y: current.y - (after.y - previous.y) / 6))
      } else {
        line.addLine(to: current)
      }
    }
    return line
  }
  private func circular(_ canvas: inout GraphicsContext, _ size: CGSize) {
    let values = data.labels.indices.map {
      max(0, data.slices.indices.contains($0) ? data.slices[$0] : 0)
    }
    let total = values.reduce(0, +)
    guard total > 0 else { return }
    if name == "SingleStackedBarChart" {
      let bar = NativeStackedBarGeometry.frame(size: size, thickness: singleStackedBarThickness)
      var barCanvas = canvas
      barCanvas.clip(to: Path(roundedRect: bar, cornerRadius: 6))
      var x = bar.minX
      for i in values.indices {
        let width = bar.width * values[i] / total
        barCanvas.fill(
          Path(CGRect(x: x, y: bar.minY, width: width, height: bar.height)),
          with: .color(color(i).opacity(inspected == nil || inspected == i ? 1 : 0.35)))
        x += width
      }
      return
    }
    let center = CGPoint(x: size.width / 2, y: semi ? size.height * 0.82 : size.height / 2)
    let radius = max(1, min(size.width / 2 - 12, semi ? size.height * 0.78 : size.height / 2 - 12))
    var start = semi ? -180.0 : -90.0
    let sweep = semi ? 180.0 : 360.0
    for i in values.indices {
      if name == "RadialChart" {
        let thickness = radius / CGFloat(max(1, values.count)) * 0.75
        let r = radius - CGFloat(i) * radius / CGFloat(max(1, values.count)) - thickness / 2
        var track = Path()
        track.addArc(
          center: center, radius: r, startAngle: .degrees(-90), endAngle: .degrees(270),
          clockwise: false)
        canvas.stroke(track, with: .color(gridColorValue), lineWidth: thickness)
        var arc = Path()
        arc.addArc(
          center: center, radius: r, startAngle: .degrees(-90),
          endAngle: .degrees(-90 + 360 * values[i] / (values.max() ?? 1)), clockwise: false)
        canvas.stroke(
          arc, with: .color(color(i).opacity(inspected == nil || inspected == i ? 1 : 0.35)),
          style: StrokeStyle(lineWidth: thickness, lineCap: .round))
      } else {
        let end = start + sweep * values[i] / total
        var sector = Path()
        if variant == "donut" {
          let inner = radius * 0.6
          sector.addArc(
            center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(end),
            clockwise: false)
          sector.addArc(
            center: center, radius: inner, startAngle: .degrees(end), endAngle: .degrees(start),
            clockwise: true)
        } else {
          sector.move(to: center)
          sector.addArc(
            center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(end),
            clockwise: false)
        }
        sector.closeSubpath()
        canvas.fill(sector, with: .color(color(i).opacity(inspected == nil || inspected == i ? 1 : 0.35)))
        canvas.stroke(sector, with: .color(canvasColor), lineWidth: 1.5)
        start = end
      }
    }
  }
  private func radar(_ canvas: inout GraphicsContext, _ size: CGSize) {
    guard !data.labels.isEmpty, !data.series.isEmpty else { return }
    let geometry = NativeRadarGeometry(size: size, scale: axisScale)
    let high = max(1, data.series.flatMap(\.values).max() ?? 1)
    let count = data.labels.count
    let point = { (i: Int, value: Double) -> CGPoint in
      geometry.point(index: i, count: count, fraction: max(0, value) / high)
    }
    for step in 1...4 {
      var polygon = Path()
      for i in 0..<count {
        let p = point(i, high * Double(step) / 4)
        if i == 0 { polygon.move(to: p) } else { polygon.addLine(to: p) }
      }
      polygon.closeSubpath()
      canvas.stroke(polygon, with: .color(gridColorValue), lineWidth: 0.5)
    }
    for i in 0..<count {
      var axis = Path()
      axis.move(to: geometry.center)
      axis.addLine(to: point(i, high))
      canvas.stroke(axis, with: .color(gridColorValue), lineWidth: 0.5)
    }
    for s in data.series.indices {
      var polygon = Path()
      for i in 0..<count {
        let p = point(i, data.value(s, i))
        if i == 0 { polygon.move(to: p) } else { polygon.addLine(to: p) }
      }
      polygon.closeSubpath()
      canvas.fill(polygon, with: .color(color(s).opacity(0.15)))
      canvas.stroke(polygon, with: .color(color(s)), lineWidth: 2)
    }
  }
  private func scatter(_ canvas: inout GraphicsContext, _ size: CGSize) {
    let layout = self.layout(size)
    let projection = NativeScatterProjection(data: data, layout: layout)
    guard !projection.points.isEmpty else { return }
    let rect = projection.rect
    grid(&canvas, rect: rect, low: projection.yMin, high: projection.yMax, layout: layout)
    let count = max(1, min(4, Int(rect.width / layout.bottomLabelWidth)))
    for i in 0...count where layout.showsBottomLabels {
      let fraction = Double(i) / Double(count)
      text(
        number(projection.xMin + (projection.xMax - projection.xMin) * fraction),
        at: CGPoint(x: rect.minX + rect.width * fraction, y: rect.maxY + layout.tickOffset),
        canvas: &canvas, anchor: i == 0 ? .leading : i == count ? .trailing : .center,
        maxWidth: rect.width / CGFloat(count))
    }
    for point in projection.points {
      let selected = inspected == point.rowIndex
      let opacity = inspected == nil || selected ? 0.85 : 0.35
      let circle = Path(ellipseIn: CGRect(
        x: point.position.x - point.radius, y: point.position.y - point.radius,
        width: point.radius * 2, height: point.radius * 2))
      canvas.fill(circle, with: .color(color(point.seriesIndex).opacity(opacity)))
      if selected {
        let ring = Path(ellipseIn: CGRect(
          x: point.position.x - point.radius - 3, y: point.position.y - point.radius - 3,
          width: point.radius * 2 + 6, height: point.radius * 2 + 6))
        canvas.stroke(ring, with: .color(color(point.seriesIndex)), lineWidth: 1.5)
      }
    }
  }
}
