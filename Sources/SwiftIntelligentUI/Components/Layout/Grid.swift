import SwiftUI
import SwiftLang

enum GridComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Grid", description: "Equal columns, default 2 and maximum 12. minChildWidth is in points and reduces columns on narrow widths, never exceeding columns. gap defaults to 3 theme units. Accessibility text sizes use one column.", params: [
            OpenUIParameter.slot("children", required: true), Parameter.number("columns"),
            Parameter.number("minChildWidth"), Parameter.number("gap")
        ]) { GridView(context: $0) }
    }
}

private struct GridView: View {
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openIntelligentUIEditorial) private var editorial
    var body: some View {
        EqualGridLayout(columns: typeSize.isAccessibilitySize ? 1 : Int(min(12, max(1, (context.number("columns") ?? 2).rounded()))),
                        minimumWidth: context.number("minChildWidth").map { CGFloat(max(0, $0)) },
                        gap: theme.spacing(context.number("gap"), fallback: 3)) {
            ForEach(context.children()) { child in
                context.render(child.value).frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.openIntelligentUIEditorial, childContext)
                    .environment(\.openIntelligentUIItemSizing, IntelligentUIItemSizing())
                    .environment(\.openIntelligentUIRowMediaAspectRatio, nil)
            }
        }
        .environment(\.openIntelligentUIImageAlbum, ImageAlbumItem.collect(context.children().map(\.value)))
    }
    private var childContext: EditorialContext {
        var result = editorial
        result.mediaRatio = nil
        return result
    }
}

struct EqualGridLayout: Layout {
    let columns: Int
    let minimumWidth: CGFloat?
    let gap: CGFloat

    func columnCount(width: CGFloat) -> Int {
        let columns = min(12, max(1, columns))
        guard let minimumWidth, minimumWidth.isFinite, minimumWidth > 0,
              width.isFinite else { return columns }
        let gap = gap.isFinite ? max(0, gap) : 0
        let fitting = floor((max(0, width) + gap) / (minimumWidth + gap))
        guard fitting.isFinite else { return columns }
        return Int(min(CGFloat(columns), max(1, fitting)))
    }
    private func geometry(proposal: ProposedViewSize, subviews: Subviews) -> (CGSize, [CGRect]) {
        guard !subviews.isEmpty else { return (.zero, []) }
        let columns = min(12, max(1, columns))
        let gap = gap.isFinite ? max(0, gap) : 0
        let ideal = subviews.map { subview in
            let width = subview.sizeThatFits(.unspecified).width
            return width.isFinite ? max(0, width) : 0
        }.max() ?? 0
        let natural = ideal * CGFloat(columns) + gap * CGFloat(columns - 1)
        let width = max(0, proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? (natural.isFinite ? natural : 0))
        let count = columnCount(width: width)
        let cellWidth = max(0, (width - CGFloat(count - 1) * gap) / CGFloat(count))
        var frames: [CGRect] = []
        var y: CGFloat = 0
        for start in stride(from: 0, to: subviews.count, by: count) {
            let end = min(start + count, subviews.count)
            let height = (start..<end).map { index in
                let height = subviews[index].sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height
                return height.isFinite ? max(0, height) : 0
            }.max() ?? 0
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
            subviews[i].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                              anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}
