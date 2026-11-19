import SwiftUI
import SwiftLang

/// Intelligent UI owns its button presentation. Dispatch and readiness still
/// use the shared context, including source-epoch and drag-intent protection.
struct OpenIntelligentUIActionSurface<Content: View>: View {
    private let context: OpenUIComponentContext
    private let action: ActionPlan
    private let role: ButtonRole?
    private let showsProgress: Bool
    private let progressTint: Color?
    private let content: Content
    init(context: OpenUIComponentContext, action: ActionPlan, role: ButtonRole? = nil,
         showsProgress: Bool = false, progressTint: Color? = nil,
         @ViewBuilder content: () -> Content) {
        self.context = context
        self.action = action
        self.role = role
        self.showsProgress = showsProgress
        self.progressTint = progressTint
        self.content = content()
    }

    var body: some View {
        OpenUIContextContent(context: context) { context in
            IntelligentUIActionContent(context: context, action: action, role: role,
                showsProgress: showsProgress, progressTint: progressTint, content: content)
        }
    }
}

private struct IntelligentUIActionContent<Content: View>: View {
    let context: OpenUIComponentContext
    let action: ActionPlan
    let role: ButtonRole?
    let showsProgress: Bool
    let progressTint: Color?
    let content: Content
    @Environment(\.isEnabled) private var hostEnabled
    @Environment(\.locale) private var locale
    @Environment(\.openIntelligentUIFormValidation) private var formValidation
    @State private var operation: UUID?

    var body: some View {
        Button(role: role) {
            guard hostEnabled, operation == nil, context.canActivate else { return }
            context.recordUserInteraction()
            // A host interaction callback may synchronously replace the source.
            guard context.canActivate else { return }
            if action.steps.contains(where: { step in
                if case .continueConversation = step { return true }
                return false
            }), formValidation?.submit() == false { return }
            let ticket = UUID()
            operation = ticket
            Task { @MainActor in
                defer {
                    if operation == ticket, context.isCurrentPresentation { operation = nil }
                }
                guard context.canActivate else { return }
                await context.perform(action)
            }
        } label: {
            content.contentShape(Rectangle())
                .environment(\.openIntelligentUIInteractiveContent, true)
                .modifier(OpenIntelligentUIActionProgress(active: showsProgress && operation != nil,
                    tint: progressTint))
        }
        .accessibilityValue(showsProgress && operation != nil
            ? SDKStrings.text("progress.processing", locale: locale) : "")
        .disabled(!context.canInteract || operation != nil)
        .environment(\.openIntelligentUIActionAppearance, appearance)
        .onChange(of: context.presentationSourceRevision) { _ in operation = nil }
    }

    private var appearance: OpenIntelligentUIActionAppearance {
        if !hostEnabled { return .disabled }
        if operation != nil { return .performing }
        return context.canInteract ? .ready : .pending
    }
}

enum OpenIntelligentUIActionAppearance { case inherited, ready, pending, performing, disabled }
private struct OpenIntelligentUIActionAppearanceKey: EnvironmentKey {
    static let defaultValue = OpenIntelligentUIActionAppearance.inherited
}
extension EnvironmentValues {
    var openIntelligentUIActionAppearance: OpenIntelligentUIActionAppearance {
        get { self[OpenIntelligentUIActionAppearanceKey.self] }
        set { self[OpenIntelligentUIActionAppearanceKey.self] = newValue }
    }
}

/// Preserve the label's geometry while a delayed indicator occupies its pixels.
/// This timing is a presentation detail, independent of the standard UI theme.
private struct OpenIntelligentUIActionProgress: ViewModifier {
    let active: Bool
    let tint: Color?
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        content.opacity(active && visible ? 0 : 1)
            .overlay {
                if active && visible {
                    Group {
                        if reduceMotion { Image(systemName: "ellipsis") }
                        else { ProgressView().controlSize(.small) }
                    }
                    .tint(tint ?? theme.actionAccent)
                    .foregroundStyle(tint ?? theme.actionAccent)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .task(id: active) {
                visible = false
                guard active else { return }
                do { try await Task.sleep(nanoseconds: 200_000_000) }
                catch { return }
                guard !Task.isCancelled else { return }
                visible = true
            }
    }
}
