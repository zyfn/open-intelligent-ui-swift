import SwiftUI
import OpenUILang
import OpenUISwiftUI

private enum TableMetrics {
    static let minimumColumnWidth: CGFloat = 80
    static let maximumColumnWidth: CGFloat = 180
    static let cellHorizontalPadding: CGFloat = 12
    static let cellVerticalPadding: CGFloat = 10
}

enum TableComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Table", description: "Native table with SDK default column sizing: descriptions take flexible remaining width, numeric/money columns stay content-sized and right aligned. Few readable columns fill the viewport; wide tables scroll. Header surface/semibold labels, consistent cell padding, vertically centered multiline rows and subtle separators preserve row relationships. Numeric digits are monospaced. Accessibility sizes use labeled vertical records. Missing cells show an em dash. No manual per-table sizing or Markdown conversion is needed.", params: [
            Parameter.array("columns", items: .object([.init(key: "type", value: .string("string"))])),
            Parameter.array("rows", items: .object([.init(key: "type", value: .string("array")), .init(key: "items", value: .object([]))]))
        ]) { TableView(context: $0) }
    }
}

struct TableData {
    struct Column: Identifiable { let id: String; let title: String; let position: Int; let numeric: Bool }
    struct Row: Identifiable { let id: UUID; let cells: [Value] }
    let columns: [Column]
    let rows: [Row]
    init(columns: Value?, rows: Value?, identity: (Int) -> UUID = { _ in UUID() }) {
        let decodedRows: [Row] = ValueReading.array(rows).enumerated().compactMap { position, value in
            guard case .array(let row) = value else { return nil }
            return Row(id: identity(position), cells: row.values)
        }
        self.rows = decodedRows
        var counts: [String: Int] = [:]
        self.columns = ValueReading.array(columns).enumerated().map { index, value in
            let title = ValueReading.string(value)
            counts[title, default: 0] += 1
            let populated = decodedRows.compactMap { $0.cells.indices.contains(index) ? $0.cells[index] : nil }.filter { !ValueReading.string($0).isEmpty && ValueReading.string($0) != "—" }
            return Column(id: title + "#" + String(counts[title]!), title: title, position: index, numeric: !populated.isEmpty && populated.allSatisfy(Self.isNumeric))
        }
    }
    static func isNumeric(_ value: Value) -> Bool {
        if ValueReading.number(value) != nil { return true }
        if case .string = value, PricePresentation.valid(value) { return true }
        let text = ValueReading.string(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.range(of: #"^[-+−]?[$€£¥₹]?\s?\d[\d,]*(\.\d+)?\s?(%|[kKmMbB]|bn)?$"#, options: .regularExpression) != nil
    }
}

/// The table contract orders rows positionally. Preserve the identity of those
/// slots across runtime reevaluation, rather than the identity of new arrays.
final class TableRowIdentities {
    private var identifiers: [Int: UUID] = [:]
    func id(at position: Int) -> UUID {
        if let id = identifiers[position] { return id }
        let id = UUID(); identifiers[position] = id; return id
    }
}

enum TableColumnWidths {
    static func resolve(ideal: [CGFloat], numeric: [Bool], viewport: CGFloat, minimum: CGFloat, maximum: CGFloat) -> [CGFloat] {
        guard !ideal.isEmpty else { return [] }
        let intrinsic = ideal.map { $0.isFinite ? max(0, $0) : maximum }
        let preferred = intrinsic.indices.map { index in
            numeric.indices.contains(index) && numeric[index] ? max(48, intrinsic[index]) : max(minimum, min(maximum, intrinsic[index]))
        }
        var widths = preferred
        if ideal.count <= 3 {
            widths = intrinsic.indices.map { index in
                numeric.indices.contains(index) && numeric[index]
                    ? preferred[index]
                    : min(preferred[index], max(minimum, min(intrinsic[index], minimum * 1.6)))
            }
        }
        let total = widths.reduce(0, +)
        guard viewport.isFinite, viewport > total else { return widths }
        var flexible = intrinsic.indices.filter { !(numeric.indices.contains($0) && numeric[$0]) }
        if flexible.isEmpty { flexible = Array(intrinsic.indices) }
        let weights = flexible.map { max(minimum, intrinsic[$0]) }
        let sum = weights.reduce(0, +)
        for (position, index) in flexible.enumerated() { widths[index] += (viewport - total) * weights[position] / max(1, sum) }
        return widths
    }
}

private struct NativeTableLayout: Layout {
    let numeric: [Bool]
    let viewport: CGFloat
    let minimum: CGFloat
    let maximum: CGFloat
    private struct Metrics { let widths: [CGFloat]; let heights: [CGFloat]; let lines: [CGFloat]; let size: CGSize }
    private func metrics(_ subviews: Subviews) -> Metrics {
        let count = numeric.count
        guard count > 0 else { return Metrics(widths: [], heights: [], lines: [], size: .zero) }
        let rows = subviews.count / (count + 1)
        let ideal = (0..<count).map { column in
            (0..<rows).map { subviews[$0 * (count + 1) + column].sizeThatFits(.unspecified).width }.max() ?? minimum
        }
        let widths = TableColumnWidths.resolve(ideal: ideal, numeric: numeric, viewport: viewport, minimum: minimum, maximum: maximum)
        let width = widths.reduce(0, +)
        var heights: [CGFloat] = [], lines: [CGFloat] = []
        for row in 0..<rows {
            heights.append((0..<count).map { column in
                subviews[row * (count + 1) + column].sizeThatFits(.init(width: widths[column], height: nil)).height
            }.max() ?? 0)
            lines.append(subviews[row * (count + 1) + count].sizeThatFits(.init(width: width, height: nil)).height)
        }
        return Metrics(widths: widths, heights: heights, lines: lines, size: CGSize(width: width, height: heights.reduce(0, +) + lines.reduce(0, +)))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { metrics(subviews).size }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = metrics(subviews), count = numeric.count
        var y = bounds.minY
        for row in result.heights.indices {
            var x = bounds.minX
            for column in 0..<count {
                subviews[row * (count + 1) + column].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                    proposal: .init(width: result.widths[column], height: result.heights[row]))
                x += result.widths[column]
            }
            y += result.heights[row]
            subviews[row * (count + 1) + count].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                proposal: .init(width: result.size.width, height: result.lines[row]))
            y += result.lines[row]
        }
    }
}

private struct TableView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var scale
    @State private var identities = TableRowIdentities()
    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    var body: some View {
        let data = TableData(columns: context.value("columns"), rows: context.value("rows"), identity: identities.id)
        if data.columns.isEmpty || data.rows.isEmpty {
            Text("暂无表格数据").foregroundStyle(theme.secondaryText)
        } else if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: theme.groupSpacing) {
                ForEach(data.rows) { row in
                    VStack(alignment: .leading, spacing: theme.innerSpacing) {
                        ForEach(data.columns) { column in
                            VStack(alignment: .leading, spacing: theme.spacingUnit) {
                                Text(column.title).font(theme.captionFont).foregroundStyle(theme.secondaryText)
                                cell(row, column)
                            }
                        }
                    }.padding(.vertical, TableMetrics.cellVerticalPadding)
                    separator
                }
            }
        } else {
            VStack(alignment: .leading, spacing: theme.innerSpacing) {
                ScrollView(.horizontal) {
                    NativeTableLayout(numeric: data.columns.map(\.numeric), viewport: viewportWidth,
                                      minimum: TableMetrics.minimumColumnWidth, maximum: TableMetrics.maximumColumnWidth) {
                        ForEach(data.columns) { column in
                            Text(column.title).font(theme.secondaryFont.weight(.semibold)).foregroundStyle(theme.primaryText)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: column.numeric ? .topTrailing : .topLeading)
                                .padding(.horizontal, TableMetrics.cellHorizontalPadding).padding(.vertical, TableMetrics.cellVerticalPadding)
                                .background(theme.surface)
                        }
                        separator
                        ForEach(data.rows) { row in
                            ForEach(data.columns) { column in
                                VStack(alignment: column.numeric ? .trailing : .leading, spacing: 0) { cell(row, column) }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: column.numeric ? .trailing : .leading)
                                    .padding(.horizontal, TableMetrics.cellHorizontalPadding).padding(.vertical, TableMetrics.cellVerticalPadding)
                            }
                            separator
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
                }
                .scrollIndicators(.visible, axes: .horizontal)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.fieldBorder))
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
                if viewportWidth > 0 && contentWidth > viewportWidth + 1 {
                    Label("左右滑动查看其余列", systemImage: "arrow.left.and.right")
                        .font(theme.captionFont).foregroundStyle(theme.secondaryText)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var separator: some View { Rectangle().fill(theme.separator.opacity(0.35)).frame(height: 1 / max(1, scale)) }
    @ViewBuilder private func cell(_ row: TableData.Row, _ column: TableData.Column) -> some View {
        if row.cells.indices.contains(column.position) {
            let value = row.cells[column.position]
            if case .element = value { context.render(value) }
            else {
                Text(InlineTypography.attributed(ValueReading.string(value).isEmpty ? "—" : ValueReading.string(value), font: theme.secondaryFont.monospacedDigit(), emphasis: theme.emphasisWeight))
                    .font(theme.secondaryFont).monospacedDigit().fixedSize(horizontal: column.numeric, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        guard context.canInteract, SourceURL.isActionable(url.absoluteString) else { return .discarded }
                        Task { await context.perform(OpenUIActions.openURL(url.absoluteString)) }; return .handled
                    })
            }
        } else { Text("—").foregroundStyle(theme.secondaryText) }
    }
}
