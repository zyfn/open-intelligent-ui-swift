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
        NativeComponentInput(element: element, registry: registry, state: state,
            contentIdentity: contentIdentity, content: content).equatable()
    }
}

final class NativeComponentContentIdentity {}

/// Reuses the enclosing Host's reads. A standalone library surface creates one
/// subscription for its supplied Context instead of observing every State
/// publication. This is a presentation boundary, not another document owner.
package struct OpenUIContextContent<Content: View>: View {
    private let context: OpenUIComponentContext
    private let content: (OpenUIComponentContext) -> Content

    package init(context: OpenUIComponentContext,
                 @ViewBuilder content: @escaping (OpenUIComponentContext) -> Content) {
        self.context = context; self.content = content
    }

    package var body: some View {
        if context.hasNativeReadScope { content(context) }
        else { NativeStandaloneComponentContent(context: context, content: content) }
    }
}

private struct NativeStandaloneComponentContent<Content: View>: View {
    let context: OpenUIComponentContext
    let content: (OpenUIComponentContext) -> Content
    @StateObject private var subscription = NativeComponentSubscription()

    var body: some View { content(context.observing(with: subscription)) }
}

/// EnvironmentObject resolution stays at the public entry for nested document
/// overrides. Compare only parent-supplied inputs here: dynamic properties have
/// their own invalidation and lifetime in the mounted content below this gate.
private struct NativeComponentInput<Content: View>: View, Equatable {
    let element: EvaluatedElement
    let registry: OpenUIComponentRegistry
    let state: OpenUIState
    let contentIdentity: NativeComponentContentIdentity
    let content: (OpenUIComponentContext) -> Content

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.state === rhs.state && lhs.contentIdentity === rhs.contentIdentity
            && lhs.registry.renderRevision == rhs.registry.renderRevision
            && nativePresentationInputsEqual(lhs.element, rhs.element)
    }

    var body: some View {
        NativeComponentContent(element: element, registry: registry, state: state,
            contentIdentity: contentIdentity, content: content)
    }
}

/// Environment changes and this node's committed update signal reach the
/// content independently of unchanged inputs from a shared State broadcast.
private struct NativeComponentContent<Content: View>: View {
    let element: EvaluatedElement
    let registry: OpenUIComponentRegistry
    let state: OpenUIState
    // Preserve closure identity in the child value as well as the input gate.
    let contentIdentity: NativeComponentContentIdentity
    let content: (OpenUIComponentContext) -> Content
    @StateObject private var subscription = NativeComponentSubscription()
    @Environment(\.openUIContextValues) private var values
    @Environment(\.openUIResources) private var resources
    @Environment(\.openUIFormName) private var formName
    @Environment(\.openUIExactFormName) private var exactFormName
    @Environment(\.openUIProgramScoped) private var programScoped
    @Environment(\.openUIInteractionScopeReady) private var interactionScopeReady
    @Environment(\.openUIActivationIntent) private var activationIntent
    @Environment(\.openUIUserInteraction) private var userInteraction

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
