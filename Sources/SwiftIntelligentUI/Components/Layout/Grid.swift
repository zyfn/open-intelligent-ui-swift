import SwiftUI
import SwiftLang

enum GridComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Grid", description: "Equal columns, default 2 and maximum 12. minChildWidth is in points and reduces columns on narrow widths, never exceeding columns. gap defaults to 3 theme units. Accessibility text sizes use one column.", params: [
            OpenUIParameter.slot("children", required: true), Parameter.number("columns", minimum: 1, maximum: 12),
            Parameter.number("minChildWidth", minimum: 0), Parameter.number("gap", minimum: 0, maximum: 24)
        ]) { GridView(context: $0) }
    }
}

private struct GridView: View {
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var direction
    @Environment(\.openIntelligentUIEditorial) private var editorial
    var body: some View {
        EqualGridLayout(columns: typeSize.isAccessibilitySize ? 1 : Int(min(12, max(1, (context.number("columns") ?? 2).rounded()))),
                        minimumWidth: context.number("minChildWidth").map { CGFloat(max(0, $0)) },
                        gap: CGFloat(min(24, max(0, context.number("gap") ?? 3))) * theme.spacingUnit,
                        rightToLeft: direction == .rightToLeft) {
            ForEach(context.children()) { child in
                context.render(child.value).frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.openIntelligentUIEditorial, childContext)
            }
        }
        .environment(\.openIntelligentUIImageAlbum, ImageAlbumItem.collect(context.children().map(\.value)))
    }
    private var childContext: EditorialContext {
        var result = editorial
        result.mediaRatio = 1
        return result
    }
}

struct EqualGridLayout: Layout {
    let columns: Int
    let minimumWidth: CGFloat?
    let gap: CGFloat
    var rightToLeft = false

    func columnCount(width: CGFloat) -> Int {
        guard let minimumWidth, minimumWidth > 0 else { return columns }
        return Int(min(CGFloat(columns), max(1, floor((max(0, width) + gap) / (minimumWidth + gap)))))
    }
    private func geometry(proposal: ProposedViewSize, subviews: Subviews) -> (CGSize, [CGRect]) {
        guard !subviews.isEmpty else { return (.zero, []) }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let width = max(0, proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? (ideal * CGFloat(columns) + gap * CGFloat(columns - 1)))
        let count = columnCount(width: width)
        let cellWidth = max(0, (width - CGFloat(count - 1) * gap) / CGFloat(count))
        var frames: [CGRect] = []
        var y: CGFloat = 0
        for start in stride(from: 0, to: subviews.count, by: count) {
            let end = min(start + count, subviews.count)
            let height = (start..<end).map { subviews[$0].sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height }.max() ?? 0
            for index in start..<end {
                frames.append(CGRect(x: CGFloat(index - start) * (cellWidth + gap), y: y, width: cellWidth, height: height))
            }
            y += height + gap
        }
        return (CGSize(width: width, height: max(0, y - gap)), frames)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        geometry(proposal: proposal, subviews: subviews).0
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = geometry(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews).1
        for i in subviews.indices {
            let frame = frames[i]
            let x = rightToLeft ? bounds.maxX - frame.maxX : bounds.minX + frame.minX
            subviews[i].place(at: CGPoint(x: x, y: bounds.minY + frame.minY), anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}
