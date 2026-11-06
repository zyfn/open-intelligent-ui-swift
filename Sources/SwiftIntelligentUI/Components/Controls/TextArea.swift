import SwiftUI
import OpenUILang
import OpenUISwiftUI

enum TextAreaComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "TextArea", description: "Multiline input bound to a string variable. rows defaults to 3, rounded and clamped to 2...20; height scales with Dynamic Type. Literal values are read-only.", params: [
            OpenUIParameter.selection("value"), OpenUIParameter.string("label", required: false),
            OpenUIParameter.string("placeholder", required: false), Parameter.number("rows", minimum: 2, maximum: 20),
            OpenUIParameter.string("error", required: false)
        ]) { TextAreaView(context: $0) }
    }
}

private struct TextAreaView: View {
    let context: OpenUIComponentContext
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.intelligentUITheme) private var theme
    @ScaledMetric(relativeTo: .body) private var lineHeight = 24.0
    @FocusState private var focused: Bool
    private var text: Binding<String> {
        Binding(get: { InputEditing.text(context.binding("value")?.wrappedValue ?? context.value("value") ?? .null) },
                set: { context.binding("value")?.wrappedValue = .string(OpenUIString($0)) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacingUnit * 2) {
            if let label = context.string("label"), !label.isEmpty { Text(label).font(theme.labelFont) }
            ZStack(alignment: .topLeading) {
                TextEditor(text: text).font(theme.bodyFont)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(minHeight: lineHeight * min(20, max(2, (context.number("rows") ?? 3).rounded())))
                if text.wrappedValue.isEmpty, let placeholder = context.string("placeholder") {
                    Text(placeholder).foregroundStyle(theme.secondaryText).padding(6).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .modifier(FieldSurface(focused: focused, invalid: !(context.string("error") ?? "").isEmpty, multiline: true))
            .accessibilityLabel(context.string("label") ?? context.string("placeholder") ?? "多行输入")
            .accessibilityHint(context.string("error") ?? "")
            FieldError(message: context.string("error"))
        }
        .foregroundStyle(theme.primaryText)
        .disabled(!context.canInteract || context.binding("value") == nil)
    }
}
