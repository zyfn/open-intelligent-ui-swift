import SwiftLang
import SwiftUI

struct OpenUINativeButton: View {
    let context: OpenUIComponentContext
    private var role: ButtonRole? { context.string("type") == "destructive" ? .destructive : nil }
    private var variant: String { context.string("variant") ?? "primary" }
    private var continuesConversation: Bool { NativeActionPresentation.button(context.element).continuesConversation }
    private var presentationReady: Bool {
        let source = context.element.sourceReadiness
        return context.codeUnitString("label") != nil && source.closed
          && ["label", "variant", "type", "size"].allSatisfy { source[$0].complete }
    }
    var body: some View {
        button.buttonStyle(
            NativeActionButtonStyle(
                theme: context.theme, variant: variant,
                size: context.string("size"), destructive: role == .destructive,
                stretchesTarget: context.stretchesVertically)
        )
        .accessibilityLabel(context.string("label") ?? "")
        .opacity(presentationReady ? 1 : 0)
        .accessibilityHidden(!presentationReady)
        .allowsHitTesting(presentationReady)
    }
    private var button: some View {
        OpenUIActionSurface(
            context: context, message: context.string("label") ?? "", action: context.value("action"),
            role: role, useNativeStyle: true, validateForm: true, showsProgress: true
        ) {
            Group {
                if continuesConversation {
                    NativeConversationActionLabel(text: context.string("label") ?? "", theme: context.theme,
                        fillsWidth: context.fillsControlWidth)
                } else {
                    Text(context.string("label") ?? "").fixedSize(horizontal: false, vertical: true)
                }
            }
                // The parent lays out the outer touch target. Expanding the label
                // to that height would paint the invisible target as button fill.
                // Keep natural text height (including wrapped lines), while column
                // actions may still fill their proposed width.
                .frame(maxWidth: context.fillsControlWidth ? .infinity : nil)
        }
        .conversationAccessoryProgress(continuesConversation)
    }
}

struct NativeIconButton: View {
  let context: OpenUIComponentContext
  var body: some View {
    OpenUIActionSurface(
      context: context, message: context.string("name") ?? "", action: context.value("action"),
      useNativeStyle: true, validateForm: context.string("variant") == "primary",
      showsProgress: true
    ) {
      context.slot("icon").frame(minWidth: 20, minHeight: 20)
    }.buttonStyle(
      NativeActionButtonStyle(
        theme: context.theme, variant: context.string("variant") ?? "secondary",
        size: context.string("size"), destructive: false,
        iconOnly: true, circular: context.string("shape") == "circle")
    )
    .accessibilityLabel(context.string("name") ?? "")
  }
}

struct NativeFollowUpBlock: View {
  let context: OpenUIComponentContext
  var body: some View {
    NativeWrappingRow(gap: context.theme.spaceS) {
      ForEach(context.children("items")) { item in
        context.render(item.value)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct NativeFollowUpItem: View {
  let context: OpenUIComponentContext
  @Environment(\.isEnabled) private var enabled
  private var text: String { context.string("text") ?? "" }
  private var cornerRadius: CGFloat {
    NativeButtonShape.readableRadius(horizontal: context.theme.spaceM, vertical: context.theme.spaceS)
  }
  private var shape: NativeButtonShape {
    NativeButtonShape(radius: nil, maximumRadius: cornerRadius)
  }
  var body: some View {
    OpenUIActionSurface(context: context, message: text, action: Self.action(for: text),
      useNativeStyle: true) {
      Text(text)
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.leading)
        .nativeTextStyle(context.theme.textStyle(.compactAction),
          color: enabled ? context.theme.textNeutralPrimary : context.theme.textNeutralTertiary)
        .padding(.horizontal, context.theme.spaceM)
        .padding(.vertical, context.theme.spaceS)
        .background(context.theme.sunk, in: shape)
        .overlay(shape.strokeBorder(context.theme.borderDefault,
          lineWidth: context.presentation.borderWidth).allowsHitTesting(false))
        .openUIControlTarget(alignment: .leading)
    }
    .buttonStyle(NativeQuietButtonStyle(theme: context.theme, cornerRadius: cornerRadius))
    .accessibilityLabel(text)
    .accessibilityHint(Text("Send this question to continue", bundle: NativeControlResources.bundle))
    .accessibilityIdentifier("openui.followup")
  }
  static func action(for text: String) -> Value {
    .object(OpenUIObject([
      ObjectField(key: OpenUIString("type"), value: .string(OpenUIString("continue_conversation"))),
      ObjectField(key: OpenUIString("message"), value: .string(OpenUIString(text))),
    ]))
  }
}
