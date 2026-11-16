import SwiftUI

/// Hosts one native OpenUI document using only the supplied registry.
/// Component libraries own typography, color, layout and loading presentation.
/// The host injects the same state consumed by all registered component views.
public struct SwiftLangView: View {
    private let state: OpenUIState
    @ObservedObject private var presentation: NativePresentationStore
    private let registry: OpenUIComponentRegistry

    public init(state: OpenUIState, registry: OpenUIComponentRegistry) {
        self.state = state
        self.presentation = state.presentationStore
        self.registry = registry
    }

    public var body: some View {
        Group {
            if let root = presentation.snapshot.root ?? presentation.snapshot.presentationRoot.flatMap({
                OpenUIPresentationProxy.element($0, registry: registry)
            }) {
                RenderNode(element: root, registry: registry)
            }
        }
        .environmentObject(state)
    }
}
