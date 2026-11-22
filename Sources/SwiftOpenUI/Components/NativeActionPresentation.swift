import SwiftLang
import SwiftUI

/// Presentation only. Never evaluates a message expression or executes an action
/// to decide whether an existing control continues a chat.
struct NativeActionPresentation: Equatable {
    var continuesConversation = false

    static func classify(_ action: Value?, ready: Bool) -> Self {
        guard ready else { return .init() }
        guard let action, action != .null else {
            // The existing dispatcher sends the button label for nil/null.
            return .init(continuesConversation: true)
        }
        switch action {
        case .actionPlan(let plan):
            guard plan.isSourceComplete else { return .init() }
            var conversations = 0
            var hasOtherIntent = false
            for step in plan.steps {
                switch step {
                case .continueConversation:
                    conversations += 1
                case .run, .custom, .openUrl:
                    hasOtherIntent = true
                case .set, .reset:
                    break
                }
            }
            return .init(continuesConversation: conversations == 1 && !hasOtherIntent)
        case .object(let fields):
            // Match the legacy dispatcher's last-key and missing-type behavior.
            // A `steps` property is ordinary object data, never an ActionPlan.
            let type: OpenUIString
            if case .string(let value) = fields.last(where: { $0.key == "type" })?.value,
               !value.isEmpty { type = value }
            else { type = "continue_conversation" }
            return .init(continuesConversation: type == "continue_conversation")
        default:
            return .init()
        }
    }

    static func button(_ element: EvaluatedElement) -> Self {
        guard element.typeName == "Button" else { return .init() }
        return classify(PropValue.value(element, "action"),
                        ready: element.sourceReadiness.closed && element.sourceReadiness["action"].complete)
    }
}

extension EnvironmentValues {
    @Entry var openUIActionLabelFont: OpenUIFont? = nil
}

/// A single label for a native Button, inheriting its declared font, color and width policy.
struct NativeConversationActionLabel: View {
    let text: String
    let theme: OpenUIThemeValues
    var fillsWidth = false
    @Environment(\.openUIActionLabelFont) private var actionFont
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let font = actionFont ?? theme.textStyle(.action).font
        let progressInset = (max(1, font.size * 1.25 * scale) + theme.spaceS) / 2
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, progressInset)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .overlay(alignment: .trailing) {
                NativeConversationAccessory(width: progressInset, height: font.measuredLineHeight(scale: scale))
            }
    }
}

private struct NativeConversationAccessory: View {
    let width: CGFloat
    let height: CGFloat
    @Environment(\.openUIActionAccessoryActive) private var active

    var body: some View {
        NativeDelayedPresentation(active: active) { visible in
            Color.clear.frame(width: width, height: height)
                .overlay {
                    if visible { NativeLoadingIndicator() }
                }
        }
        .fixedSize()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
