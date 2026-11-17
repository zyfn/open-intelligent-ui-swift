import SwiftLang
import SwiftUI
import Combine


struct NativeSeparator: View {
    let context: OpenUIComponentContext
    @Environment(\.displayScale) private var displayScale
    @ViewBuilder var body: some View {
        Group {
            if context.string("orientation") == "vertical" {
                Rectangle().fill(context.theme.borderDefault).frame(width: 1 / displayScale).frame(minHeight: 18)
            } else {
                Rectangle().fill(context.theme.borderDefault).frame(height: 1 / displayScale)
            }
        }.accessibilityHidden(context.flag("decorative") ?? true)
    }
}

struct NativeMetric: View {
    let context: OpenUIComponentContext
    var inline: Bool
    @Environment(\.multilineTextAlignment) private var textAlignment
    var body: some View {
        Group {
            if inline {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: context.theme.spacing("s")) {
                        value.fixedSize(horizontal: true, vertical: true)
                        details
                    }
                    VStack(alignment: textAlignment == .center ? .center : .leading,
                      spacing: context.theme.spacing("2xs")) {
                        value; details
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: context.theme.spacing("2xs")) {
                    NativeWrappingRow(gap: context.theme.spaceS) {
                        value
                        comparison
                    }
                    subtitle
                }
            }
        }.accessibilityElement(children: .combine)
    }
    private var value: some View {
        NativeMetricValue(text: context.string("value") ?? "",
            font: inline ? context.theme.textNumbersDefaultHeavy : context.theme.textHeadingSm.monospacedDigit(),
            theme: context.theme)
    }
    @ViewBuilder private var details: some View {
        comparison
        subtitle
    }
    @ViewBuilder private var comparison: some View {
        if let previous = context.string("previousValue") {
            Text(previous).strikethrough().nativeTextStyle(context.theme.textStyle(.caption))
        }
        if case .object(let trend) = context.value("trend"), case .number(let number) = trend["value"],
            number.isFinite,
            case .string(let direction) = trend["direction"]
        {
            Label(
                number.formatted(.number.precision(.fractionLength(0...2))) + "%",
                systemImage: direction == "down" ? "arrow.down" : "arrow.up"
            )
            .nativeTextStyle(context.theme.textStyle(.caption))
        }
    }
    @ViewBuilder private var subtitle: some View {
        if let subtext = context.string("subtext") {
            Text(subtext).nativeTextStyle(context.theme.textStyle(.supporting))
        }
    }
}

/// Keep one amount intact. A rare wider-than-viewport value can be read by
/// horizontal scrolling; it is never split through its decimal or shrunk.
struct NativeMetricValue: View {
    let text: String
    let font: OpenUIFont
    let theme: OpenUIThemeValues
    @ScaledMetric(relativeTo: NativeTextRole.metric.textStyle) private var scale: CGFloat = 1
    private var label: some View { Text(text).openUIFont(font, role: .metric).monospacedDigit().fixedSize() }
    var body: some View {
        // These are text-only measurement candidates, without state, resources
        // or actions. Only the selected presentation is exposed to accessibility.
        ViewThatFits(in: .horizontal) {
            label
            ScrollView(.horizontal) { label }
                .frame(height: font.resolved(for: .metric).measuredLineHeight(scale: scale))
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(text)
    }
}

/// Upstream AccordionRenderer opens the newest item as the count grows, until
/// onValueChange records a user's open/close choice. Removals do not reset it.
struct NativeAccordionSelection {
    private(set) var selected: OpenUIString?
    private var userHasInteracted = false
    private var previousItemCount = 0
    mutating func choose(_ value: OpenUIString?) {
        userHasInteracted = true
        selected = value
    }
    mutating func reconcile(_ keys: [OpenUIString]) {
        if !userHasInteracted, keys.count > previousItemCount { selected = keys.last }
        previousItemCount = keys.count
    }
}

struct NativeAccordion: View {
    let context: OpenUIComponentContext
    @Environment(\.openUIUserInteraction) private var parentInteraction
    @Environment(\.openUIFormValidation) private var validation
    @Environment(\.displayScale) private var displayScale
    @State private var local = NativeAccordionSelection()
    private var items: [OpenUIRenderChild] { context.children("items") }
    private var keys: [OpenUIString] {
        items.compactMap { child in
            guard case .element(let item) = child.value else { return nil }
            return PropValue.codeUnitString(item, "value")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { child in
                if case .element(let item) = child.value, let key = PropValue.codeUnitString(item, "value")
                {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { local.selected == key },
                            set: { open in
                                local.choose(open ? key : nil)
                            })
                    ) {
                        context.render(PropValue.value(item, "content") ?? .null)
                            .padding(.top, context.theme.spacing("m"))
                            .environment(\.openUIUserInteraction, { local.choose(key); parentInteraction?() })
                            .simultaneousGesture(TapGesture().onEnded { local.choose(key); parentInteraction?() })
                    } label: {
                        Text(PropValue.string(item, "trigger") ?? "").nativeTextStyle(context.theme.textStyle(.fieldLabel))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, context.theme.spacing("l"))
                    if child.id != items.last?.id {
                        Rectangle().fill(context.theme.borderDefault).frame(height: 1 / displayScale)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .onAppear { local.reconcile(keys) }
        .onChange(of: keys) { updated in local.reconcile(updated) }
        .onReceive(validation?.$focusRequest.eraseToAnyPublisher() ?? Empty<NativeFormValidation.FocusRequest?, Never>().eraseToAnyPublisher()) { request in
            guard let name = request?.name else { return }
            for child in items {
                guard case .element(let item) = child.value,
                    let key = PropValue.codeUnitString(item, "value"),
                    NativeFormValidation.containsField(name, in: PropValue.value(item, "content") ?? .null) else { continue }
                local.choose(key); break
            }
        }
    }

}

struct NativeDataTable: View {
    struct Column: Identifiable {
        let id: String
        let title: String
        let data: [Value]
        let numeric: Bool
        let source: NativeSourceReadiness
    }
    let context: OpenUIComponentContext
    @Environment(\.openUITableCellPolicy) private var cellPolicy
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var minimumWidth: CGFloat = 88
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1
    @State private var availableWidth: CGFloat = 0
    @State private var currentPage = 0
    @State private var stableColumns: [Column]?
    @Namespace private var measurementScope
    private let pageSize = 10 // Pinned upstream Table's DEFAULT_PAGE_SIZE.
    private var tableAppearance: OpenUITableAppearance? { context.theme.tableAppearance }
    private var tableCellTheme: OpenUIThemeValues {
        var theme = context.theme
        if let font = tableAppearance?.bodyFont {
            theme.textBodyDefault = font
            theme.textBodyDefaultHeavy = font.weight(.medium)
            theme.textBodySm = font
            theme.textBodySmHeavy = font.weight(.medium)
        }
        return theme
    }
    private var columnGap: CGFloat { tableAppearance == nil ? context.theme.spacing("ml") : 0 }
    private var readsByRow: Bool { typeSize.isAccessibilitySize }
    private var currentColumns: [Column] {
        context.children("columns").compactMap { child in
            guard case .element(let element) = child.value else { return nil }
            let raw = PropValue.value(element, "data") ?? .null
            let data: [Value]
            if case .array(let values) = raw {
                data = values.values
            } else {
                data = raw == .null || raw == .undefined ? [] : [raw]
            }
            return Column(id: child.id, title: PropValue.string(element, "label") ?? "", data: data,
                numeric: PropValue.string(element, "type") == "number", source: element.sourceReadiness)
        }
    }
    private var waiting: Bool { !context.hasDataFailure && (context.hasPendingData || (context.isStreaming && !context.element.isSourceComplete)) }
    private var incomplete: Bool { !context.isStreaming && (!context.element.isSourceComplete || context.hasInterruptedData) && !context.hasPendingData }
    private var columns: [Column] {
        if !context.element.isSourceComplete || context.hasPendingData || context.hasDataFailure,
           let stableColumns { return stableColumns }
        return currentColumns
    }
    private func columnsReady(_ columns: [Column]) -> Bool {
        if stableColumns != nil { return true }
        let source = context.element.sourceReadiness["columns"]
        return source.complete || (source.closed && source.expectedCount == columns.count)
    }
    private func rowCount(in columns: [Column]) -> Int {
        let maximum = columns.map { $0.data.count }.max() ?? 0
        guard !context.element.isSourceComplete else { return maximum }
        for row in 0..<maximum {
            let ready = columns.allSatisfy { column in
                let source = column.source["data"]
                return source.complete || (row < column.data.count && source[row].complete)
                    || (source.closed && row >= column.data.count)
            }
            if !ready { return row }
        }
        return maximum
    }
    @ViewBuilder var body: some View {
        // Share one projection through this render. Completed tables still read
        // current data; stableColumns covers incomplete or unavailable data.
        let columns = self.columns
        Group {
            if columnsReady(columns) && !columns.isEmpty {
                loadedTable(columns: columns, rowCount: rowCount(in: columns))
            } else if waiting {
                NativePendingContent(loading: true, message: "Loading data")
            } else { stateMessage }
        }
        .onAppear(perform: rememberColumns)
        .onChange(of: context.element) { _ in rememberColumns() }
        .onChange(of: context.hasPendingData) { _ in rememberColumns() }
        .onChange(of: context.element.isSourceComplete) { _ in rememberColumns() }
    }
    private func rememberColumns() {
        if context.element.isSourceComplete && !context.hasPendingData && !context.hasDataFailure { stableColumns = currentColumns }
    }
    private var stateMessage: some View {
        Text(context.hasDataFailure ? (stableColumns == nil ? "Unable to load data" : "Unable to refresh data")
            : incomplete ? "Table is incomplete" : "No data", bundle: NativeControlResources.bundle)
            .nativeTextStyle(context.theme.textStyle(.supporting)).padding(.vertical, context.theme.spaceS)
    }
    private func loadedTable(columns: [Column], rowCount: Int) -> some View {
        let pageCount = max(1, (rowCount + pageSize - 1) / pageSize)
        let safePage = min(currentPage, pageCount - 1)
        let start = safePage * pageSize
        let visibleRows = start..<min(start + pageSize, rowCount)
        return VStack(alignment: .leading, spacing: context.theme.spacing("s")) {
            NativeTableViewport { tableContent(columns: columns, visibleRows: visibleRows) }
            if !waiting && (rowCount == 0 || incomplete || context.hasDataFailure) { stateMessage }
            if pageCount > 1 {
                NativePageControls(page: safePage, count: pageCount, enabled: true, identifier: "openui.table") { currentPage = $0 }
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: NativeTableWidthKey.self, value: [measurementScope: geometry.size.width])
            }
        )
        .onPreferenceChange(NativeTableWidthKey.self) { values in
            guard let width = values[measurementScope], width.isFinite, width > 0, abs(width - availableWidth) > 0.5 else { return }
            availableWidth = width
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("openui.table")
        .accessibilityValue(Text(waiting ? "Loading data" : "", bundle: NativeControlResources.bundle))
        .background {
            if let appearance = tableAppearance {
                RoundedRectangle(cornerRadius: appearance.cornerRadius ?? context.theme.radius3xl).fill(appearance.background)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: tableAppearance.map { $0.cornerRadius ?? context.theme.radius3xl } ?? 0))
        .overlay {
            if let appearance = tableAppearance {
                RoundedRectangle(cornerRadius: appearance.cornerRadius ?? context.theme.radius3xl)
                    .strokeBorder(appearance.gridLine, lineWidth: 0.5)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) {
            NativeDelayedPresentation(active: waiting) { visible in
                if visible { NativeLoadingIndicator().padding(context.theme.space2xs) }
            }
        }
        .environment(\.openUIInteractionScopeReady, context.canInteract && !context.hasPendingData && !context.hasDataFailure)
        .environment(\.openUIActionDensity, .compact)
    }
    private func tableLayout(columns: [Column]) -> AnyLayout {
        if readsByRow {
            return AnyLayout(NativeTableReadingLayout(columns: columns.count,
                width: max(minimumWidth, availableWidth), gap: context.theme.spaceXs,
                rowGap: context.theme.spaceM))
        }
        return AnyLayout(NativeDataTableLayout(
            columns: columns.count, width: max(minimumWidth, availableWidth),
            minimum: minimumWidth, gap: columnGap,
            columnMinimums: columns.map { $0.numeric ? minimumWidth : context.presentation.minimumTextColumnWidth * textScale }
        ))
    }
    @ViewBuilder private func tableContent(columns: [Column], visibleRows: Range<Int>) -> some View {
        let firstColumnID = columns.first?.id
        let lastColumnID = columns.last?.id
        let cellTheme = tableCellTheme
        // Layout changes preserve the cell subtree, including custom controls.
        tableLayout(columns: columns) {
            ForEach(columns) { column in
                Text(column.title).openUIFont(tableAppearance?.headerFont ?? context.theme.textBodySmHeavy, role: .control)
                    .foregroundStyle(context.theme.textNeutralPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .frame(minHeight: tableAppearance?.headerFont.map { $0.resolved(for: .body).measuredLineHeight(scale: textScale) }, alignment: .top)
                    .padding(.vertical, tableAppearance == nil ? context.theme.spaceS : context.theme.spaceM)
                    .padding(.horizontal, tableAppearance == nil ? 0 : context.theme.spaceS)
                    .multilineTextAlignment(column.numeric ? .trailing : .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: column.numeric ? .topTrailing : .topLeading)
                    .background { if let appearance = tableAppearance { appearance.headerBackground } }
                    .overlay(alignment: .trailing) {
                        if let appearance = tableAppearance, column.id != lastColumnID, !readsByRow {
                            appearance.gridLine.frame(width: 0.5).allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    .opacity(readsByRow ? 0 : 1).accessibilityHidden(readsByRow)
            }
            (tableAppearance?.gridLine ?? context.theme.borderDefault).frame(height: tableAppearance == nil ? 1 / displayScale : 0.5).layoutValue(key: NativeTableBoundaryKey.self, value: true)
                .opacity(readsByRow ? 0 : 1).accessibilityHidden(true)
            ForEach(visibleRows, id: \.self) { row in
                ForEach(columns) { column in
                    VStack(alignment: column.numeric && !readsByRow ? .trailing : .leading,
                        spacing: context.theme.space2xs) {
                        if readsByRow && !column.title.isEmpty {
                            Text(column.title).nativeTextStyle(context.theme.textStyle(.supporting))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        cell(column.data.indices.contains(row) ? column.data[row] : .null)
                            .openUIFont(column.numeric ? cellTheme.textBodyDefault.monospacedDigit() : cellTheme.textBodyDefault)
                            .environment(\.openUITheme, cellTheme)
                    }
                        .multilineTextAlignment(column.numeric && !readsByRow ? .trailing : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: tableAppearance?.bodyFont.map { $0.resolved(for: .body).measuredLineHeight(scale: textScale) }, alignment: .top)
                        .padding(.vertical, readsByRow ? context.theme.spaceXs : (tableAppearance == nil ? context.theme.spaceSM : context.theme.spaceM))
                        .padding(.horizontal, tableAppearance == nil ? 0 : context.theme.spaceS)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                            alignment: column.numeric && !readsByRow ? .topTrailing : .topLeading)
                        .background {
                            if let appearance = tableAppearance, !readsByRow {
                                column.id == firstColumnID ? appearance.headerBackground : appearance.background
                            }
                        }
                        .overlay(alignment: .trailing) {
                            if let appearance = tableAppearance, column.id != lastColumnID, !readsByRow {
                                appearance.gridLine.frame(width: 0.5).allowsHitTesting(false).accessibilityHidden(true)
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("openui.table.cell.\(row).\(column.id)")
                }
                if row < visibleRows.upperBound - 1 {
                    (tableAppearance?.gridLine ?? context.theme.borderDefault).frame(height: tableAppearance == nil ? 1 / displayScale : 0.5).layoutValue(key: NativeTableBoundaryKey.self, value: true)
                        .accessibilityHidden(true)
                }
            }
        }
    }
    @ViewBuilder private func cell(_ value: Value) -> some View {
        if case .boolean(let flag) = value {
            Text(flag ? "true" : "false")
        } else {
            context.renderTableCell(value, policy: cellPolicy)
        }
    }
}

/// Read-only and editable tables use native horizontal scrolling without
/// inserting helper copy into the surrounding document.
struct NativeTableViewport<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.horizontal) { content() }
            .scrollIndicators(.visible, axes: .horizontal)
    }
}

/// Every column receives one shared proposal before any row is measured.
/// Flexible columns share available space; intrinsic/fixed children can keep a
/// wider scrollable table. Nothing depends on the component type in a cell.
enum NativeTableColumnPlacement {
    static func widths(ideal: [CGFloat], minimum: CGFloat, available: CGFloat, gap: CGFloat, minimums: [CGFloat]? = nil) -> [CGFloat] {
        guard !ideal.isEmpty else { return [] }
        let available = available.isFinite ? max(0, available) : 0
        let floor = minimum.isFinite ? max(1, minimum) : 1
        let preferred = ideal.map { $0.isFinite ? max(1, $0) : floor }
        var widths = preferred.enumerated().map { index, value in
            let requested = minimums.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? floor
            return min(value, requested.isFinite ? max(1, requested) : floor)
        }
        var remaining = max(0, available - gap * CGFloat(ideal.count - 1) - widths.reduce(0, +))
        let order = preferred.indices.sorted { preferred[$0] < preferred[$1] }
        for (offset, index) in order.enumerated() {
            let target = preferred[index]
            let extra = min(max(0, target - widths[index]), remaining / CGFloat(order.count - offset))
            widths[index] += extra
            remaining -= extra
        }
        if remaining > 0 {
            for index in widths.indices { widths[index] += remaining / CGFloat(widths.count) }
        }
        return widths
    }
}

private struct NativeTableBoundaryKey: LayoutValueKey { static let defaultValue = false }

/// A user-selected reading arrangement of the original cells, without
/// assuming that a particular column is a row key or duplicating actions.
private struct NativeTableReadingLayout: Layout {
    let columns: Int
    let width: CGFloat
    let gap: CGFloat
    let rowGap: CGFloat

    private func frames(_ views: Subviews) -> [CGRect] {
        var frames = Array(repeating: CGRect.zero, count: views.count)
        var y: CGFloat = 0
        for index in views.indices where index > columns {
            if views[index][NativeTableBoundaryKey.self] {
                y += rowGap
                frames[index] = CGRect(x: 0, y: y, width: width, height: 0.5)
                y += 0.5 + rowGap
            } else {
                let size = views[index].sizeThatFits(.init(width: width, height: nil))
                let height = size.height.isFinite ? max(0, size.height) : 0
                frames[index] = CGRect(x: 0, y: y,
                    width: size.width.isFinite ? max(width, size.width) : width, height: height)
                y += height + gap
            }
        }
        return frames
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(subviews)
        return CGSize(width: frames.map(\.maxX).max() ?? width, height: frames.map(\.maxY).max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, frame) in zip(subviews, frames(subviews)) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading, proposal: .init(frame.size))
        }
    }
}

private struct NativeDataTableLayout: Layout {
    let columns: Int
    let width: CGFloat
    let minimum: CGFloat
    let gap: CGFloat
    var columnMinimums: [CGFloat]? = nil

    private func frames(_ views: Subviews) -> [CGRect] {
        guard columns > 0 else { return [] }
        let cells = views.indices.filter { !views[$0][NativeTableBoundaryKey.self] }
        var ideal = Array(repeating: CGFloat.zero, count: columns)
        for (position, index) in cells.enumerated() {
            let measured = views[index].sizeThatFits(.unspecified).width
            if measured.isFinite { ideal[position % columns] = max(ideal[position % columns], measured) }
        }
        var widths = NativeTableColumnPlacement.widths(ideal: ideal, minimum: minimum, available: width, gap: gap, minimums: columnMinimums)
        // Some children explicitly refuse compression (for example a supplied
        // fixed media size). Widen that column for every row, not just its cell.
        for (position, index) in cells.enumerated() {
            let column = position % columns
            let measured = views[index].sizeThatFits(ProposedViewSize(width: widths[column], height: nil)).width
            if measured.isFinite { widths[column] = max(widths[column], measured) }
        }
        var result = Array(repeating: CGRect.zero, count: views.count)
        var y: CGFloat = 0
        for start in stride(from: 0, to: cells.count, by: columns) {
            let end = min(start + columns, cells.count)
            let sizes = (start..<end).map { views[cells[$0]].sizeThatFits(ProposedViewSize(width: widths[$0 % columns], height: nil)) }
            let height = sizes.map(\.height).filter(\.isFinite).max() ?? 0
            var x: CGFloat = 0
            for position in start..<end {
                let index = cells[position]
                let column = position % columns
                result[index] = CGRect(x: x, y: y, width: widths[column], height: height)
                x += result[index].width + gap
            }
            y += height
            if end > start {
                let divider = cells[end - 1] + 1
                if views.indices.contains(divider), views[divider][NativeTableBoundaryKey.self] {
                    result[divider] = CGRect(x: 0, y: y, width: max(0, x - gap), height: 0.5)
                    y += 0.5
                }
            }
        }
        return result
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let placed = frames(subviews)
        return CGSize(width: placed.map(\.maxX).max() ?? 0, height: placed.map(\.maxY).max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, frame) in zip(subviews, frames(subviews)) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                proposal: ProposedViewSize(frame.size))
        }
    }
}

private struct NativeTableWidthKey: PreferenceKey {
    static let defaultValue: [Namespace.ID: CGFloat] = [:]
    static func reduce(value: inout [Namespace.ID: CGFloat], nextValue: () -> [Namespace.ID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}
