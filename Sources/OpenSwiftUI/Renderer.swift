import SwiftUI
import OpenUICore
import OpenUILang

/// Applies the standard library's appearance to a host-owned state and registry.
/// Most clients select `OpenUILibrary.standard()` and present `OpenUIView`, which
/// keeps the generation contract, reader and native registry paired together.
/// Use this lower-level view when supplying the matched registry directly;
/// retain the state for the document's lifetime and feed content outside `body`.
public struct OpenUIRenderer: View {
    private let state: OpenUIState
    private let registry: ComponentRegistry
    @Environment(\.openUITheme) private var theme

    public init(state: OpenUIState, registry: ComponentRegistry) {
        self.state = state
        self.registry = registry
    }

    public var body: some View {
        OpenUICoreView(state: state, registry: registry)
            .openUIFont(theme.textBodyDefault)
            .foregroundStyle(theme.textNeutralPrimary)
            .tint(theme.interactiveAccentDefault)
    }
}
