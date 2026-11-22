import SwiftUI
import SwiftLang

enum RowComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Row", description: "Horizontal flex layout: gap defaults to 2 theme units, align center, justify start, wrap false. Box flex shares each line's free space. A direct Image/SearchImage sets gap 16 points and align start. A direct photo or a Box containing only one direct photo uses a fixed one-third width clamped to 120–200 points and photo ratio 4:3. Accessibility reading rows may stack natively.", params: [
            OpenUIParameter.slot("children", required: true), Parameter.number("gap"),
            OpenUIParameter.string("align", required: false, values: ["start", "center", "end", "stretch"]),
            OpenUIParameter.string("justify", required: false, values: ["start", "center", "end", "between"]),
            OpenUIParameter.flag("wrap")
        ]) { RowView(context: $0) }
    }
}

private struct RowView: View {
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.layoutDirection) private var direction
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openIntelligentUIItemSizing) private var parentSizing
    @Environment(\.openIntelligentUIViewportSize) private var viewport
    @ScaledMetric(relativeTo: .body) private var fontUnit: CGFloat = 17

    var body: some View {
        let children = context.children()
        let stacked = typeSize.isAccessibilitySize && children.count > 1
            && children.allSatisfy { RowPresentation.isReadingBlock($0.value) }
        let photo = RowMediaRules.hasDirectPhoto(children)
        let gap = photo && !stacked ? 16 : theme.spacing(context.number("gap"), fallback: 2)
        let alignment = photo && !stacked ? "start" : context.string("align") ?? "center"
        let cross: HorizontalAlignment = alignment == "end" ? .trailing : alignment == "center" ? .center : .leading
        let boundedHeight = parentSizing.height != .natural
        let layout: AnyLayout = stacked
            ? AnyLayout(VStackLayout(alignment: cross, spacing: gap))
            : AnyLayout(WrappingRowLayout(gap: gap, alignment: alignment,
                justification: context.string("justify") ?? "start", wraps: context.flag("wrap") ?? false,
                rightToLeft: direction == .rightToLeft, fillsHeight: boundedHeight, viewport: viewport))
        return layout {
            ForEach(children) { child in
                context.render(child.value)
                    .frame(maxWidth: stacked && alignment == "stretch" ? .infinity : nil, alignment: .leading)
                    .environment(\.openIntelligentUIItemSizing, IntelligentUIItemSizing.forChild(child.value,
                        width: !stacked && EditorialNode.kind(child.value) == "Box" ? .allocated : alignment == "stretch" && stacked ? .stretch : .natural,
                        height: !stacked && alignment == "stretch" ? .stretch : .natural, hasDefiniteHeight: boundedHeight))
                    .environment(\.openIntelligentUIRowMediaAspectRatio,
                        !stacked && RowMediaRules.kind(child.value) != .none ? 4.0 / 3.0 : nil)
                    .layoutValue(key: IntelligentUIFlexItemKey.self, value: IntelligentUIFlexItem.read(child.value, theme: theme, fontUnit: fontUnit))
                    .layoutValue(key: RowDivider.self, value: EditorialNode.kind(child.value) == "Divider")
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: cross, vertical: .top))
    }
}

enum RowFlexRules {
    static func weight(_ value: Value) -> CGFloat {
        if let explicit = ValueReading.number(ValueReading.field(value, "flex")) { return CGFloat(max(0, explicit)) }
        return EditorialNode.kind(value) == "Spacer" ? 1 : 0
    }
}

enum RowPresentation {
    static func isReadingBlock(_ value: Value) -> Bool {
        EditorialNode.media(value) || ["Text", "Title", "Caption", "Markdown", "Box", "Col", "Card", "ImageText", "ProductCard", "TransportCard", "List", "Table", "Chart", "Form", "Quote", "Code", "Disclosure"].contains(EditorialNode.kind(value))
    }
}

/// Layout geometry is independent of views so wrapping and spacing can be verified.
struct RowGeometry {
    let frames: [CGRect]
    let size: CGSize

    init(sizes: [CGSize], width: CGFloat, gap: CGFloat, alignment: String, justification: String, wraps: Bool,
         stretchIndices: Set<Int> = [], minimumLineHeight: CGFloat = 0, lineHeight: CGFloat? = nil) {
        guard !sizes.isEmpty else { frames = []; size = .zero; return }
        let sizes = sizes.map { CGSize(width: $0.width.isFinite ? max(0, $0.width) : 0,
                                       height: $0.height.isFinite ? max(0, $0.height) : 0) }
        let width = width.isFinite ? max(0, width) : sizes.reduce(0) { $0 + $1.width }
        let gap = gap.isFinite ? max(0, gap) : 0
        let minimumLineHeight = minimumLineHeight.isFinite ? max(0, minimumLineHeight) : 0
        var rows: [[Int]] = [[]]
        var used: CGFloat = 0
        for i in sizes.indices {
            let next = used + (rows[rows.count - 1].isEmpty ? 0 : gap) + sizes[i].width
            if wraps && next > width && !rows[rows.count - 1].isEmpty {
                rows.append([]); used = 0
            }
            used += (rows[rows.count - 1].isEmpty ? 0 : gap) + sizes[i].width
            rows[rows.count - 1].append(i)
        }
        var result = Array(repeating: CGRect.zero, count: sizes.count)
        var y: CGFloat = 0
        for row in rows {
            let height = lineHeight.flatMap { $0.isFinite ? max(0, $0) : nil }
                ?? max(minimumLineHeight, row.map { sizes[$0].height }.max() ?? 0)
            let contentWidth = row.reduce(CGFloat.zero) { $0 + sizes[$1].width }
            let spare = width - contentWidth - CGFloat(row.count - 1) * gap
            let spacing = justification == "between" && row.count > 1 ? gap + max(0, spare) / CGFloat(row.count - 1) : gap
            var x = justification == "center" ? spare / 2 : justification == "end" ? spare : 0
            for i in row {
                let stretches = alignment == "stretch" || stretchIndices.contains(i)
                let dy = stretches ? 0 : alignment == "end" ? height - sizes[i].height : alignment == "center" ? (height - sizes[i].height) / 2 : 0
                result[i] = CGRect(x: x, y: y + dy, width: sizes[i].width, height: stretches ? height : sizes[i].height)
                x += sizes[i].width + spacing
            }
            y += height + gap
        }
        frames = result
        size = CGSize(width: width, height: max(0, y - gap))
    }
}

struct WrappingRowLayout: Layout {
    var gap: CGFloat
    var alignment: String
    var justification: String
    var wraps: Bool
    var rightToLeft = false
    var fillsWidth = true
    var fillsHeight = false
    var viewport: CGSize?

    static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties(); properties.stackOrientation = .horizontal; return properties
    }

    private func geometry(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect], proposals: [ProposedViewSize]) {
        guard !subviews.isEmpty else { return (.zero, [], []) }
        let items = subviews.map { subview -> IntelligentUIFlexItem in
            if let item = subview[IntelligentUIFlexItemKey.self] { return item }
            let weight = FlexGeometry.length(subview[RowFlexWeight.self])
            return IntelligentUIFlexItem(grow: weight > 0 ? weight : nil)
        }
        let directPhoto = items.contains { $0.media == .direct }
        let gap = directPhoto ? CGFloat(16) : FlexGeometry.length(gap)
        let alignment = directPhoto ? "start" : alignment
        let intrinsic = subviews.map { $0.sizeThatFits(.unspecified) }
        let naturalWidths = items.indices.map { index in
            let authored = items[index].grow == nil ? items[index].width?.resolve(relativeTo: nil, em: items[index].fontUnit, viewport: viewport) : nil
            return max(items[index].insets, authored ?? FlexGeometry.length(intrinsic[index].width))
        }
        let natural = FlexGeometry.sum(naturalWidths + Array(repeating: gap, count: max(0, items.count - 1)))
        let definiteWidth = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
        let width = fillsWidth ? definiteWidth ?? natural : min(definiteWidth ?? natural, natural)
        let parentHeight = fillsHeight ? proposal.height.flatMap { $0.isFinite ? max(0, $0) : nil } : nil
        let bases = items.indices.map { index -> FlexBasis in
            let item = items[index]
            if item.media != .none {
                let mediaWidth = max(item.insets, RowMediaRules.width(in: width))
                return FlexBasis(basis: mediaWidth, minimum: mediaWidth, shrink: 0)
            }
            let authored = item.grow == nil ? item.width?.resolve(relativeTo: definiteWidth == nil ? nil : width, em: item.fontUnit, viewport: viewport) : nil
            let basis = definiteWidth != nil && item.grow != nil ? item.insets : max(item.insets, authored ?? naturalWidths[index])
            return FlexBasis(basis: basis, minimum: item.insets, grow: item.grow ?? 0,
                shrink: item.grow == nil && item.numericWidth ? 0 : 1, insets: item.insets)
        }
        // Line breaks use hypothetical bases. flex: n 1 0% retains its zero
        // basis during wrapping; each resulting line then resolves free space.
        var lines: [[Int]] = [[]]
        var used: CGFloat = 0
        for index in bases.indices {
            let basis = max(bases[index].basis, bases[index].minimum)
            let next = used + (lines[lines.count - 1].isEmpty ? 0 : gap) + basis
            if wraps && next > width && !lines[lines.count - 1].isEmpty { lines.append([]); used = 0 }
            used += (lines[lines.count - 1].isEmpty ? 0 : gap) + basis
            lines[lines.count - 1].append(index)
        }
        var frames = Array(repeating: CGRect.zero, count: subviews.count)
        var proposals = Array(repeating: ProposedViewSize.unspecified, count: subviews.count)
        var measuredLines: [[CGSize]] = []
        for line in lines {
            let available = max(0, width - CGFloat(max(0, line.count - 1)) * gap)
            let allocations = FlexDistribution.lengths(line.map { bases[$0] }, available: available)
            measuredLines.append(line.enumerated().map { offset, index -> CGSize in
                let item = items[index]
                let authoredHeight = item.height?.resolve(relativeTo: parentHeight, em: item.fontUnit, viewport: viewport)
                // Measure an auto cross-size naturally. A percentage height
                // retains the definite container height as its reference.
                let proposed = ProposedViewSize(width: allocations[offset], height: item.isBox && authoredHeight != nil ? parentHeight : nil)
                proposals[index] = proposed
                let measured = subviews[index].sizeThatFits(proposed)
                return CGSize(width: allocations[offset], height: subviews[index][RowDivider.self] ? 0 : FlexGeometry.length(measured.height))
            })
        }
        let naturalHeights = measuredLines.map { $0.map(\.height).max() ?? 0 }
        let naturalHeight = FlexGeometry.sum(naturalHeights) + CGFloat(max(0, lines.count - 1)) * gap
        let extra = parentHeight.map { max(0, $0 - naturalHeight) / CGFloat(lines.count) } ?? 0
        var y: CGFloat = 0
        for (lineIndex, line) in lines.enumerated() {
            let dividers = Set(line.indices.filter { subviews[line[$0]][RowDivider.self] })
            let geometry = RowGeometry(sizes: measuredLines[lineIndex], width: width, gap: gap, alignment: alignment,
                justification: justification, wraps: false, stretchIndices: dividers,
                lineHeight: !wraps ? parentHeight ?? naturalHeights[lineIndex] : naturalHeights[lineIndex] + extra)
            for (offset, index) in line.enumerated() {
                let frame = geometry.frames[offset]
                frames[index] = frame.offsetBy(dx: 0, dy: y)
                if alignment == "stretch" || subviews[index][RowDivider.self] {
                    let item = items[index]
                    if !item.isBox || item.height?.resolve(relativeTo: parentHeight, em: item.fontUnit, viewport: viewport) == nil {
                        proposals[index].height = frame.height
                    }
                }
            }
            y += geometry.size.height + gap
        }
        return (CGSize(width: width, height: parentHeight ?? max(0, y - gap)), frames, proposals)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        geometry(proposal: proposal, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = geometry(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for index in subviews.indices {
            let frame = result.frames[index]
            let x = rightToLeft ? bounds.maxX - frame.maxX : bounds.minX + frame.minX
            subviews[index].place(at: CGPoint(x: x, y: bounds.minY + frame.minY), anchor: .topLeading, proposal: result.proposals[index])
        }
    }
}
