import SwiftUI
import SwiftLang

/// The latest upstream form rules are validated only on a real submission.
/// Fields retain their ordinary bindings and are never rewritten by validation.
enum IntelligentUIRules {
    static func parameter() -> ParamDef {
        let fields: [(String, JSONValue)] = [
            ("required", Parameter.booleanSchema), ("email", Parameter.booleanSchema),
            ("url", Parameter.booleanSchema), ("numeric", Parameter.booleanSchema),
            ("min", Parameter.numberSchema), ("max", Parameter.numberSchema),
            ("minLength", Parameter.numberSchema), ("maxLength", Parameter.numberSchema),
            ("pattern", Parameter.stringSchema)
        ]
        return ParamDef(name: "rules", required: false, schema: .object([
            .init(key: "type", value: .string("object")),
            .init(key: "properties", value: .object(fields.map { .init(key: OpenUIString($0.0), value: $0.1) })),
            .init(key: "additionalProperties", value: .boolean(false))
        ]))
    }

    static func parse(_ value: Value?) -> [ParsedRule] {
        guard case .object = value else { return [] }
        return ["required", "email", "url", "numeric", "min", "max", "minLength", "maxLength", "pattern"].compactMap { name in
            let argument = ValueReading.field(value, name)
            switch name {
            case "required", "email", "url", "numeric":
                return argument == .boolean(true) ? ParsedRule(type: name) : nil
            case "min", "max", "minLength", "maxLength":
                return ValueReading.number(argument).map { ParsedRule(type: name, arg: .number($0)) }
            case "pattern":
                if case .string(let text) = argument {
                    return ParsedRule(type: name, arg: .string(text))
                }
                return nil
            default: return nil
            }
        }
    }

    @MainActor static func message(context: OpenUIComponentContext, valueKey: String) -> String? {
        let rules = parse(context.value("rules"))
        guard !rules.isEmpty else { return nil }
        let value = context.binding(valueKey)?.wrappedValue ?? context.value(valueKey) ?? .null
        // A required checkbox must actually be selected, not merely present.
        if valueKey == "checked", value == .boolean(false), rules.contains(where: { $0.type == "required" }) {
            return validate(.string(""), rules: [ParsedRule(type: "required")])
        }
        return validate(value, rules: rules)
    }
}

@MainActor final class IntelligentUIFormValidationStore: ObservableObject {
    @Published private(set) var errors: [String: String] = [:]
    private var fields: [String: () -> String?] = [:]
    private var submitted = false

    func register(_ id: String, check: @escaping () -> String?) {
        fields[id] = check
        if submitted { refresh(id) }
    }
    func unregister(_ id: String) {
        fields.removeValue(forKey: id)
        if errors.removeValue(forKey: id) != nil { objectWillChange.send() }
    }
    func refresh(_ id: String) {
        guard submitted, let check = fields[id] else { return }
        let message = check()
        if errors[id] != message {
            if let message { errors[id] = message }
            else { errors.removeValue(forKey: id) }
        }
    }
    func submit() -> Bool {
        submitted = true
        errors = fields.reduce(into: [String: String]()) { output, entry in
            if let failure = entry.value() { output[entry.key] = failure }
        }
        return errors.isEmpty
    }
}

extension EnvironmentValues {
    @Entry var openIntelligentUIFormValidation: IntelligentUIFormValidationStore? = nil
}

/// Registers the currently mounted field with the enclosing form; errors
/// become visible only after submission and clear when the value is corrected.
struct IntelligentUIFormFieldFeedback: ViewModifier {
    let context: OpenUIComponentContext
    let valueKey: String
    @Environment(\.openIntelligentUIFormValidation) private var store
    @State private var identity = UUID().uuidString

    @ViewBuilder func body(content: Content) -> some View {
        if let store {
            ValidatedFormField(content: content, context: context, valueKey: valueKey,
                               identity: identity, store: store)
        } else {
            content
        }
    }
}

private struct ValidatedFormField<Content: View>: View {
    let content: Content
    let context: OpenUIComponentContext
    let valueKey: String
    let identity: String
    @ObservedObject var store: IntelligentUIFormValidationStore
    @Environment(\.openIntelligentUITheme) private var theme

    private var currentValue: Value {
        context.binding(valueKey)?.wrappedValue ?? context.value(valueKey) ?? .null
    }
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacingUnit) {
            content
            if let message = store.errors[identity] {
                Text(message).font(theme.captionFont).foregroundStyle(theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .onAppear(perform: register)
        .onChange(of: currentValue) { _ in store.refresh(identity) }
        .onChange(of: context.value("rules")) { _ in register() }
        .onChange(of: context.presentationSourceRevision) { _ in register() }
        .onDisappear { store.unregister(identity) }
    }
    private func register() {
        store.register(identity) { [context, valueKey] in
            IntelligentUIRules.message(context: context, valueKey: valueKey)
        }
    }
}
