import SwiftUI

/// Mounts a registered component against the shared session. Component libraries
/// may wrap the supplied context to apply their own visual presentation policy.
public struct OpenUIComponentHost<Content: View>: View {
    private let element: EvaluatedElement
    private let registry: OpenUIComponentRegistry
    private let content: (OpenUIComponentContext) -> Content
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.openUIContextValues) private var values
    @Environment(\.openUIResources) private var resources
    @Environment(\.openUIFormName) private var formName
    @Environment(\.openUIExactFormName) private var exactFormName
    @Environment(\.openUIProgramScoped) private var programScoped
    @Environment(\.openUIInteractionScopeReady) private var interactionScopeReady
    @Environment(\.openUIActivationIntent) private var activationIntent
    @Environment(\.openUIUserInteraction) private var userInteraction

    public init(element: EvaluatedElement, registry: OpenUIComponentRegistry,
                @ViewBuilder content: @escaping (OpenUIComponentContext) -> Content) {
        self.element = element
        self.registry = registry
        self.content = content
    }

    public var body: some View {
        let element = self.element.isSourceComplete ? self.element : state.liveElement(matching: self.element)
        var context = OpenUIComponentContext(element: element, registry: registry, state: state,
            values: values, resources: resources, formName: formName, exactFormName: exactFormName)
        context.interactionScopeReady = interactionScopeReady
        context.activationIntent = activationIntent
        context.onUserInteraction = userInteraction
        let view = content(context)
            .environment(\.openUIInlineLinksReady, context.canInteract)
            .allowsHitTesting(element.sourceReadiness.placeholder == nil)
        // Reset once at the tree's entry, including direct RenderNode hosts.
        // Repeating an explicit id on every descendant would merge lazy siblings.
        return Group {
            if programScoped == ObjectIdentifier(state) { view }
            else {
                OpenUIProgramScope(owner: ObjectIdentifier(state), revision: state.presentationRevision,
                    resources: state.resourceStore,
                    content: view.environment(\.openUIMediaCache, state.mediaCache))
            }
        }
    }
}

private struct OpenUIProgramScope<Content: View>: View {
    let owner: ObjectIdentifier
    let revision: Int
    let resources: NativeResourceStore
    let content: Content
    @Namespace private var instance
    @Environment(\.openUIResourceContext) private var parentResources

    var body: some View {
        content.environment(\.openUIProgramScoped, owner)
            .openUIResourceContext(resources.scoped(parentResources))
            .id(OpenUIProgramIdentity(instance: instance, owner: owner, revision: revision))
    }
}

private struct OpenUIProgramIdentity: Hashable {
    let instance: Namespace.ID
    let owner: ObjectIdentifier
    let revision: Int
}
