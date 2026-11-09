import SwiftUI
import OpenUILang
import OpenUISwiftUI

enum RowComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Row", description: "Horizontal flex layout. Defaults: gap 2 theme units, align center, justify start, wrap false. Explicit Box.flex/width controls ordinary rows. A two-item image/text row uses the SDK thumbnail profile and top-aligned text; image position follows child order. Do not supply image proportions. Accessibility block rows stack. wrap moves items to further lines.", params: [
            OpenUIParameter.slot("children", required: true), Parameter.number("gap", minimum: 0, maximum: 24),
            OpenUIParameter.string("align", required: false, values: ["start", "center", "end", "stretch"]),
            OpenUIParameter.string("justify", required: false, values: ["start", "center", "end", "between"]),
            OpenUIParameter.flag("wrap")
        ]) { RowView(context: $0) }
    }
}

private struct RowView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.layoutDirection) private var direction
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.intelligentUIEditorial) private var editorial
    private func isBlock(_ child: OpenUIRenderChild) -> Bool {
        guard case .element(let element) = child.value else { return false }
        return ["Box", "Col", "Card", "ImageText", "ProductCard", "TransportCard", "List", "Table", "Chart", "Form"].contains(element.typeName)
    }
    private func weight(_ child: OpenUIRenderChild) -> Double {
        if let explicit = ValueReading.number(ValueReading.field(child.value, "flex")) { return min(1000, max(0, explicit)) }
        if ValueReading.number(ValueReading.field(child.value, "width")) != nil { return 0 }
        return 0
    }
    @ViewBuilder var body: some View {
        let children = context.children()
        if children.count == 2, children.filter({ EditorialNode.media($0.value) }).count == 1, let mediaIndex = children.firstIndex(where: { EditorialNode.media($0.value) }), !typeSize.isAccessibilitySize {
            EditorialRowLayout(preferredImageWidth: EditorialMetrics.imageWidth, ratio: EditorialNode.imageRatio(children[mediaIndex].value) ?? EditorialMetrics.imageAspectRatio, gap: theme.groupSpacing, rightToLeft: (direction == .rightToLeft) != (mediaIndex == 1)) {
                context.render(children[mediaIndex].value).environment(\.intelligentUIEditorial, mediaContext(true))
                context.render(children[1 - mediaIndex].value).environment(\.intelligentUIEditorial, mediaContext(false))
            }
            .environment(\.layoutDirection, direction)
        } else if typeSize.isAccessibilitySize && children.count > 1 && children.allSatisfy({ isBlock($0) || EditorialNode.media($0.value) }) {
            VStack(alignment: .leading, spacing: CGFloat(context.number("gap") ?? 3) * theme.spacingUnit) {
                ForEach(children) { child in
                    context.render(child.value).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else { row }
    }
    private func mediaContext(_ media: Bool) -> EditorialContext {
        var value = editorial; value.mediaRatio = media ? EditorialMetrics.imageAspectRatio : nil
        return value
    }
    private var row: some View {
        WrappingRowLayout(gap: CGFloat(min(24, max(0, context.number("gap") ?? 2))) * theme.spacingUnit,
                          alignment: context.string("align") ?? "center",
                          justification: context.string("justify") ?? "start",
                          wraps: context.flag("wrap") ?? false,
                          rightToLeft: direction == .rightToLeft) {
            let children = context.children()
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                context.render(child.value).layoutValue(key: RowFlexWeight.self, value: CGFloat(weight(child)))
                    .environment(\.intelligentUIEditorial, rowContext(child.value, previous: index > 0 ? children[index - 1].value : nil))
            }
        }
    }
    private func rowContext(_ value: Value, previous: Value?) -> EditorialContext {
        var result = editorial
        result.cardSubtitle = editorial.openingCardTitle && previous.map(EditorialNode.smallTitle) == true && ["Text", "Caption"].contains(EditorialNode.kind(value))
        result.openingCardTitle = editorial.openingCardTitle && EditorialNode.smallTitle(value)
        return result
    }
}

/// Layout geometry is independent of views so wrapping and spacing can be verified.
struct RowGeometry {
    let frames: [CGRect]
    let size: CGSize

    init(sizes: [CGSize], width: CGFloat, gap: CGFloat, alignment: String, justification: String, wraps: Bool) {
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
                let dy = alignment == "end" ? height - sizes[i].height : alignment == "center" ? (height - sizes[i].height) / 2 : 0
                result[i] = CGRect(x: x, y: y + dy, width: sizes[i].width, height: alignment == "stretch" ? height : sizes[i].height)
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

    private func geometry(proposal: ProposedViewSize, subviews: Subviews) -> RowGeometry {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
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
            return subviews[i].sizeThatFits(ProposedViewSize(width: offered, height: nil))
        }
        return RowGeometry(sizes: sizes, width: width, gap: gap, alignment: alignment, justification: justification, wraps: wraps)
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
