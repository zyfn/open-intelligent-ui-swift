import SwiftUI
import SwiftLang

enum InputComponent {
    static var component: OpenUIComponent {
        let value = ParamDef(name: "value", required: true, isBindable: true, schema: .object([
            .init(key: "type", value: .array([.string("string"), .string("number")]))
        ]))
        return OpenUIComponent(name: "Input", description: "Text or number input. type defaults to text. Bind value to a $variable; literals are read-only. Finite numeric edits update the binding and empty input writes null. Unapplied numeric drafts show the current committed value during editing; invalid drafts remain visible for review afterward and never replace it. Numbers use dot decimals and valid comma thousands grouping. Form submission validates declared rules before continuing the conversation.", params: [
            value, OpenUIParameter.string("label", required: false),
            OpenUIParameter.string("type", required: false, values: ["text", "number"]),
            OpenUIParameter.string("placeholder", required: false), IntelligentUIRules.parameter()
        ]) { InputView(context: $0) }
    }
}

enum InputEditing {
    static func numericValue(_ text: String) -> Value? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .null }
        // Editing grammar only. Existing source values and price strings are not rewritten.
        let pattern = #"^[+-]?(?:(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#
        guard text.range(of: pattern, options: .regularExpression) != nil,
              let number = Double(text.replacingOccurrences(of: ",", with: "")), number.isFinite else { return nil }
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

/// Presentation-only editing session. The binding remains the committed value.
/// Invalid drafts and drafts superseded by an external edit require an explicit choice.
struct NumericInputDraft {
    private(set) var text: String?
    private(set) var needsReview = false

    mutating func edit(_ text: String) -> Value? {
        self.text = text
        needsReview = false
        return InputEditing.numericValue(text)
    }
    mutating func finish(current: Value) {
        guard let text else { return }
        if InputEditing.numericValue(text) == current { discard() }
        else { needsReview = true }
    }
    mutating func externalValueChanged(to value: Value) {
        guard let text, InputEditing.numericValue(text) != value else { return }
        needsReview = true
    }
    mutating func discard() { text = nil; needsReview = false }
    var parsed: Value? { text.flatMap(InputEditing.numericValue) }
    func isPending(current: Value) -> Bool {
        guard text != nil else { return false }
        return parsed != current
    }
}

private struct InputView: View {
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.locale) private var locale
    @State private var draft = NumericInputDraft()
    @FocusState private var focused: Bool
    private var value: Value { context.binding("value")?.wrappedValue ?? context.value("value") ?? .null }
    private var label: String { context.string("label") ?? "" }
    private var numeric: Bool { context.string("type") == "number" }
    private var showingReview: Bool { numeric && draft.needsReview && !focused }
    private var committedText: String {
        let committed = InputEditing.text(value)
        return committed.isEmpty ? SDKStrings.text("controls.input.empty_value", locale: locale) : committed
    }
    private var reviewMessage: String {
        SDKStrings.text(draft.parsed == nil ? "controls.input.invalid" : "controls.input.external_change", locale: locale, committedText)
    }
    private var pendingMessage: String {
        SDKStrings.text("controls.input.pending", locale: locale, committedText)
    }
    private var feedbackMessage: String {
        guard numeric else { return "" }
        if showingReview { return reviewMessage }
        return draft.isPending(current: value) ? pendingMessage : ""
    }
    private var binding: Binding<String> {
        Binding(get: { (numeric ? draft.text : nil) ?? InputEditing.text(value) }, set: { text in
            guard context.canInteract else { return }
            if numeric {
                if let parsed = draft.edit(text) {
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
                .onSubmit { if numeric { draft.finish(current: value) }; focused = false }
                #if os(iOS)
                .keyboardType(context.string("type") == "number" ? .numbersAndPunctuation : .default)
                #endif
                .modifier(FieldSurface(focused: focused, invalid: showingReview))
                .accessibilityLabel(label.isEmpty ? context.string("placeholder") ?? SDKStrings.text("controls.input.label", locale: locale) : label)
                .accessibilityHint(feedbackMessage)
            if showingReview {
                Label(reviewMessage, systemImage: "exclamationmark.circle")
                    .font(theme.captionFont).foregroundStyle(theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: theme.innerSpacing) { reviewActions }
                    VStack(alignment: .leading, spacing: theme.innerSpacing) { reviewActions }
                }
            } else if numeric && draft.isPending(current: value) {
                Text(pendingMessage)
                    .font(theme.captionFont).foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(theme.primaryText)
        .disabled(!context.canInteract || context.binding("value") == nil)
        .onChange(of: focused) { if !$0 && numeric { draft.finish(current: value) } }
        .onChange(of: value) { if numeric { draft.externalValueChanged(to: $0) } }
        .modifier(IntelligentUIFormFieldFeedback(context: context, valueKey: "value"))
    }
    @ViewBuilder private var reviewActions: some View {
        Button(SDKStrings.text("controls.input.restore", locale: locale)) { draft.discard() }
            .buttonStyle(UpstreamButtonStyle(variant: "ghost", tint: theme.actionAccent, size: "sm"))
        if let parsed = draft.parsed {
            Button(SDKStrings.text("controls.input.accept", locale: locale)) {
                guard context.canInteract, let binding = context.binding("value") else { return }
                binding.wrappedValue = parsed
                draft.discard()
            }.buttonStyle(UpstreamButtonStyle(variant: "outline", tint: theme.actionAccent, size: "sm"))
        }
    }
}
