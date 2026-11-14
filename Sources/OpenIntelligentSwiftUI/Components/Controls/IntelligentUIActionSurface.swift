import SwiftUI
import OpenUILang
import OpenUICore

/// Intelligent UI owns its button presentation. Dispatch and readiness still
/// use the shared context, including source-epoch and drag-intent protection.
struct IntelligentUIActionSurface<Content: View>: View {
    private let context: OpenUIComponentContext
    private let action: ActionPlan
    private let role: ButtonRole?
    private let showsProgress: Bool
    private let progressTint: Color?
    private let content: Content
    // Readiness may change without changing the component's evaluated props.
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.isEnabled) private var hostEnabled
    @Environment(\.locale) private var locale
    @State private var operation: UUID?

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
        Button(role: role) {
            guard hostEnabled, operation == nil, context.canActivate else { return }
            context.recordUserInteraction()
            // A host interaction callback may synchronously replace the source.
            guard context.canActivate else { return }
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
                .environment(\.intelligentUIInteractiveContent, true)
                .modifier(IntelligentUIActionProgress(active: showsProgress && operation != nil,
                    tint: progressTint))
        }
        .accessibilityValue(showsProgress && operation != nil
            ? SDKStrings.text("progress.processing", locale: locale) : "")
        .disabled(!context.canInteract || operation != nil)
        .environment(\.intelligentUIActionAppearance, appearance)
        .onChange(of: context.presentationSourceRevision) { _ in operation = nil }
    }

    private var appearance: IntelligentUIActionAppearance {
        if !hostEnabled { return .disabled }
        if operation != nil { return .performing }
        return context.canInteract ? .ready : .pending
    }
}

enum IntelligentUIActionAppearance { case inherited, ready, pending, performing, disabled }
private struct IntelligentUIActionAppearanceKey: EnvironmentKey {
    static let defaultValue = IntelligentUIActionAppearance.inherited
}
extension EnvironmentValues {
    var intelligentUIActionAppearance: IntelligentUIActionAppearance {
        get { self[IntelligentUIActionAppearanceKey.self] }
        set { self[IntelligentUIActionAppearanceKey.self] = newValue }
    }
}

/// Preserve the label's geometry while a delayed indicator occupies its pixels.
/// This timing is a presentation detail, independent of the standard UI theme.
private struct IntelligentUIActionProgress: ViewModifier {
    let active: Bool
    let tint: Color?
    @Environment(\.intelligentUITheme) private var theme
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
