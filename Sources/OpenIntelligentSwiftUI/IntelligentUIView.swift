import SwiftUI
import OpenUICore

/// Renders externally supplied state with the matching component library.
public struct IntelligentUIView: View {
    private let state: OpenUIState
    private let library: IntelligentUILibrary
    @Environment(\.intelligentUITheme) private var theme

    public init(state: OpenUIState, library: IntelligentUILibrary) {
        self.state = state
        self.library = library
    }

    public var body: some View {
        OpenUICoreView(state: state, registry: library.readerComponents.registry)
            .intelligentUILayoutTrace("renderer-content")
            .frame(maxWidth: theme.readingWidth, alignment: .leading)
            .intelligentUILayoutTrace("renderer-frame", "limit=\(LayoutTrace.number(theme.readingWidth))")
            .font(theme.bodyFont)
            .foregroundStyle(theme.primaryText)
            .tint(theme.accent)
    }
}
