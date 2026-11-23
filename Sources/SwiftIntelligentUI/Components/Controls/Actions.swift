import SwiftUI
import SwiftLang

enum IconButtonComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "IconButton", description: "Native icon button with accessible label. variant defaults to outline. Missing actions are disabled.", params: [
            OpenUIParameter.string("icon"), OpenUIParameter.action(),
            OpenUIParameter.string("label", required: false), OpenUIParameter.string("variant", required: false, values: ["outline", "ghost", "solid"])
        ]) { IconButtonView(context: $0) }
    }
}
private struct IconButtonView: View {
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.locale) private var locale
    private var tint: Color { theme.buttonAccent(nil, variant: context.string("variant") ?? "outline") }
    private var foreground: Color {
        context.string("variant") == "solid" ? theme.actionForeground : tint
    }
    @ViewBuilder var body: some View {
        surface.buttonStyle(IconButtonStyle(variant: context.string("variant") ?? "outline"))
            .disabled(context.action() == nil).tint(tint)
    }
    private var surface: some View {
        OpenIntelligentUIActionSurface(context: context, action: context.action() ?? ActionPlan(),
            showsProgress: true, progressTint: foreground) {
            Image(systemName: IconCatalog.symbol(context.string("icon")) ?? "questionmark")
                .foregroundStyle(foreground)
                .frame(width: 34, height: 34)
                .frame(minWidth: theme.minimumControlHeight, minHeight: theme.minimumControlHeight)
                .contentShape(Rectangle())
                .accessibilityLabel(context.string("label") ?? context.string("icon") ?? SDKStrings.text("controls.action.fallback", locale: locale))
        }
    }
}

/// Keep the icon's surface visible when progress replaces its label, while
/// applying the same pressed, focus and disabled feedback to the whole control.
private struct IconButtonStyle: ButtonStyle {
    let variant: String
    @Environment(\.isEnabled) private var enabled
    @Environment(\.openIntelligentUIActionAppearance) private var appearance
    @Environment(\.isFocused) private var focused
    @Environment(\.openIntelligentUITheme) private var theme
    private var tint: Color { theme.buttonAccent(nil, variant: variant) }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle().fill(variant == "solid" ? theme.actionAccent : variant == "ghost" ? .clear : theme.canvas)
                    .frame(width: 34, height: 34)
            }
            .overlay {
                Circle().strokeBorder(variant == "ghost" ? .clear : theme.fieldBorder)
                    .frame(width: 34, height: 34).allowsHitTesting(false)
            }
            .background(configuration.isPressed ? tint.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 10_000))
            .overlay(RoundedRectangle(cornerRadius: 10_000)
                .strokeBorder(focused ? tint : .clear, lineWidth: 2))
            .opacity(enabled || appearance == .pending || appearance == .performing ? 1 : 0.55)
    }
}

enum PressableComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Pressable", description: "One clickable presentation surface. Multiple children form one vertical group with shared padding, background, border and hit region. Do not nest interactive controls. Defaults: selected false, padding 3 theme units, clear background, theme radius. Missing actions are disabled.", params: [
            OpenUIParameter.slot("children", required: true), OpenUIParameter.action(), OpenUIParameter.flag("selected"),
            Parameter.number("padding"), Parameter.color("background"), Parameter.radius()
        ]) { PressableView(context: $0) }
    }
}
private struct PressableView: View {
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.locale) private var locale
    private var contentTheme: OpenIntelligentUITheme { theme.onBackground(context.string("background")) }
    private var selected: Bool { context.flag("selected") == true }
    private var hasSelection: Bool { context.flag("selected") != nil }
    private var accessibilitySummary: String {
        let summary = context.children().map { PresentationText.summary($0.value, locale: locale) }.filter { !$0.isEmpty }.joined(separator: "，")
        return summary.isEmpty ? SDKStrings.text("controls.action.fallback", locale: locale) : summary
    }
    var body: some View {
        OpenIntelligentUIActionSurface(context: context, action: context.action() ?? ActionPlan(), showsProgress: true) {
            VStack(alignment: .leading, spacing: theme.innerSpacing) { context.slot() }
                .openIntelligentUIPresentationOnly()
                .padding(.trailing, hasSelection ? 28 : 0)
                .padding(theme.spacing(context.number("padding"), fallback: 3))
                .frame(minHeight: theme.minimumControlHeight, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: theme.radius(named: context.string("radius"), points: context.number("radius"))))
                .background(context.string("background").map { theme.backgroundColor($0) } ?? .clear,
                            in: RoundedRectangle(cornerRadius: theme.radius(named: context.string("radius"), points: context.number("radius"))))
                .overlay(RoundedRectangle(cornerRadius: theme.radius(named: context.string("radius"), points: context.number("radius")))
                    .fill(selected ? contentTheme.actionAccent.opacity(0.06) : .clear))
                .overlay(RoundedRectangle(cornerRadius: theme.radius(named: context.string("radius"), points: context.number("radius")))
                    .strokeBorder(selected ? contentTheme.actionAccent.opacity(0.35) : .clear))
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(contentTheme.actionAccent).padding(8).accessibilityHidden(true)
                    }
                }
        }.buttonStyle(QuietControlStyle(cornerRadius: theme.radius(named: context.string("radius"), points: context.number("radius"))))
            .disabled(context.action() == nil)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .environment(\.openIntelligentUITheme, contentTheme)
            .foregroundStyle(contentTheme.primaryText)
    }
}
