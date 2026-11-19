import SwiftUI
import SwiftLang

/// Native counterpart of the upstream Length value. Points and px are logical
/// platform points; percentages follow the containing layout proposal rather
/// than the physical screen. em/rem scale with the host's Dynamic Type setting.
enum IntelligentUILength: Equatable {
    case points(CGFloat)
    case percent(CGFloat)
    case em(CGFloat)

    static func read(_ value: Value?) -> Self? {
        if let number = ValueReading.number(value), number >= 0 { return .points(CGFloat(min(10_000, number))) }
        guard case .string(let raw) = value else { return nil }
        let text = raw.displayString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text == "auto" { return nil }
        for (suffix, kind) in [("rem", "em"), ("em", "em"), ("px", "pt"),
                                ("pt", "pt"), ("%", "percent")] {
            guard text.hasSuffix(suffix),
                  let number = Double(text.dropLast(suffix.count)),
                  number.isFinite, number >= 0 else { continue }
            let capped = CGFloat(min(10_000, number))
            switch kind {
            case "em": return .em(capped)
            case "percent": return .percent(capped / 100)
            default: return .points(capped)
            }
        }
        // vw/vh/fr and arbitrary CSS expressions do not have a faithful
        // parent-independent equivalent in a SwiftUI message cell.
        return nil
    }

    func resolve(relativeTo offered: CGFloat?, em: CGFloat) -> CGFloat? {
        switch self {
        case .points(let value): return value
        case .em(let value): return min(10_000, value * em)
        case .percent(let value):
            guard let offered, offered.isFinite else { return nil }
            return max(0, offered * value)
        }
    }
}

struct IntelligentUILengthFrame: Layout {
    let width: IntelligentUILength?
    let height: IntelligentUILength?
    let fontUnit: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = width?.resolve(relativeTo: proposal.width, em: fontUnit)
        let h = height?.resolve(relativeTo: proposal.height, em: fontUnit)
        let content = subviews.first?.sizeThatFits(ProposedViewSize(width: w ?? proposal.width,
                                                                     height: h ?? proposal.height)) ?? .zero
        return CGSize(width: max(0, w ?? content.width), height: max(0, h ?? content.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

struct IntelligentUILengthModifier: ViewModifier {
    let width: IntelligentUILength?
    let height: IntelligentUILength?
    let fontUnit: CGFloat

    func body(content: Content) -> some View {
        IntelligentUILengthFrame(width: width, height: height, fontUnit: fontUnit) { content }
    }
}
