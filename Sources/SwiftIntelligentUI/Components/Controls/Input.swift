import SwiftUI
import OpenUILang
import OpenUISwiftUI

enum InputComponent {
    static var component: OpenUIComponent {
        let value = ParamDef(name: "value", required: true, isBindable: true, schema: .object([
            .init(key: "type", value: .array([.string("string"), .string("number")]))
        ]))
        return OpenUIComponent(name: "Input", description: "Text or number input. type defaults to text. Bind value to a $variable; literals are read-only. Numeric drafts stay visible while editing, finite values update the binding, empty input writes null, invalid drafts preserve the previous value until blur. Numbers use dot decimals and allow comma grouping.", params: [
            value, OpenUIParameter.string("label", required: false),
            OpenUIParameter.string("type", required: false, values: ["text", "number"]),
            OpenUIParameter.string("placeholder", required: false), OpenUIParameter.string("error", required: false)
        ]) { InputView(context: $0) }
    }
}

enum InputEditing {
    static func numericValue(_ text: String) -> Value? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .null }
        guard let number = Double(text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite else { return nil }
        return .number(number)
    }
    static func text(_ value: Value) -> String {
        switch value {
        case .string(let value): return value.displayString
        case .number(let number) where number.isFinite:
            let text = String(number)
            return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        default: return ""
        }
    }
}

private struct InputView: View {
    let context: OpenUIComponentContext
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.intelligentUITheme) private var theme
    @State private var draft: String?
    @State private var lastWritten: Value?
    @FocusState private var focused: Bool
    private var value: Value { context.binding("value")?.wrappedValue ?? context.value("value") ?? .null }
    private var label: String { context.string("label") ?? "" }
    private var binding: Binding<String> {
        Binding(get: { draft ?? InputEditing.text(value) }, set: { text in
            guard context.canInteract else { return }
            if context.string("type") == "number" {
                draft = text
                if let parsed = InputEditing.numericValue(text) {
                    lastWritten = parsed
                    context.binding("value")?.wrappedValue = parsed
                }
            } else {
                context.binding("value")?.wrappedValue = .string(OpenUIString(text))
            }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacingUnit * 2) {
            if !label.isEmpty { Text(label).font(theme.labelFont) }
            TextField(context.string("placeholder") ?? "", text: binding)
                .font(theme.bodyFont).textFieldStyle(.plain)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { focused = false }
                #if os(iOS)
                .keyboardType(context.string("type") == "number" ? .numbersAndPunctuation : .default)
                #endif
                .modifier(FieldSurface(focused: focused, invalid: !(context.string("error") ?? "").isEmpty))
                .accessibilityLabel(label.isEmpty ? context.string("placeholder") ?? "输入" : label)
                .accessibilityHint(context.string("error") ?? "")
            FieldError(message: context.string("error"))
        }
        .foregroundStyle(theme.primaryText)
        .disabled(!context.canInteract || context.binding("value") == nil)
        .onChange(of: focused) { if !$0 { draft = nil; lastWritten = nil } }
        .onChange(of: value) { new in
            if new != lastWritten { draft = nil }
            lastWritten = nil
        }
    }
}
