import SwiftUI

/// Mounts a registered component against the shared session. Component libraries
/// may wrap the supplied context to apply their own visual presentation policy.
public struct OpenUIComponentHost<Content: View>: View {
    private let element: EvaluatedElement
    private let registry: OpenUIComponentRegistry
    private let content: (OpenUIComponentContext) -> Content
    private let contentIdentity: NativeComponentContentIdentity
    @EnvironmentObject private var state: OpenUIState

    public init(element: EvaluatedElement, registry: OpenUIComponentRegistry,
                @ViewBuilder content: @escaping (OpenUIComponentContext) -> Content) {
        self.element = element
        self.registry = registry
        self.content = content
        self.contentIdentity = NativeComponentContentIdentity()
    }

    init(element: EvaluatedElement, registry: OpenUIComponentRegistry,
         contentIdentity: NativeComponentContentIdentity,
         @ViewBuilder content: @escaping (OpenUIComponentContext) -> Content) {
        self.element = element; self.registry = registry; self.content = content
        self.contentIdentity = contentIdentity
    }

    public var body: some View {
        NativeComponentContent(element: element, registry: registry, state: state,
            contentIdentity: contentIdentity, content: content).equatable()
    }
}

final class NativeComponentContentIdentity {}

/// EnvironmentObject resolution stays at the public entry for nested document
/// overrides. Shared broadcasts stop before live lookup, readiness and Context
/// construction; this mounted node receives its own committed update signal.
private struct NativeComponentContent<Content: View>: View, Equatable {
    let element: EvaluatedElement
    let registry: OpenUIComponentRegistry
    let state: OpenUIState
    @StateObject private var subscription = NativeComponentSubscription()
    let contentIdentity: NativeComponentContentIdentity
    let content: (OpenUIComponentContext) -> Content
    @Environment(\.openUIContextValues) private var values
    @Environment(\.openUIResources) private var resources
    @Environment(\.openUIFormName) private var formName
    @Environment(\.openUIExactFormName) private var exactFormName
    @Environment(\.openUIProgramScoped) private var programScoped
    @Environment(\.openUIInteractionScopeReady) private var interactionScopeReady
    @Environment(\.openUIActivationIntent) private var activationIntent
    @Environment(\.openUIUserInteraction) private var userInteraction

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.state === rhs.state && lhs.contentIdentity === rhs.contentIdentity
            && lhs.registry.renderRevision == rhs.registry.renderRevision
            && nativePresentationInputsEqual(lhs.element, rhs.element)
    }

    var body: some View {
        let (presentation, reads) = subscription.begin(element: element, state: state)
        let element = presentation.element
        var context = OpenUIComponentContext(element: element, registry: registry, state: state,
            values: values, resources: resources, formName: formName, exactFormName: exactFormName,
            nativePresentation: presentation, readScope: reads)
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
                OpenUIProgramScope(owner: ObjectIdentifier(state), revision: presentation.presentationRevision,
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
