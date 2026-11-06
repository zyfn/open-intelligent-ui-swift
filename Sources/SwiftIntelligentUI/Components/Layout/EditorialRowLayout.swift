import SwiftUI

enum EditorialRowMetrics {
    static func columns(width: CGFloat, preferred: CGFloat, gap: CGFloat) -> (image: CGFloat, text: CGFloat) {
        let width = max(1, width), gap = max(0, gap)
        let image = min(max(1, preferred), width * 0.34)
        return (image, max(1, width - image - gap))
    }
}
struct EditorialRowLayout: Layout {
    let preferredImageWidth: CGFloat
    let ratio: CGFloat
    let gap: CGFloat
    let rightToLeft: Bool
    var idealWidth: CGFloat = 280
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? idealWidth
        let columns = EditorialRowMetrics.columns(width: width, preferred: preferredImageWidth, gap: gap)
        let text = subviews.count > 1 ? subviews[1].sizeThatFits(.init(width: columns.text, height: nil)).height : 0
        return CGSize(width: width, height: max(columns.image / max(0.2, ratio), text))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let columns = EditorialRowMetrics.columns(width: bounds.width, preferred: preferredImageWidth, gap: gap)
        subviews[0].place(at: CGPoint(x: rightToLeft ? bounds.maxX - columns.image : bounds.minX, y: bounds.minY), proposal: .init(width: columns.image, height: columns.image / max(0.2, ratio)))
        subviews[1].place(at: CGPoint(x: rightToLeft ? bounds.minX : bounds.minX + columns.image + gap, y: bounds.minY), proposal: .init(width: columns.text, height: bounds.height))
    }
}
