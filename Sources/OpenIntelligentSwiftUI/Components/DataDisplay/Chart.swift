import SwiftUI
import Charts
import OpenUILang
import OpenUISwiftUI

private enum ChartMetrics {
    static let axisFont: Font = .caption
    static let legendFont: Font = .footnote
    static let labelColor: Color = .primary
}

enum ChartComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Chart", description: "Native chart with tap/drag/hover popover inspection, accessible data points and expandable data details. Selection stays local to the chart. x is a category (numeric for scatter); up to 8 numeric series inferred from the first row. Defaults: format number, currency USD, stacked false, height 240 points. Invalid values are omitted. Pie/donut use the first series and nonnegative values. Data details preserve exact accessible values.", params: [
            OpenUIParameter.string("type", values: ["bar", "line", "area", "pie", "donut", "scatter"]),
            Parameter.array("data", items: .object([.init(key: "type", value: .string("object")), .init(key: "additionalProperties", value: .object([.init(key: "type", value: .array([.string("string"), .string("number")]))]))])),
            OpenUIParameter.string("x", required: false),
            Parameter.array("series", items: .object([.init(key: "type", value: .string("string"))]), required: false),
            OpenUIParameter.string("format", required: false, values: ["number", "currency", "percent"]),
            OpenUIParameter.string("currency", required: false), OpenUIParameter.flag("stacked"),
            Parameter.number("height", minimum: 140, maximum: 480)
        ]) { ChartView(context: $0) }
    }
}

struct ChartData {
    struct Point: Identifiable {
        let id: String
        let label: String
        let x: Double?
        let series: String
        let value: Double
        let segment: Int
        init(id: String, label: String, x: Double?, series: String, value: Double, segment: Int = 0) {
            self.id = id; self.label = label; self.x = x; self.series = series; self.value = value; self.segment = segment
        }
        var segmentKey: String { series + "#segment:" + String(segment) }
    }
    struct Entry: Identifiable {
        let id: String
        let label: String
        let series: String
        let value: Double?
    }
    let xKey: String
    let series: [String]
    let points: [Point]
    let omitted: Int
    let labels: [String]
    let entries: [Entry]
    init(rows: Value?, x: String?, series: Value?, scatter: Bool = false) {
        let rows = ValueReading.array(rows)
        let fields: [ObjectField] = { if case .object(let object) = rows.first { return object.fields }; return [] }()
        let key = x ?? fields.first(where: { field in
            if scatter { return ValueReading.number(field.value) != nil }
            if case .string = field.value { return true }
            return false
        })?.key.displayString ?? fields.first?.key.displayString ?? ""
        xKey = key
        let requested = ValueReading.array(series).map { ValueReading.string($0) }
        let inferred = fields.filter { $0.key.displayString != key && ValueReading.number($0.value) != nil }.map { $0.key.displayString }
        var seen = Set<String>()
        self.series = Array((requested.isEmpty ? inferred : requested).filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(8))
        var points: [Point] = [], entries: [Entry] = [], labels: [String] = [], seenLabels = Set<String>()
        var omitted = 0, occurrences: [String: Int] = [:], segments: [String: Int] = [:]
        for row in rows {
            let rawX = ValueReading.field(row, key)
            let label = ValueReading.string(rawX)
            if !label.isEmpty && seenLabels.insert(label).inserted { labels.append(label) }
            occurrences[label, default: 0] += 1
            for series in self.series {
                let value = ValueReading.number(ValueReading.field(row, series))
                let id = label + "#" + String(occurrences[label]!) + "#" + series
                if !label.isEmpty { entries.append(Entry(id: id, label: label, series: series, value: value)) }
                guard !label.isEmpty, let value, !scatter || ValueReading.number(rawX) != nil else {
                    omitted += 1; segments[series, default: 0] += 1; continue
                }
                points.append(Point(id: id, label: label, x: ValueReading.number(rawX), series: series, value: value,
                                    segment: segments[series, default: 0]))
            }
        }
        self.points = points; self.omitted = omitted; self.labels = labels; self.entries = entries
    }
    static func formatted(_ value: Double, kind: String?, currency: String?, locale: Locale = .current) -> String {
        guard value.isFinite else { return SDKStrings.text("chart.unavailable", locale: locale) }
        // Shortest numeric representation preserves the current Value/Double.
        // It cannot recover source lexical zeros or precision lost before rendering.
        let number = jsNumberString(value).replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
        if kind == "percent" { return number + "%" }
        if kind == "currency" { return currencyCode(currency) + " " + number }
        return number
    }
    static func currencyCode(_ currency: String?) -> String {
        currency?.range(of: "^[A-Za-z]{3}$", options: .regularExpression) != nil ? currency!.uppercased() : "USD"
    }
    /// Axis labels are concise; inspection and data details retain the original precision.
    static func axisLabel(_ value: Double, kind: String?, currency: String?, locale: Locale = .current) -> String {
        let label = value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(locale))
        if kind == "percent" { return label + "%" }
        guard kind == "currency" else { return label }
        return currencyCode(currency) + " " + label
    }
}

private struct ChartView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    @EnvironmentObject private var state: OpenUIState
    @State private var inspectedLabel: String?
    @State private var inspectionPresented = false
    @State private var inspectedPointID: String?
    private var selectedLabel: String? { inspectedLabel }
    private var kind: String { context.string("type") ?? "bar" }
    private var data: ChartData { ChartData(rows: context.value("data"), x: context.string("x"), series: context.value("series"), scatter: kind == "scatter") }
    private func formatted(_ value: Double) -> String { ChartData.formatted(value, kind: context.string("format"), currency: context.string("currency"), locale: locale) }
    var body: some View {
        let data = data
        VStack(alignment: .leading, spacing: theme.groupSpacing) {
            if data.points.isEmpty {
                Text(SDKStrings.text("chart.empty", locale: locale)).foregroundStyle(theme.secondaryText)
                if !data.entries.isEmpty { detail(data) }
            } else {
                if !typeSize.isAccessibilitySize {
                    if kind == "pie" || kind == "donut" {
                        NativePie(points: data.points.filter { $0.series == data.series.first && $0.value >= 0 },
                                  donut: kind == "donut", selected: inspectedPointID,
                                  plotHeight: CGFloat(min(480, max(140, context.number("height") ?? 240))),
                                  interactive: context.canInteract,
                                  formatted: formatted, select: { selectPoint($0, data: data) })
                            .popover(isPresented: $inspectionPresented) { popover(data) }
                    } else {
                        cartesian(data).frame(height: CGFloat(min(480, max(140, context.number("height") ?? 240))))
                        seriesLegend(data)
                    }
                    DisclosureGroup(SDKStrings.text("chart.details", locale: locale)) { detail(data).padding(.top, theme.innerSpacing) }
                } else { detail(data) }
                if data.omitted > 0 { Text(SDKStrings.text("chart.omitted", locale: locale, data.omitted)).font(theme.captionFont).foregroundStyle(theme.secondaryText) }
                if kind == "pie" || kind == "donut" {
                    let negative = data.points.filter { $0.series == data.series.first && $0.value < 0 }.count
                    if negative > 0 {
                        Text(SDKStrings.text("chart.negative_omitted", locale: locale, negative))
                            .font(theme.captionFont).foregroundStyle(theme.secondaryText)
                    }
                }
            }
        }
        .onChange(of: data.points.map(\.id)) { ids in
            if let inspectedPointID, !ids.contains(inspectedPointID) { clearInspection() }
            else if let selectedLabel, !data.labels.contains(selectedLabel) { clearInspection() }
        }
    }
    private func select(_ label: String) {
        guard context.canInteract else { return }
        inspectionPresented = !label.isEmpty
        guard selectedLabel != label else { return }
        inspectedLabel = label
        inspectedPointID = nil
    }
    private func selectPoint(_ id: String, data: ChartData) {
        guard context.canInteract, let point = data.points.first(where: { $0.id == id }) else { return }
        inspectedPointID = id; inspectedLabel = point.label; inspectionPresented = true
    }
    private func clearInspection() {
        inspectionPresented = false; inspectedLabel = nil; inspectedPointID = nil
    }
    private func inspectedPoints(_ data: ChartData) -> [ChartData.Point] {
        if kind == "pie" || kind == "donut" { return data.points.filter { $0.id == inspectedPointID } }
        return data.points.filter { $0.label == selectedLabel }
    }
    @ViewBuilder private func popover(_ data: ChartData) -> some View {
        let content = VStack(alignment: .leading, spacing: theme.innerSpacing) {
            HStack {
                Text(selectedLabel ?? SDKStrings.text("chart.value", locale: locale)).font(theme.titleFont)
                Spacer()
                Button { inspectionPresented = false } label: { Image(systemName: "xmark").frame(minWidth: theme.minimumControlHeight, minHeight: theme.minimumControlHeight) }
                    .buttonStyle(.borderless).accessibilityLabel(SDKStrings.text("chart.close_inspection", locale: locale))
            }
            BoundedContentScroll(maximumHeight: 320) {
                VStack(alignment: .leading, spacing: theme.innerSpacing) {
                    ForEach(inspectedPoints(data)) { point in
                        ChartValueRow(label: point.series, value: formatted(point.value))
                    }
                }
            }
        }.font(theme.bodyFont).padding(theme.groupSpacing).frame(minWidth: 200, idealWidth: 240, maxWidth: 300).tint(theme.actionAccent)
        if #available(iOS 16.4, macOS 13.3, *) { content.presentationCompactAdaptation(.popover) }
        else { content }
    }
    private func cartesian(_ data: ChartData) -> some View {
        let styles = drawingStyles(data)
        return Charts.Chart(data.points) { point in
            if point.label == selectedLabel, point.id == data.points.first(where: { $0.label == selectedLabel })?.id {
                if kind == "scatter" {
                    RuleMark(x: .value(SDKStrings.text("chart.selected", locale: locale), point.x ?? 0)).foregroundStyle(theme.secondaryText.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                } else {
                    RuleMark(x: .value(SDKStrings.text("chart.selected", locale: locale), point.label)).foregroundStyle(theme.secondaryText.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                }
            }
            if kind == "scatter" {
                PointMark(x: .value(data.xKey, point.x ?? 0), y: .value(point.series, point.value))
                    .foregroundStyle(by: .value(SDKStrings.text("chart.series", locale: locale), point.series)).symbol(by: .value(SDKStrings.text("chart.series", locale: locale), point.series))
                    .accessibilityLabel(point.label + "，" + point.series).accessibilityValue(formatted(point.value))
            } else if kind == "line" {
                LineMark(x: .value(data.xKey, point.label), y: .value(SDKStrings.text("chart.value", locale: locale), point.value), series: .value(SDKStrings.text("chart.segment", locale: locale), point.segmentKey))
                    .foregroundStyle(by: .value(SDKStrings.text("chart.series", locale: locale), point.series)).symbol(by: .value(SDKStrings.text("chart.series", locale: locale), point.series))
                    .accessibilityLabel(point.label + "，" + point.series).accessibilityValue(formatted(point.value))
            } else if kind == "area" {
                AreaMark(x: .value(data.xKey, point.label), y: .value(SDKStrings.text("chart.value", locale: locale), point.value), stacking: context.flag("stacked") == true ? .standard : .unstacked)
                    .foregroundStyle(by: .value(SDKStrings.text("chart.segment", locale: locale), point.segmentKey)).opacity(0.35)
                    .accessibilityLabel(point.label + "，" + point.series).accessibilityValue(formatted(point.value))
            } else if context.flag("stacked") == true {
                BarMark(x: .value(data.xKey, point.label), y: .value(SDKStrings.text("chart.value", locale: locale), point.value))
                    .foregroundStyle(by: .value(SDKStrings.text("chart.series", locale: locale), point.series))
                    .accessibilityLabel(point.label + "，" + point.series).accessibilityValue(formatted(point.value))
            } else {
                BarMark(x: .value(data.xKey, point.label), y: .value(SDKStrings.text("chart.value", locale: locale), point.value))
                    .foregroundStyle(by: .value(SDKStrings.text("chart.series", locale: locale), point.series)).position(by: .value(SDKStrings.text("chart.series", locale: locale), point.series))
                    .accessibilityLabel(point.label + "，" + point.series).accessibilityValue(formatted(point.value))
            }
        }
        .modifier(ChartCategoryDomain(categories: data.labels, numeric: kind == "scatter"))
        .chartOverlay { proxy in
            GeometryReader { geometry in
              ZStack(alignment: .topLeading) {
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { inspect(at: $0.location, proxy: proxy, geometry: geometry, data: data) })
                    .simultaneousGesture(DragGesture(minimumDistance: 16).onChanged { value in
                        if abs(value.translation.width) > abs(value.translation.height) { inspect(at: value.location, proxy: proxy, geometry: geometry, data: data) }
                    })
                    .onContinuousHover { phase in
                        if case .active(let location) = phase { inspect(at: location, proxy: proxy, geometry: geometry, data: data) }
                    }
                    .accessibilityHidden(true)
                if let point = inspectedPoints(data).first,
                   let x = kind == "scatter" ? proxy.position(forX: point.x ?? 0) : proxy.position(forX: point.label),
                   let y = proxy.position(forY: point.value) {
                    Color.clear.frame(width: 1, height: 1)
                        .position(x: geometry[proxy.plotAreaFrame].minX + x, y: geometry[proxy.plotAreaFrame].minY + y)
                        .popover(isPresented: $inspectionPresented, arrowEdge: .bottom) { popover(data) }
                }
              }
            }
        }
        .chartForegroundStyleScale(domain: styles.map(\.0), range: styles.map(\.1))
        .chartLegend(.hidden)
        .chartXAxis { AxisMarks { _ in
            AxisValueLabel().font(ChartMetrics.axisFont).foregroundStyle(ChartMetrics.labelColor)
        } }
        .chartYAxis { AxisMarks(position: .leading) { value in
            AxisGridLine().foregroundStyle(theme.separator)
            AxisValueLabel { if let number = value.as(Double.self) {
                Text(ChartData.axisLabel(number, kind: context.string("format"), currency: context.string("currency"), locale: locale))
                    .font(ChartMetrics.axisFont).foregroundStyle(ChartMetrics.labelColor)
            } }
        } }
    }
    private func drawingStyles(_ data: ChartData) -> [(String, Color)] {
        let palette = theme.chartColors.isEmpty ? [.blue] : theme.chartColors
        let colors = Dictionary(uniqueKeysWithValues: data.series.enumerated().map { ($0.element, palette[$0.offset % palette.count]) })
        if kind != "area" { return data.series.map { ($0, colors[$0] ?? .blue) } }
        var seen = Set<String>()
        return data.points.compactMap { point in
            guard seen.insert(point.segmentKey).inserted else { return nil }
            return (point.segmentKey, colors[point.series] ?? .blue)
        }
    }
    private func seriesLegend(_ data: ChartData) -> some View {
        WrappingRowLayout(gap: theme.groupSpacing, alignment: "center", justification: "start", wraps: true) {
            ForEach(Array(data.series.enumerated()), id: \.element) { index, series in
                HStack(spacing: theme.spacingUnit) {
                    Circle().fill((theme.chartColors.isEmpty ? [.blue] : theme.chartColors)[index % max(1, theme.chartColors.count)]).frame(width: 8, height: 8)
                    Text(series)
                }
            }
        }.font(ChartMetrics.legendFont).foregroundStyle(ChartMetrics.labelColor)
    }
    private func inspect(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy, data: ChartData) {
        let frame = geometry[proxy.plotAreaFrame]
        guard frame.contains(location) else { return }
        let x = location.x - frame.minX
        if kind == "scatter", let value: Double = proxy.value(atX: x), let label = ChartInspection.nearest(to: value, points: data.points) {
            select(label)
        } else if let label: String = proxy.value(atX: x) { select(label) }
    }
    private func detail(_ data: ChartData) -> some View {
        VStack(alignment: .leading, spacing: theme.innerSpacing) {
            ForEach(data.entries) { entry in
                ChartValueRow(label: entry.label + (data.series.count > 1 ? " · " + entry.series : ""),
                              value: entry.value.map(formatted) ?? SDKStrings.text("chart.missing_value", locale: locale))
            }
        }.font(theme.secondaryFont)
    }
}

private struct ChartCategoryDomain: ViewModifier {
    let categories: [String]
    let numeric: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if numeric { content } else { content.chartXScale(domain: categories) }
    }
}

private struct ChartValueRow: View {
    let label: String
    let value: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.intelligentUITheme) private var theme
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize { stacked }
            else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: theme.innerSpacing) {
                        Text(label).fixedSize(horizontal: true, vertical: true)
                        Spacer(minLength: theme.innerSpacing)
                        Text(value).monospacedDigit().fixedSize(horizontal: true, vertical: true)
                    }
                    stacked
                }
            }
        }.accessibilityElement(children: .combine)
    }
    private var stacked: some View {
        VStack(alignment: .leading, spacing: theme.spacingUnit) {
            Text(label).foregroundStyle(theme.secondaryText)
            Text(value).monospacedDigit()
        }.fixedSize(horizontal: false, vertical: true)
    }
}

private struct NativePie: View {
    @Environment(\.locale) private var locale
    let points: [ChartData.Point]
    let donut: Bool
    let selected: String?
    let plotHeight: CGFloat
    let interactive: Bool
    let formatted: (Double) -> String
    let select: (String) -> Void
    @Environment(\.intelligentUITheme) private var theme
    private var colors: [Color] { theme.chartColors.isEmpty ? [.blue] : theme.chartColors }
    var body: some View {
        let total = points.reduce(0) { $0 + $1.value }
        if total > 0 && total.isFinite {
            VStack(alignment: .leading, spacing: theme.innerSpacing) {
              Canvas { canvas, size in
                let radius = min(size.width, size.height) / 2
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                var angle = -90.0
                for (index, point) in points.enumerated() {
                    let end = angle + point.value / total * 360
                    var path = Path()
                    if donut {
                        path.addArc(center: center, radius: radius * 0.8, startAngle: .degrees(angle), endAngle: .degrees(end), clockwise: false)
                        canvas.stroke(path, with: .color(colors[index % colors.count].opacity(selected == nil || selected == point.id ? 1 : 0.45)), style: StrokeStyle(lineWidth: radius * 0.35))
                    } else {
                        path.move(to: center)
                        path.addArc(center: center, radius: radius * 0.95, startAngle: .degrees(angle), endAngle: .degrees(end), clockwise: false)
                        path.closeSubpath()
                        canvas.fill(path, with: .color(colors[index % colors.count].opacity(selected == nil || selected == point.id ? 1 : 0.45)))
                    }
                    angle = end
                }
              }
              .overlay { GeometryReader { geometry in
                  Color.clear.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { value in
                      if let point = ChartInspection.sectorPoint(at: value.location, size: geometry.size, points: points, donut: donut) { select(point.id) }
                  }).accessibilityHidden(true)
              } }
              .frame(height: plotHeight)
              .accessibilityLabel(SDKStrings.text("chart.proportion_summary", locale: locale, points.count))
              if points.count > 8 {
                  DisclosureGroup(SDKStrings.text("chart.all_categories", locale: locale, points.count)) { legend }
              } else { legend }
            }
        } else { Text(SDKStrings.text("chart.empty_proportions", locale: locale)).foregroundStyle(theme.secondaryText) }
    }
    private var legend: some View {
        VStack(alignment: .leading, spacing: theme.spacingUnit) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                Button { select(point.id) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: theme.innerSpacing) {
                        Circle().fill(colors[index % colors.count]).frame(width: 8, height: 8).accessibilityHidden(true)
                        ChartValueRow(label: point.label, value: formatted(point.value))
                        Image(systemName: "checkmark").opacity(selected == point.id ? 1 : 0).accessibilityHidden(true)
                    }.frame(maxWidth: .infinity, minHeight: theme.minimumControlHeight, alignment: .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(QuietControlStyle()).disabled(!interactive)
                    .font(ChartMetrics.legendFont).foregroundStyle(ChartMetrics.labelColor)
                    .accessibilityLabel(point.label + "，" + formatted(point.value))
                    .accessibilityAddTraits(selected == point.id ? [.isSelected] : [])
            }
        }
    }
}

enum ChartInspection {
    static func nearest(to x: Double, points: [ChartData.Point]) -> String? {
        points.filter { $0.x != nil }.min { abs(($0.x ?? 0) - x) < abs(($1.x ?? 0) - x) }?.label
    }
    static func sector(at point: CGPoint, size: CGSize, points: [ChartData.Point], donut: Bool) -> String? {
        sectorPoint(at: point, size: size, points: points, donut: donut)?.label
    }
    static func sectorPoint(at point: CGPoint, size: CGSize, points: [ChartData.Point], donut: Bool) -> ChartData.Point? {
        let dx = point.x - size.width / 2, dy = point.y - size.height / 2
        let radius = min(size.width, size.height) / 2
        let distance = hypot(dx, dy)
        guard radius > 0, distance <= radius * 0.98, !donut || distance >= radius * 0.6 else { return nil }
        let total = points.reduce(0) { $0 + max(0, $1.value) }
        guard total > 0, total.isFinite else { return nil }
        var angle = atan2(dy, dx) * 180 / .pi + 90
        if angle < 0 { angle += 360 }
        var end = 0.0
        for point in points {
            end += max(0, point.value) / total * 360
            if angle < end { return point }
        }
        return nil
    }
}
