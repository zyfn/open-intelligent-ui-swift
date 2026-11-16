import SwiftUI
import SwiftLang

/// For a card with one primary action. Its label must contain presentation only,
/// not nested buttons. The host decides how the resulting event is handled.
public struct OpenUIActionSurface<Content: View>: View {
    private let context: OpenUIComponentContext
    private enum Dispatch { case plan(ActionPlan), value(String, Value?) }
    private let dispatch: Dispatch
    private let content: Content
    private let role: ButtonRole?
    private let useNativeStyle: Bool
    private let validateForm: Bool
    private let showsProgress: Bool
    private var usesConversationAccessory = false
    // Source readiness can change interaction eligibility without changing props.
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.openUIFormValidation) private var validation
    @Environment(\.isEnabled) private var hostEnabled
    @State private var performing = false

    public init(context: OpenUIComponentContext, action: ActionPlan, role: ButtonRole? = nil, useNativeStyle: Bool = false, validateForm: Bool = false, showsProgress: Bool = false, @ViewBuilder content: () -> Content) {
        self.context = context; self.dispatch = .plan(action); self.content = content()
        self.role = role; self.useNativeStyle = useNativeStyle; self.validateForm = validateForm
        self.showsProgress = showsProgress
    }

    public init(context: OpenUIComponentContext, message: String, action: Value? = nil, role: ButtonRole? = nil, useNativeStyle: Bool = false, validateForm: Bool = false, showsProgress: Bool = false, @ViewBuilder content: () -> Content) {
        self.context = context; self.dispatch = .value(message, action); self.content = content()
        self.role = role; self.useNativeStyle = useNativeStyle; self.validateForm = validateForm
        self.showsProgress = showsProgress
    }

    /// Internal presentation choice; the existing dispatch/validation path is unchanged.
    func conversationAccessoryProgress(_ enabled: Bool = true) -> Self {
        var copy = self
        copy.usesConversationAccessory = enabled
        return copy
    }

    @ViewBuilder public var body: some View {
        if useNativeStyle { button } else { button.buttonStyle(.plain) }
    }
    private var button: some View {
        Button(role:role) {
            guard !performing, context.canActivate else { return }
            context.recordUserInteraction()
            // A form submission must see the latest local draft, even when
            // the user taps its action before the edit debounce expires.
            if needsValidation {
                let prepared = validateForm ? validation?.validateAll() : validation?.preparePendingWrites()
                if prepared == false { validation?.requestInvalidFieldFocus(); return }
            }
            guard context.canActivate else { return }
            performing = true
            Task { @MainActor in
                defer { performing = false }
                switch dispatch {
                case .plan(let plan): await context.perform(plan)
                case .value(let message, let action): await context.triggerAction(message, action: action)
                }
            }
        } label: {
            Group {
                if useNativeStyle { content }
                else { content.openUIControlTarget(alignment: .leading) }
            }.contentShape(Rectangle())
                .environment(\.openUICardIsAction, true)
                .modifier(NativeActionProgress(active: showsProgress && performing,
                                               usesAccessory: usesConversationAccessory))
        }
        .accessibilityValue(accessibilityStatus)
        .disabled(!context.canInteract || performing)
        .environment(\.openUIActionAppearance,
            !hostEnabled ? .disabled : performing ? .performing : context.canInteract ? .ready : .pending)
    }
    @MainActor private var accessibilityStatus: Text {
        if performing { return Text("In progress", bundle: NativeControlResources.bundle) }
        if hostEnabled && !context.canInteract {
            if context.hasDataFailure { return Text("Content unavailable", bundle: NativeControlResources.bundle) }
            if context.hasInterruptedData || (!context.isStreaming && !context.hasPendingData) {
                return Text("Content is incomplete", bundle: NativeControlResources.bundle)
            }
            return Text("Loading", bundle: NativeControlResources.bundle)
        }
        return Text("")
    }
    private var needsValidation: Bool {
        switch dispatch {
        case .plan(let action): return NativeFormValidation.requiresValidation(action)
        case .value(_,let value): return NativeFormValidation.requiresValidation(action: value)
        }
    }
}
