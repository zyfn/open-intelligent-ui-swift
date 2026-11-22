import SwiftUI
import SwiftLang

/// Native counterpart of the upstream Length value. Points and px are logical
/// platform points; percentages follow the containing layout proposal rather
/// than the physical screen. em/rem scale with the host's Dynamic Type setting.
enum IntelligentUILength: Equatable {
    case points(CGFloat)
    case percent(CGFloat)
    case em(CGFloat)
    case viewportWidth(CGFloat)
    case viewportHeight(CGFloat)

    static func read(_ value: Value?) -> Self? {
        if let number = ValueReading.number(value) { return .points(CGFloat(max(0, number))) }
        guard case .string(let raw) = value else { return nil }
        let text = raw.displayString.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "auto" { return nil }
        // Pinned shared/props.ts accepts this grammar, not arbitrary CSS.
        guard text.range(of: #"^[0-9]+(\.[0-9]+)?(px|%|em|rem|vh|vw|fr)?$"#, options: .regularExpression) != nil else { return nil }
        let suffix = ["rem", "em", "px", "%", "vw", "vh", "fr"].first { text.hasSuffix($0) } ?? ""
        guard let number = Double(suffix.isEmpty ? text : String(text.dropLast(suffix.count))), number.isFinite else { return nil }
        let length = CGFloat(number)
        switch suffix {
        case "em", "rem": return .em(length)
        case "%": return .percent(length / 100)
        case "vw": return .viewportWidth(length / 100)
        case "vh": return .viewportHeight(length / 100)
        // fr passes the upstream sanitizer but has no used width/height value
        // in CSS. Preserve its auto fallback rather than inventing fractions.
        case "fr": return nil
        default: return .points(length)
        }
    }

    func resolve(relativeTo offered: CGFloat?, em: CGFloat, viewport: CGSize? = nil) -> CGFloat? {
        func product(_ value: CGFloat, _ reference: CGFloat?) -> CGFloat? {
            guard value.isFinite, value >= 0, let reference, reference.isFinite else { return nil }
            let result = max(0, reference) * value
            return result.isFinite ? result : nil
        }
        switch self {
        case .points(let value):
            guard value.isFinite, value >= 0 else { return nil }
            return value
        case .em(let value):
            return product(value, em)
        case .percent(let value): return product(value, offered)
        case .viewportWidth(let value): return product(value, viewport?.width)
        case .viewportHeight(let value): return product(value, viewport?.height)
        }
    }

    func isDefinite(parent: Bool, viewport: CGSize?) -> Bool {
        switch self {
        case .percent: return parent
        case .viewportWidth: return viewport?.width.isFinite == true
        case .viewportHeight: return viewport?.height.isFinite == true
        case .points, .em: return true
        }
    }
}

struct IntelligentUILengthFrame: Layout {
    let width: IntelligentUILength?
    let height: IntelligentUILength?
    let fontUnit: CGFloat
    var itemSizing = IntelligentUIItemSizing()
    var minimumSize: CGFloat = 0
    var viewport: CGSize?
    var alignment: Alignment = .topLeading
    var rightToLeft = false

    private func sizing(for proposal: ProposedViewSize, subviews: Subviews) -> (width: CGFloat?, height: CGFloat?, content: ProposedViewSize) {
        let proposedWidth = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
        let proposedHeight = proposal.height.flatMap { $0.isFinite ? max(0, $0) : nil }
        let authoredWidth = width?.resolve(relativeTo: proposedWidth, em: fontUnit, viewport: viewport)
        let authoredHeight = height?.resolve(relativeTo: itemSizing.hasDefiniteHeight ? proposedHeight : nil, em: fontUnit, viewport: viewport)
        let w = (itemSizing.width == .allocated ? proposedWidth : authoredWidth ?? (itemSizing.width == .stretch ? proposedWidth : nil)).map { max(minimumSize, $0) }
        let h = (itemSizing.height == .allocated ? proposedHeight : authoredHeight ?? (itemSizing.height == .stretch ? proposedHeight : nil)).map { max(minimumSize, $0) }
        let contentHeight = h ?? (itemSizing.hasDefiniteHeight ? proposedHeight : nil)
        var contentWidth = w ?? proposedWidth
        if w == nil, itemSizing.width == .natural, let proposedWidth {
            let ideal = subviews.first?.sizeThatFits(ProposedViewSize(width: nil, height: contentHeight)).width ?? 0
            contentWidth = min(proposedWidth, FlexGeometry.length(ideal))
        }
        return (w, h, ProposedViewSize(width: contentWidth, height: contentHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizing = sizing(for: proposal, subviews: subviews)
        let content = subviews.first?.sizeThatFits(sizing.content) ?? .zero
        return CGSize(width: sizing.width ?? (content.width.isFinite ? max(0, content.width) : 0),
                      height: sizing.height ?? (content.height.isFinite ? max(0, content.height) : 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        // Resolve lengths against the same parent proposal used to measure.
        // The resulting bounds are not another percentage reference size.
        let sizing = sizing(for: proposal, subviews: subviews)
        let measured = child.sizeThatFits(sizing.content)
        let width = measured.width.isFinite ? max(0, measured.width) : 0
        let height = measured.height.isFinite ? max(0, measured.height) : 0
        let horizontal: CGFloat = alignment.horizontal == .trailing ? 1 : alignment.horizontal == .center ? 0.5 : 0
        let vertical: CGFloat = alignment.vertical == .bottom ? 1 : alignment.vertical == .center ? 0.5 : 0
        child.place(at: CGPoint(x: bounds.minX + (bounds.width - width) * (rightToLeft ? 1 - horizontal : horizontal),
                                y: bounds.minY + (bounds.height - height) * vertical),
                    anchor: .topLeading, proposal: sizing.content)
    }
}

struct IntelligentUILengthModifier: ViewModifier {
    let width: IntelligentUILength?
    let height: IntelligentUILength?
    let fontUnit: CGFloat
    var itemSizing = IntelligentUIItemSizing()
    var minimumSize: CGFloat = 0
    var alignment: Alignment = .topLeading
    var rightToLeft = false
    @Environment(\.openIntelligentUIViewportSize) private var viewport

    func body(content: Content) -> some View {
        IntelligentUILengthFrame(width: width, height: height, fontUnit: fontUnit,
            itemSizing: itemSizing, minimumSize: minimumSize, viewport: viewport,
            alignment: alignment, rightToLeft: rightToLeft) { content }
    }
}
