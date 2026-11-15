import SwiftUI

/// Hosts one native OpenUI document using only the supplied registry.
/// Component libraries own typography, color, layout and loading presentation.
/// The host injects the same state consumed by all registered component views.
public struct SwiftLangView: View {
    @ObservedObject private var state: OpenUIState
    private let registry: OpenUIComponentRegistry

    public init(state: OpenUIState, registry: OpenUIComponentRegistry) {
        self.state = state
        self.registry = registry
    }

    public var body: some View {
        Group {
            if let root = state.root ?? state.presentationRoot.flatMap({
                OpenUIPresentationProxy.element($0, registry: registry)
            }) {
                RenderNode(element: root, registry: registry)
            }
        }
        .environmentObject(state)
    }
}
