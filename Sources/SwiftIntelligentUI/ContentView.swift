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
        SwiftLangView(state: state, registry: library.readerComponents.registry)
            .openIntelligentUILayoutTrace("renderer-content")
            .frame(maxWidth: theme.readingWidth, alignment: .leading)
            .openIntelligentUILayoutTrace("renderer-frame", "limit=\(LayoutTrace.number(theme.readingWidth))")
            .font(theme.bodyFont)
            .foregroundStyle(theme.primaryText)
            .tint(theme.accent)
    }
}
