import SwiftUI
import OpenUILang
import OpenUISwiftUI

enum CheckboxComponent {
    @MainActor static func toggle(_ context: OpenUIComponentContext) {
        guard context.canInteract, let binding = context.binding("checked") else { return }
        binding.wrappedValue = .boolean(binding.wrappedValue != .boolean(true))
    }
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Checkbox", description: "A compact leading checkmark square with a text label, not an iOS settings switch. Bind checked to a $variable; literal values are read-only. The full row is tappable with an accessible checked state. lineThrough defaults to false and strikes the label only when checked. For tasks use one clear task label rather than repeating the same task in a title, description and Checkbox.", params: [
            Parameter.boundBoolean("checked"), OpenUIParameter.string("label"),
            OpenUIParameter.flag("lineThrough")
        ]) { CheckboxView(context: $0) }
    }
}

private struct CheckboxView: View {
    let context: OpenUIComponentContext
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var indicatorSize: CGFloat = 20
    private var checked: Bool {
        if case .boolean(let value) = context.binding("checked")?.wrappedValue { return value }
        return context.flag("checked") ?? false
    }
    var body: some View {
        Button {
            CheckboxComponent.toggle(context)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: theme.innerSpacing) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: indicatorSize, weight: .regular))
                    .foregroundStyle(checked ? theme.actionAccent : theme.secondaryText)
                    .frame(width: indicatorSize, height: indicatorSize)
                    .accessibilityHidden(true)
                Text(context.string("label") ?? "")
                    .strikethrough(checked && context.flag("lineThrough") == true)
                    .font(theme.bodyFont)
                    .foregroundStyle(checked && context.flag("lineThrough") == true ? theme.secondaryText : theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: theme.minimumControlHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietControlStyle())
        .accessibilityLabel(context.string("label") ?? "")
        .accessibilityValue(checked ? SDKStrings.text("controls.checkbox.checked", locale: locale) : SDKStrings.text("controls.checkbox.unchecked", locale: locale))
        .accessibilityAddTraits(checked ? [.isSelected] : [])
        .disabled(!context.canInteract || context.binding("checked") == nil)
    }
}
