import SwiftUI
import SwiftLang

/// Applies the standard library's appearance to a host-owned state and registry.
/// Most clients select `OpenUILibrary.openUI()` and present `OpenUIView`, which
/// keeps the generation contract, reader and native registry paired together.
/// Use this lower-level view when supplying the matched registry directly;
/// retain the state for the document's lifetime and feed content outside `body`.
struct OpenUIContentView: View {
    private let state: OpenUIState
    private let registry: OpenUIComponentRegistry
    @Environment(\.openUITheme) private var theme

    public init(state: OpenUIState, registry: OpenUIComponentRegistry) {
        self.state = state
        self.registry = registry
    }

    public var body: some View {
        SwiftLangView(state: state, registry: registry)
            .openUIFont(theme.textBodyDefault)
            .foregroundStyle(theme.textNeutralPrimary)
            .tint(theme.interactiveAccentDefault)
    }
}
