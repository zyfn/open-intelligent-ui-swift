import SwiftUI
import SwiftLang

/// Renders externally supplied state with the matching component library.
struct OpenIntelligentUIContentView: View {
    private let state: OpenUIState
    private let library: OpenIntelligentUIComponents
    @Environment(\.openIntelligentUITheme) private var theme

    public init(state: OpenUIState, library: OpenIntelligentUIComponents) {
        self.state = state
        self.library = library
    }

    public var body: some View {
        IntelligentUIReadingWidthLayout(maximumWidth: theme.readingWidth) {
            SwiftLangView(state: state, registry: library.readerComponents.registry)
                // The renderer root may resolve an authored percentage height
                // against an actual finite host proposal. Auto-height roots still
                // use natural height; child containers establish their own scope.
                .environment(\.openIntelligentUIItemSizing, IntelligentUIItemSizing(hasDefiniteHeight: true))
                .openIntelligentUILayoutTrace("renderer-content")
        }
        .openIntelligentUILayoutTrace("renderer-frame", "limit=\(LayoutTrace.number(theme.readingWidth))")
        .font(theme.bodyFont)
        .foregroundStyle(theme.primaryText)
        .tint(theme.accent)
        .modifier(IntelligentUIViewportModifier())
    }
}

/// Limit the reading width without replacing the host's height proposal with
/// the measured content height. Root percentages must keep their host reference
/// during placement as well as measurement.
private struct IntelligentUIReadingWidthLayout: Layout {
    let maximumWidth: CGFloat

    private func contentProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
        let limit = maximumWidth.isFinite ? max(0, maximumWidth) : nil
        return ProposedViewSize(width: limit.map { min(width ?? $0, $0) } ?? width,
                                height: proposal.height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let offered = contentProposal(proposal)
        let measured = subviews.first?.sizeThatFits(offered) ?? .zero
        let width = proposal.width == nil ? measured.width : offered.width ?? measured.width
        return CGSize(width: FlexGeometry.length(width), height: FlexGeometry.length(measured.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: contentProposal(proposal))
    }
}
