import SwiftUI
import OpenUILang
import OpenUISwiftUI

struct ChoiceOption: Identifiable, Equatable {
    let id: String
    let label: String
    let detail: String?

    static func decode(_ value: Value?) -> [Self] {
        guard case .array(let values) = value else { return [] }
        var seen = Set<String>()
        let flattened = values.flatMap { value -> [Value] in
            if case .array(let array) = value { return array.values }; return [value]
        }
        return flattened.compactMap { value in
            let option: Self
            if case .string(let text) = value {
                option = Self(id: text.displayString, label: text.displayString, detail: nil)
            } else if case .object(let fields) = value,
                      case .string(let id) = fields.fields.last(where: { $0.key == "value" })?.value,
                      case .string(let label) = fields.fields.last(where: { $0.key == "label" })?.value {
                let detail: String? = {
                    if case .string(let text) = fields.fields.last(where: { $0.key == "description" })?.value { return text.displayString }
                    return nil
                }()
                option = Self(id: id.displayString, label: label.displayString, detail: detail)
            } else { return nil }
            return seen.insert(option.id).inserted ? option : nil
        }
    }

    static func parameter(descriptions: Bool = false) -> ParamDef {
        var fields: [JSONField] = [
            .init(key: "value", value: .object([.init(key: "type", value: .string("string"))])),
            .init(key: "label", value: .object([.init(key: "type", value: .string("string"))]))
        ]
        if descriptions { fields.append(.init(key: "description", value: .object([.init(key: "type", value: .string("string"))]))) }
        return ParamDef(name: "options", required: true, schema: .object([
            .init(key: "type", value: .string("array")), .init(key: "items", value: .object([
                .init(key: "anyOf", value: .array([
                    .object([.init(key: "type", value: .string("string"))]),
                    .object([.init(key: "type", value: .string("object")), .init(key: "properties", value: .object(fields)),
                             .init(key: "required", value: .array([.string("value"), .string("label")])), .init(key: "additionalProperties", value: .boolean(false))])
                ]))
            ]))
        ]))
    }
}

enum SelectComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Select", description: "Menu selection bound to a string. Options are strings or value/label objects. Unknown selection shows placeholder; no implicit selection. Duplicate values use the first option. Empty lists and literal values are read-only.", params: [
            OpenUIParameter.selection("value"), ChoiceOption.parameter(),
            OpenUIParameter.string("label", required: false), OpenUIParameter.string("placeholder", required: false),
            OpenUIParameter.string("error", required: false)
        ]) { SelectView(context: $0) }
    }
}

private struct SelectView: View {
    let context: OpenUIComponentContext
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.intelligentUITheme) private var theme
    private var options: [ChoiceOption] { ChoiceOption.decode(context.value("options")) }
    private var selection: Binding<String?> {
        Binding(get: {
            let value = InputEditing.text(context.binding("value")?.wrappedValue ?? context.value("value") ?? .null)
            return options.contains { $0.id == value } ? value : nil
        }, set: { value in
            if let value, options.contains(where: { $0.id == value }) {
                context.binding("value")?.wrappedValue = .string(OpenUIString(value))
            }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: theme.innerSpacing) {
        if let label = context.string("label"), !label.isEmpty { Text(label).font(theme.labelFont) }
        Menu {
            Picker(context.string("label") ?? "选择", selection: selection) {
                Text(context.string("placeholder") ?? "请选择").tag(Optional<String>.none).disabled(true)
                ForEach(options) { Text($0.label).tag(Optional($0.id)) }
            }
        } label: {
            HStack {
                Text(options.first { $0.id == selection.wrappedValue }?.label ?? context.string("placeholder") ?? "请选择")
                Spacer(minLength: theme.innerSpacing)
                Image(systemName: "chevron.down").font(theme.captionFont).accessibilityHidden(true)
            }.foregroundStyle(theme.primaryText).modifier(FieldSurface(invalid: !(context.string("error") ?? "").isEmpty))
        }
        .menuStyle(.borderlessButton).font(theme.bodyFont).tint(theme.actionAccent)
        .disabled(!context.canInteract || context.binding("value") == nil || options.isEmpty)
        .accessibilityHint(context.string("error") ?? "")
        FieldError(message: context.string("error"))
        }
    }
}

enum SegmentedControlComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "SegmentedControl", description: "Short string choices; wraps on narrow widths. block defaults to false. Options accept strings or value/label objects; duplicate values use the first. Literal values are read-only.", params: [
            OpenUIParameter.selection("value"), ChoiceOption.parameter(), OpenUIParameter.flag("block")
        ]) { NativeSegmentedView(context: $0) }
    }
}

private struct NativeSegmentedView: View {
    let context: OpenUIComponentContext
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.dynamicTypeSize) private var typeSize
    private var options: [ChoiceOption] { ChoiceOption.decode(context.value("options")) }
    private var selection: Binding<String?> {
        Binding(get: {
            let value = InputEditing.text(context.binding("value")?.wrappedValue ?? context.value("value") ?? .null)
            return options.contains { $0.id == value } ? value : nil
        }, set: { if let value = $0 { context.binding("value")?.wrappedValue = .string(OpenUIString(value)) } })
    }
    var body: some View {
        if !typeSize.isAccessibilitySize && (2...4).contains(options.count) {
            ViewThatFits(in: .horizontal) {
                Picker("选项", selection: selection) {
                    ForEach(options) { Text($0.label).tag(Optional($0.id)) }
                }.pickerStyle(.segmented).labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: context.flag("block") == true ? .infinity : nil, alignment: .leading)
                    .disabled(!context.canInteract || context.binding("value") == nil)
                ChoiceGroupView(context: context, segmented: true)
            }
        } else { ChoiceGroupView(context: context, segmented: true) }
    }
}

enum RadioGroupComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "RadioGroup", description: "Single selection bound to a string. variant defaults to list; pills wrap, cards show descriptions. Duplicate values use the first option. Literal values are read-only.", params: [
            OpenUIParameter.selection("value"), ChoiceOption.parameter(descriptions: true),
            OpenUIParameter.string("label", required: false),
            OpenUIParameter.string("variant", required: false, values: ["list", "pills", "cards"])
        ]) { ChoiceGroupView(context: $0, segmented: false) }
    }
}

private struct ChoiceGroupView: View {
    let context: OpenUIComponentContext
    let segmented: Bool
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.layoutDirection) private var direction
    private var options: [ChoiceOption] { ChoiceOption.decode(context.value("options")) }
    private var selected: String { InputEditing.text(context.binding("value")?.wrappedValue ?? context.value("value") ?? .null) }
    private var pills: Bool { segmented || context.string("variant") == "pills" }
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacingUnit * 2) {
            if !segmented, let label = context.string("label"), !label.isEmpty { Text(label).font(theme.labelFont) }
            let layout = pills
                ? AnyLayout(WrappingRowLayout(gap: theme.spacingUnit * 2, alignment: "center", justification: "start", wraps: true, rightToLeft: direction == .rightToLeft, fillsWidth: !segmented || context.flag("block") == true))
                : context.string("variant") == "cards"
                    ? AnyLayout(EqualGridLayout(columns: 12, minimumWidth: 200, gap: theme.innerSpacing, rightToLeft: direction == .rightToLeft))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            layout {
                ForEach(options) { option in
                    Button {
                        context.binding("value")?.wrappedValue = .string(OpenUIString(option.id))
                    } label: {
                        HStack(alignment: .top, spacing: theme.spacingUnit * 2) {
                            if !pills { Image(systemName: selected == option.id ? "largecircle.fill.circle" : "circle").accessibilityHidden(true) }
                            VStack(alignment: .leading, spacing: theme.spacingUnit) {
                                Text(option.label).fontWeight(selected == option.id ? .medium : .regular).fixedSize(horizontal: false, vertical: true)
                                if let detail = option.detail { Text(detail).font(theme.captionFont).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true) }
                            }
                        }
                        .font(theme.bodyFont).padding(theme.spacingUnit * 2)
                        .frame(maxWidth: pills ? nil : .infinity, minHeight: theme.minimumControlHeight, alignment: .leading)
                        .contentShape(Rectangle())
                        .foregroundStyle(pills && !segmented && selected == option.id ? theme.actionForeground : theme.primaryText)
                        .background(pills && selected == option.id ? (!segmented ? theme.primaryText : theme.surface) : .clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(pills && !segmented ? (selected == option.id ? theme.primaryText : theme.fieldBorder) : .clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == option.id ? [.isSelected] : [])
                    .accessibilityValue(selected == option.id ? "已选择" : "未选择")
                }
            }
        }
        .frame(maxWidth: !segmented || context.flag("block") == true ? .infinity : nil, alignment: .leading)
        .disabled(!context.canInteract || context.binding("value") == nil)
    }
}
