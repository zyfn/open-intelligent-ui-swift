import SwiftUI
import SwiftLang

enum RowComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Row", description: "Horizontal flex layout. Defaults: gap 2 theme units, align center, justify start, wrap false. Explicit Box.flex/width controls ordinary rows. A two-item image/prose row with default placement uses the SDK thumbnail profile; explicit gap is honored and explicit align/justify/wrap use ordinary row placement. Narrow or accessibility reading rows may stack without replacing their children. wrap moves items to further lines.", params: [
            OpenUIParameter.slot("children", required: true), Parameter.number("gap", minimum: 0, maximum: 24),
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
    @Environment(\.openIntelligentUIEditorial) private var editorial
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        let children = context.children()
        let mediaIndex = RowPresentation.mediaIndex(children.map(\.value), hasExplicitPlacement: context.string("align") != nil || context.string("justify") != nil || context.flag("wrap") != nil)
        let stacked = (typeSize.isAccessibilitySize && children.count > 1 && children.allSatisfy { RowPresentation.isReadingBlock($0.value) })
            || (mediaIndex != nil && availableWidth > 0 && availableWidth < EditorialMetrics.minimumRowWidth)
        let gap = context.number("gap").map { CGFloat(min(24, max(0, $0))) * theme.spacingUnit }
            ?? (mediaIndex == nil ? theme.spacingUnit * 2 : theme.groupSpacing)
        let stackedAlignment: HorizontalAlignment = context.string("align") == "end" ? .trailing : context.string("align") == "center" ? .center : .leading
        let layout: AnyLayout = stacked
            ? AnyLayout(VStackLayout(alignment: stackedAlignment, spacing: gap))
            : mediaIndex.map { AnyLayout(EditorialRowLayout(preferredImageWidth: EditorialMetrics.imageWidth,
                ratio: EditorialNode.imageRatio(children[$0].value) ?? EditorialMetrics.imageAspectRatio,
                gap: gap, rightToLeft: direction == .rightToLeft, mediaIndex: $0)) }
                ?? AnyLayout(WrappingRowLayout(gap: gap, alignment: context.string("align") ?? "center",
                    justification: context.string("justify") ?? "start", wraps: context.flag("wrap") ?? false,
                    rightToLeft: direction == .rightToLeft))
        // Keep the same ForEach and IDs while only the layout changes.
        return layout {
            ForEach(children) { child in
                context.render(child.value)
                    .environment(\.openIntelligentUIEditorial, childContext(child.value, media: mediaIndex != nil, stacked: stacked))
                    .frame(maxWidth: stacked && context.string("align") == "stretch" ? .infinity : nil, alignment: .leading)
                    .layoutValue(key: RowFlexWeight.self, value: RowFlexRules.weight(child.value))
                    .layoutValue(key: RowDivider.self, value: EditorialNode.kind(child.value) == "Divider")
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: stackedAlignment, vertical: .top))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            if width.isFinite, width > 0, abs(width - availableWidth) > 0.5 { availableWidth = width }
        }
    }

    private func childContext(_ value: Value, media: Bool, stacked: Bool) -> EditorialContext {
        var result = editorial
        if media && EditorialNode.media(value) { result.mediaRatio = stacked ? theme.coverImageAspectRatio : EditorialMetrics.imageAspectRatio }
        return result
    }
}

enum RowFlexRules {
    static func weight(_ value: Value) -> CGFloat {
        if let explicit = ValueReading.number(ValueReading.field(value, "flex")) { return CGFloat(min(1000, max(0, explicit))) }
        return EditorialNode.kind(value) == "Spacer" ? 1 : 0
    }
}

enum RowPresentation {
    static func isReadingBlock(_ value: Value) -> Bool {
        EditorialNode.media(value) || ["Text", "Title", "Caption", "Markdown", "Box", "Col", "Card", "ImageText", "ProductCard", "TransportCard", "List", "Table", "Chart", "Form", "Quote", "Code", "Disclosure"].contains(EditorialNode.kind(value))
    }
    static func mediaIndex(_ children: [Value], hasExplicitPlacement: Bool) -> Int? {
        guard !hasExplicitPlacement, children.count == 2,
              children.filter({ EditorialNode.media($0) }).count == 1,
              let index = children.firstIndex(where: EditorialNode.media),
              EditorialNode.isProse(children[1 - index]),
              children.allSatisfy({ ValueReading.field($0, "width") == nil && ValueReading.field($0, "flex") == nil }) else { return nil }
        return index
    }
}

/// Layout geometry is independent of views so wrapping and spacing can be verified.
struct RowGeometry {
    let frames: [CGRect]
    let size: CGSize

    init(sizes: [CGSize], width: CGFloat, gap: CGFloat, alignment: String, justification: String, wraps: Bool, stretchIndices: Set<Int> = []) {
        guard !sizes.isEmpty else { frames = []; size = .zero; return }
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
            let height = row.map { sizes[$0].height }.max() ?? 0
            let contentWidth = row.reduce(CGFloat.zero) { $0 + sizes[$1].width }
            let spare = max(0, width - contentWidth - CGFloat(row.count - 1) * gap)
            let spacing = justification == "between" && row.count > 1 ? gap + spare / CGFloat(row.count - 1) : gap
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

    static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties(); properties.stackOrientation = .horizontal; return properties
    }

    private func geometry(proposal: ProposedViewSize, subviews: Subviews) -> RowGeometry {
        let dividers = Set(subviews.indices.filter { subviews[$0][RowDivider.self] })
        let ideal = subviews.indices.map { index -> CGSize in
            let size = subviews[index].sizeThatFits(.unspecified)
            return dividers.contains(index) ? CGSize(width: size.width.isFinite ? size.width : 1, height: 0) : size
        }
        let natural = ideal.reduce(CGFloat.zero) { $0 + $1.width } + CGFloat(max(0, ideal.count - 1)) * gap
        let proposed = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? natural
        let width = max(0, fillsWidth ? proposed : min(proposed, natural))
        let available = max(0, width - CGFloat(max(0, ideal.count - 1)) * gap)
        let total = ideal.reduce(CGFloat.zero) { $0 + $1.width }
        let weights = subviews.map { max(0, $0[RowFlexWeight.self]) }
        let weight = weights.reduce(0, +)
        let fixed = ideal.indices.filter { weights[$0] == 0 }.reduce(CGFloat.zero) { $0 + ideal[$1].width }
        let sizes = subviews.indices.map { i in
            let offered = !wraps && weight > 0
                ? (weights[i] > 0 ? max(0, available - fixed) * weights[i] / weight : ideal[i].width)
                : wraps ? min(width, ideal[i].width) : total > available && total > 0 ? available * ideal[i].width / total : ideal[i].width
            return dividers.contains(i) ? CGSize(width: offered, height: 0) : subviews[i].sizeThatFits(ProposedViewSize(width: offered, height: nil))
        }
        return RowGeometry(sizes: sizes, width: width, gap: gap, alignment: alignment, justification: justification, wraps: wraps, stretchIndices: dividers)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        geometry(proposal: proposal, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let geometry = geometry(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for i in subviews.indices {
            let frame = geometry.frames[i]
            let x = rightToLeft ? bounds.maxX - frame.maxX : bounds.minX + frame.minX
            subviews[i].place(at: CGPoint(x: x, y: bounds.minY + frame.minY), anchor: .topLeading,
                              proposal: ProposedViewSize(frame.size))
        }
    }
}
