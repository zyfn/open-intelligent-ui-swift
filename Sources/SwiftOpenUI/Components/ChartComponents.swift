import SwiftLang
import SwiftUI

/// Canvas renders chart families on the package's supported platforms. All chart families
/// use actual plotted geometry, with axes, legends, pointer inspection and
/// complete VoiceOver data, including negative and degenerate domains.
struct NativeChart: View {
  let context: OpenUIComponentContext
  @Environment(\.locale) private var locale
  @Environment(\.layoutDirection) private var direction
  @State private var visibility = NativeChartVisibility()
  @State private var inspected: Int?
  @State private var inspectionLocation = CGPoint.zero
  @State private var pinnedInspection = false
  @State private var stableData: NativeChartData?
  @State private var progressiveData: NativeChartData?
  @State private var presentationCache = NativeChartPresentationCache()
  @State private var axisMeasurements = NativeChartAxisMeasurements()
  @State private var showsDataDetails = false
  @ScaledMetric(relativeTo: NativeTextRole.caption.textStyle) private var axisScale: CGFloat = 1
  @ScaledMetric(relativeTo: NativeTextRole.control.textStyle) private var controlScale: CGFloat = 1
  @ScaledMetric(relativeTo: .body) private var legendMarkerSize: CGFloat = 8
  @Namespace private var measurementScope
  private var name: String { context.element.typeName }
  private var currentData: NativeChartData { presentationCache.values(context).current }
  private var waiting: Bool { !context.hasDataFailure && (context.hasPendingData || (context.isStreaming && !context.element.isSourceComplete)) }
  private var incomplete: Bool { !context.isStreaming && (!context.element.isSourceComplete || context.hasInterruptedData) && !context.hasPendingData }
  private var allData: NativeChartData {
    if context.hasPendingData || context.hasDataFailure, let stableData { return stableData }
    if context.element.isSourceComplete { return currentData }
    return stableData ?? presentationCache.values(context).staged
      ?? progressiveData ?? NativeChartData()
  }
  private var data: NativeChartData { allData.excluding(visibility.hidden, for: name) }
  private var palette: [Color] {
    context.theme.chartColors(forSeriesCount: legend.count, chartType: name)
  }
  private var legend: [String] { allData.legendNames(for: name) }
  private struct LegendEntry: Identifiable {
    let id: Int
    let index: Int
    let title: String
  }
  private var legendEntries: [LegendEntry] {
    legend.enumerated().map { .init(id: allData.colorIndex(at: $0.offset), index: $0.offset, title: $0.element) }
  }
  private var showsLegend: Bool {
    legend.count > 1 || ["PieChart", "RadialChart", "SingleStackedBarChart"].contains(name)
  }
  private var drawing: NativeChartDrawing {
    NativeChartDrawing(
      data: data, name: name, variant: context.presentationString("variant"),
      semi: context.presentationString("appearance") == "semiCircular", palette: palette,
      secondary: context.theme.textNeutralSecondary, border: context.theme.borderDefault,
      gridColor: context.presentation.chartGrid, axisColor: context.presentation.chartAxis,
      canvasColor: context.theme.background, labelFont: context.theme.textStyle(.caption).font.nativeFont(scale: axisScale),
      inspected: inspected, axisScale: axisScale,
      singleStackedBarThickness: context.presentation.singleStackedBarThickness * axisScale,
      axisMeasurements: axisMeasurements,
      hasYAxisTitle: context.string("yLabel")?.isEmpty == false)
  }
  private var measuredAxisLabels: some View {
    let labels = drawing.axisLabels
    let left = name == "HorizontalBarChart" ? [] : labels.left
    let style = context.theme.textStyle(.caption)
    return HStack(spacing: 0) {
      ForEach(Array((left + labels.bottom).enumerated()), id: \.offset) { index, label in
        Text(label).nativeTextStyle(style).monospacedDigit()
          .lineLimit(1).fixedSize()
          .background(GeometryReader { geometry in
            Color.clear.preference(key: NativeChartAxisMeasurementKey.self, value: [measurementScope:
              NativeChartAxisMeasurements(
                leftWidth: index < left.count ? geometry.size.width : 0,
                bottomWidth: index >= left.count ? geometry.size.width : 0,
                lineHeight: max(geometry.size.height, style.font.measuredLineHeight(scale: axisScale)))])
          })
      }
    }.fixedSize().hidden().allowsHitTesting(false).accessibilityHidden(true)
  }
  /// Touch scrolling stays native; a tap inspects a point and a touch-and-hold
  /// opens the chart's data menu. Desktop pointer dragging inspects the plot.
  @ViewBuilder var body: some View {
    Group {
      if !allData.hasContent(for: name) {
        NativePendingContent(loading: waiting, message: "Loading data",
          terminalMessage: context.hasDataFailure ? "Unable to load chart"
            : allData.invalidData ? "Chart data is invalid" : incomplete ? "Chart is incomplete" : "No data")
      } else { chartBody }
    }
    .onAppear(perform: rememberStableData)
    .onChange(of: ObjectIdentifier(context.element)) { _ in rememberStableData() }
    .onChange(of: context.hasPendingData) { _ in rememberStableData() }
  }

  private func rememberStableData() {
    if context.element.isSourceComplete && !context.hasPendingData && !context.hasDataFailure {
      if stableData != currentData { stableData = currentData }
    } else if let next = presentationCache.values(context).staged, progressiveData != next { progressiveData = next }
  }

  private var chartBody: some View {
    chartContent
      .sheet(isPresented: $showsDataDetails) {
        NativeChartDataDetails(data: allData, palette: palette, theme: context.theme,
          locale: locale, selectedIndex: visibility.hidden.isEmpty ? inspected : nil)
      }
  }

  private var dataDetailsAction: some View {
    Button { showsDataDetails = true } label: {
      Label {
        Text("View chart data", bundle: NativeControlResources.bundle)
      } icon: { Image(systemName: "list.bullet.rectangle") }
    }
    .accessibilityIdentifier("openui.chart.data-details")
  }

  private var chartContent: some View {
    VStack(alignment: .leading, spacing: context.theme.spaceM) {
      NativeChartPlotLayout(drawing: drawing, explicitHeight: context.presentationNumber("height"),
        defaultHeight: defaultHeight) {
        GeometryReader { geometry in
          Canvas { canvas, size in
            drawing.draw(
              in: &canvas, size: size, xLabel: context.string("xLabel"),
              yLabel: context.string("yLabel"))
          }
          .lineLimit(1).truncationMode(.middle)
          .contentShape(Rectangle())
          .modifier(NativeChartInteraction { point, pinned in
            let next = point.flatMap { drawing.inspectionIndex(at: $0, size: geometry.size) }
            if pinned && pinnedInspection && next == inspected { inspected = nil; pinnedInspection = false }
            else {
              inspected = next; pinnedInspection = pinned
              if let point {
                let origin = geometry.frame(in: .named(measurementScope)).origin
                inspectionLocation = CGPoint(x: origin.x + point.x, y: origin.y + point.y)
              }
            }
          })
          .accessibilityIdentifier("openui-chart-" + name)
          .accessibilityLabel([name, context.string("xLabel"), context.string("yLabel")]
            .compactMap { $0 }.joined(separator: ", "))
          .accessibilityChildren {
            ForEach(Array(data.accessibilityRows.enumerated()), id: \.offset) { _, row in Text(row) }
          }
          .accessibilityActions { dataDetailsAction }
          .overlay(alignment: .topLeading) {
            if ["BarChart", "LineChart", "AreaChart"].contains(name) {
              NativeChartCategoryAxis(labels: data.labels, layout: drawing.layout(geometry.size), theme: context.theme)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .allowsHitTesting(false).accessibilityHidden(true)
            }
            if name == "RadarChart" {
              NativeRadarLabels(labels: data.labels, theme: context.theme, scale: axisScale)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .allowsHitTesting(false).accessibilityHidden(true)
            }
          }
          .overlay(alignment: .topTrailing) {
            NativeDelayedPresentation(active: waiting && allData.hasContent(for: name)) { visible in
              if visible { NativeLoadingIndicator().padding(context.theme.space2xs) }
            }
          }
          .overlay {
            if data.hasZeroTotal(for: name) {
              Text("Total is zero", bundle: NativeControlResources.bundle)
                .nativeTextStyle(context.theme.textStyle(.supporting))
                .fixedSize(horizontal: false, vertical: true)
                .padding(context.theme.spaceM).allowsHitTesting(false)
            }
          }
          .accessibilityValue(Text(waiting ? "Loading data" : incomplete ? "Chart is incomplete"
            : data.hasZeroTotal(for: name) ? "Total is zero" : "", bundle: NativeControlResources.bundle))
          .allowsHitTesting(data.hasContent(for: name))
        }
        .environment(\.layoutDirection, direction)
        if name == "HorizontalBarChart" {
          // Position is the category identity, including repeated source labels.
          // These are the visible labels, measured synchronously by the plot layout.
          ForEach(Array(data.labels.enumerated()), id: \.offset) { _, label in
            Text(label).nativeTextStyle(context.theme.textStyle(.caption), color: context.presentation.chartAxis)
              .monospacedDigit()
              .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
              .multilineTextAlignment(direction == .rightToLeft ? .leading : .trailing)
              .environment(\.layoutDirection, direction)
              .allowsHitTesting(false).accessibilityHidden(true)
          }
        }
      }
        // Plot placement and inspection use physical coordinates. Keep the
        // layout from mirroring them; each text-bearing child keeps the host's
        // writing direction through its own environment above.
        .environment(\.layoutDirection, .leftToRight)
        // The data menu also covers an empty plot after all series are hidden.
        .contentShape(Rectangle())
        .contextMenu { dataDetailsAction }
      if name == "RadarChart" {
        NativeRadarCategoryKey(labels: data.labels, theme: context.theme)
      }
      if showsLegend {
        // Legend items already own vertical padding and their full control target.
        NativeChartLegendLayout(rightToLeft: direction == .rightToLeft) {
          ForEach(legendEntries) { entry in
            let index = entry.index
            let title = entry.title
            if name == "SingleStackedBarChart" {
              legendLabel(index: index, title: title).accessibilityElement(children: .combine)
            } else {
              Button { visibility.toggle(title, current: legend) } label: {
                legendLabel(index: index, title: title).openUIControlTarget(alignment: .leading)
              }
                .buttonStyle(NativeQuietButtonStyle(theme: context.theme))
                .opacity(visibility.hidden.contains(OpenUIString(title)) ? 0.3 : 1)
                .accessibilityLabel(title)
                .accessibilityValue(visibility.hidden.contains(OpenUIString(title))
                  ? Text("Hidden", bundle: NativeControlResources.bundle) : Text("Visible", bundle: NativeControlResources.bundle))
                .accessibilityIdentifier("openui.chart.legend." + title)
            }
          }
        }
        // These chart families always own a legend control region. Reserve its
        // minimum target before labels/values arrive, without fabricating any
        // legend entries. Longer real legends can still wrap naturally.
        .frame(minHeight: ["PieChart", "RadialChart"].contains(name)
          ? max(context.presentation.minimumControlTargetSize,
            context.theme.textLabelSm.resolved(for: .control).measuredLineHeight(scale: controlScale) + 12) : nil)
      }
      if allData.hasContent(for: name), incomplete || context.hasDataFailure {
        Text(context.hasDataFailure ? (stableData == nil ? "Unable to load chart" : "Unable to refresh chart")
          : "Chart is incomplete", bundle: NativeControlResources.bundle)
          .nativeTextStyle(context.theme.textStyle(.supporting))
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
      .coordinateSpace(name: measurementScope)
      .background(alignment: .topLeading) { measuredAxisLabels }
      // Inspection stays within the chart; complete data remains available
      // through the plot's context menu and accessibility action.
      .overlay(alignment: .topLeading) {
        GeometryReader { geometry in
          if let inspected, let details = data.inspection(at: inspected, locale: locale) {
            NativeChartTooltip(details: details, palette: palette,
              anchor: inspectionLocation, bounds: geometry.size, theme: context.theme)
          }
        }.allowsHitTesting(false)
      }
      .zIndex(inspected == nil ? 0 : 1)
      .onPreferenceChange(NativeChartAxisMeasurementKey.self) { measurements in
        let next = measurements[measurementScope] ?? NativeChartAxisMeasurements()
        if next != axisMeasurements { axisMeasurements = next }
      }
      .onChange(of: data.accessibilityRows) { _ in inspected = nil; pinnedInspection = false }
  }
  private var defaultHeight: Double {
    if name == "SingleStackedBarChart" {
      return Double(max(context.presentation.minimumControlTargetSize,
        context.presentation.singleStackedBarThickness + context.theme.spaceS * 2))
    }
    if ["PieChart", "RadialChart"].contains(name) { return 210 }
    return 250
  }
  private func legendLabel(index: Int, title: String) -> some View {
    HStack(spacing: context.theme.spacing("xs")) {
      if ["LineChart", "AreaChart"].contains(name) {
        Path { path in
          path.move(to: CGPoint(x: 0, y: legendMarkerSize / 2))
          path.addLine(to: CGPoint(x: legendMarkerSize * 3, y: legendMarkerSize / 2))
        }
        .stroke(palette[allData.colorIndex(at: index) % palette.count],
          style: StrokeStyle(lineWidth: 2, lineCap: .round,
            dash: NativeChartSeriesStyle.dash(for: allData.colorIndex(at: index))))
        .frame(width: legendMarkerSize * 3, height: legendMarkerSize).accessibilityHidden(true)
      } else {
        Circle()
          .fill(palette[allData.colorIndex(at: index) % palette.count])
          .frame(width: legendMarkerSize, height: legendMarkerSize).accessibilityHidden(true)
      }
      Text(title).openUIFont(context.theme.textLabelSm, role: .control).foregroundStyle(context.theme.textNeutralSecondary)
        .fixedSize(horizontal: false, vertical: true)
      if ["PieChart", "RadialChart"].contains(name), allData.slices.indices.contains(index) {
        Text(NativeChartNumber.tooltip(allData.slices[index], locale: locale))
          .openUIFont(context.theme.textLabelSm.weight(.semibold)).monospacedDigit().layoutPriority(1)
      } else if name == "SingleStackedBarChart", allData.slices.indices.contains(index) {
        Text(NativeChartNumber.percentage(allData.slices[index], total: allData.slices.reduce(0, +)))
          .openUIFont(context.theme.textLabelSm, role: .control).monospacedDigit()
      }
    }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
  }

}

private struct NativeRadarLabelSizes: PreferenceKey {
  static let defaultValue: [Int: CGSize] = [:]
  static func reduce(value: inout [Int: CGSize], nextValue: () -> [Int: CGSize]) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}

private struct NativeRadarLabels: View {
  let labels: [String]
  let theme: OpenUIThemeValues
  let scale: CGFloat
  @ScaledMetric(relativeTo: NativeTextRole.detail.textStyle) private var textScale: CGFloat = 1
  @State private var sizes: [Int: CGSize] = [:]
  var body: some View {
    GeometryReader { geometry in
      let style = theme.textStyle(.supporting)
      let projection = NativeRadarGeometry(size: geometry.size, scale: scale)
      let frames = NativeRadarLabelPlacement.frames(size: geometry.size, count: labels.count,
        sizes: sizes, scale: scale,
        lineHeight: style.font.measuredLineHeight(scale: textScale))
      ZStack(alignment: .topLeading) {
        ForEach(projection.labelIndices(count: labels.count), id: \.self) { index in
          let frame = frames[index]
          Text("\(index + 1)").nativeTextStyle(style).monospacedDigit().fixedSize()
            .background(GeometryReader { measured in
              Color.clear.preference(key: NativeRadarLabelSizes.self, value: [index: measured.size])
            })
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        }
      }
    }
    .onPreferenceChange(NativeRadarLabelSizes.self) { if $0 != sizes { sizes = $0 } }
  }
}

struct NativeRadarCategoryKey: View {
  let labels: [String]
  let theme: OpenUIThemeValues
  @Environment(\.layoutDirection) private var direction
  var body: some View {
    NativeChartLegendLayout(gap: theme.spaceM, rightToLeft: direction == .rightToLeft) {
      ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
        HStack(alignment: .firstTextBaseline, spacing: theme.spaceXs) {
          Text("\(index + 1)").nativeTextStyle(theme.textStyle(.supporting)).monospacedDigit()
          Text(label).nativeTextStyle(theme.textStyle(.compactBody)).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, theme.space3xs)
      }
    }.accessibilityHidden(true) // The chart already exposes complete category/value rows.
  }
}

/// Category text uses native text layout rather than Canvas's inherited
/// one-line environment. The plot and inspection share the same geometry.
struct NativeChartCategoryAxis: View {
  @Environment(\.layoutDirection) private var textDirection
  @Environment(\.openUIPresentation) private var nativePresentation

  let labels: [String]
  let layout: NativeChartLayout
  let theme: OpenUIThemeValues
  var body: some View {
    ZStack(alignment: .topLeading) {
      ForEach(layout.categoryLabels(count: labels.count), id: \.index) { label in
        Text(labels[label.index]).openUIFont(theme.textBodySm, role: .detail).monospacedDigit()
          .foregroundStyle(nativePresentation.chartAxis).lineLimit(layout.categoryLabelLines).truncationMode(.tail)
          .multilineTextAlignment(textAlignment(for: label.anchor))
          .environment(\.layoutDirection, textDirection)
          .frame(width: label.width, alignment: Alignment(horizontal:
            label.anchor.x == 0 ? .leading : label.anchor.x == 1 ? .trailing : .center, vertical: .top))
          .fixedSize(horizontal: false, vertical: true)
          .offset(x: label.x - label.width * label.anchor.x,
            y: layout.rect.maxY + (layout.categoryLabelLines > 1 ? 6 * layout.scale : layout.tickOffset - layout.lineHeight / 2))
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      // Canvas and inspection use physical x coordinates. Only the label
      // container is LTR; text shaping keeps the caller's writing direction.
      // Mirroring just this overlay associates categories with the wrong data.
      .environment(\.layoutDirection, .leftToRight)
  }
  private func textAlignment(for anchor: UnitPoint) -> TextAlignment {
    guard anchor.x != 0.5 else { return .center }
    let physicalLeft = anchor.x == 0
    return physicalLeft == (textDirection == .leftToRight) ? .leading : .trailing
  }
}

private struct NativeChartTooltip: View {
  let details: NativeChartInspection
  let palette: [Color]
  let anchor: CGPoint
  let bounds: CGSize
  let theme: OpenUIThemeValues
  var body: some View {
    NativeChartTooltipLayout(anchor: anchor, bounds: bounds) {
      ViewThatFits(in: .vertical) {
        NativeChartInspectionContent(details: details, palette: palette, theme: theme)
          .fixedSize(horizontal: false, vertical: true)
          .modifier(NativeOverlaySurface(theme: theme, compact: true))
        // A bounded inspection never covers neighboring content. The chart's
        // menu and accessibility action retain access to the complete values.
        Color.clear.frame(width: 0, height: 0)
      }
      .accessibilityIdentifier("openui-chart-inspection")
    }.allowsHitTesting(false)
  }
}

/// The inspection overlay and full data reader share the same complete values.
struct NativeChartInspectionContent: View {
  let details: NativeChartInspection
  let palette: [Color]
  let theme: OpenUIThemeValues
  @Environment(\.displayScale) private var displayScale
  @ScaledMetric(relativeTo: .body) private var markerSize: CGFloat = 9
  var body: some View {
    VStack(alignment: .leading, spacing: theme.spacing("sm")) {
      if !details.title.isEmpty {
        HStack(spacing: theme.spacing("s")) {
          if let index = details.colorIndex { marker(index) }
          Text(details.title).openUIFont(theme.textBodySmHeavy, role: .detail)
            .foregroundStyle(theme.textNeutralPrimary).fixedSize(horizontal: false, vertical: true)
        }
        Rectangle().fill(theme.borderDefault).frame(height: 1 / displayScale)
      }
      VStack(alignment: .leading, spacing: theme.spacing("s")) {
        ForEach(details.rows) { row in
          HStack(alignment: .firstTextBaseline, spacing: theme.spacing("s")) {
            if let index = row.colorIndex { marker(index) }
            Group {
              if let label = row.label { Text(label) }
              else { Text("Value", bundle: NativeControlResources.bundle) }
            }.foregroundStyle(theme.textNeutralSecondary)
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(row.value).monospacedDigit().foregroundStyle(theme.textNeutralPrimary)
              .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
              .layoutPriority(1)
          }.accessibilityElement(children: .combine)
        }
      }.openUIFont(theme.textBodySm, role: .detail)
    }
      .padding(theme.spaceM)
      .accessibilityElement(children: .contain)
  }
  private func marker(_ index: Int) -> some View {
    RoundedRectangle(cornerRadius: 2)
      .fill(palette.isEmpty ? theme.interactiveAccentDefault : palette[max(0, index) % palette.count])
      .frame(width: markerSize, height: markerSize)
      .accessibilityHidden(true)
  }
}

private struct NativeChartTooltipLayout: Layout {
  let anchor: CGPoint
  let bounds: CGSize
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { bounds }
  func placeSubviews(in rect: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    guard let view = subviews.first else { return }
    // Give ViewThatFits a real vertical budget. Larger inspections remain
    // available in the data reader instead of covering neighboring content.
    let size = view.sizeThatFits(ProposedViewSize(width: min(240, max(1, bounds.width - 16)),
      height: max(0, min(320, bounds.height - 16))))
    let frame = NativeChartTooltipPlacement.frame(size: size, anchor: anchor, bounds: bounds)
    view.place(at: CGPoint(x: rect.minX + frame.minX, y: rect.minY + frame.minY), anchor: .topLeading,
      proposal: ProposedViewSize(frame.size))
  }
}

private struct NativeChartAxisMeasurementKey: PreferenceKey {
  static let defaultValue: [Namespace.ID: NativeChartAxisMeasurements] = [:]
  static func reduce(value: inout [Namespace.ID: NativeChartAxisMeasurements], nextValue: () -> [Namespace.ID: NativeChartAxisMeasurements]) {
    value.merge(nextValue(), uniquingKeysWith: { $0.merging($1) })
  }
}
