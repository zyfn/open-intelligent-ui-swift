import SwiftUI
import OpenUILang
import OpenUICore

/// Shared card navigation action; public arbitrary actions remain Button.
struct PrimaryLinkButton: View {
    let context: OpenUIComponentContext
    let label: String
    let url: String
    var compact = false
    var symbol: String? = nil
    @Environment(\.intelligentUITheme) private var theme
    var body: some View {
        IntelligentUIActionSurface(context: context, action: OpenUIActions.openURL(url),
            showsProgress: true, progressTint: theme.actionForeground) {
            HStack(spacing: theme.spacingUnit) {
                Text(label)
                if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
            }.font(compact ? theme.compactActionFont : theme.labelFont).foregroundStyle(theme.actionForeground)
        }
        .buttonStyle(UpstreamButtonStyle(tint: theme.actionAccent, size: compact ? "sm" : "md"))
        .controlSize(compact ? .small : .regular).tint(theme.actionAccent)
        .frame(minHeight: theme.minimumControlHeight).contentShape(Rectangle()).accessibilityLabel(label)
    }
}

enum IconButtonComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "IconButton", description: "Native icon button with accessible label. variant defaults to outline. Missing actions are disabled.", params: [
            OpenUIParameter.string("icon", values: IconCatalog.names), OpenUIParameter.action(),
            OpenUIParameter.string("label", required: false), OpenUIParameter.string("variant", required: false, values: ["outline", "ghost", "solid"])
        ]) { IconButtonView(context: $0) }
    }
}
private struct IconButtonView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.locale) private var locale
    private var foreground: Color {
        context.string("variant") == "solid" ? theme.actionForeground : theme.actionAccent
    }
    @ViewBuilder var body: some View {
        surface.buttonStyle(IconButtonStyle(variant: context.string("variant") ?? "outline"))
            .disabled(context.action() == nil).tint(theme.actionAccent)
    }
    private var surface: some View {
        IntelligentUIActionSurface(context: context, action: context.action() ?? ActionPlan(),
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
    @Environment(\.intelligentUIActionAppearance) private var appearance
    @Environment(\.isFocused) private var focused
    @Environment(\.intelligentUITheme) private var theme

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
            .background(configuration.isPressed ? theme.actionAccent.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 10_000))
            .overlay(RoundedRectangle(cornerRadius: 10_000)
                .strokeBorder(focused ? theme.actionAccent : .clear, lineWidth: 2))
            .opacity(enabled || appearance == .pending || appearance == .performing ? 1 : 0.55)
    }
}

enum PressableComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Pressable", description: "One clickable presentation surface. Multiple children form one vertical group with shared padding, background, border and hit region. Do not nest interactive controls. Defaults: selected false, padding 3 theme units, clear background, theme radius. Missing actions are disabled.", params: [
            OpenUIParameter.slot("children", required: true), OpenUIParameter.action(), OpenUIParameter.flag("selected"),
            Parameter.number("padding", minimum: 0, maximum: 24), OpenUIParameter.string("background", required: false, values: Parameter.colors), Parameter.radius()
        ]) { PressableView(context: $0) }
    }
}
private struct PressableView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.locale) private var locale
    private var selected: Bool { context.flag("selected") == true }
    private var hasSelection: Bool { context.flag("selected") != nil }
    private var accessibilitySummary: String {
        let summary = context.children().map { PresentationText.summary($0.value, locale: locale) }.filter { !$0.isEmpty }.joined(separator: "，")
        return summary.isEmpty ? SDKStrings.text("controls.action.fallback", locale: locale) : summary
    }
    var body: some View {
        IntelligentUIActionSurface(context: context, action: context.action() ?? ActionPlan(), showsProgress: true) {
            VStack(alignment: .leading, spacing: theme.innerSpacing) { context.slot() }
                .intelligentUIPresentationOnly()
                .padding(.trailing, hasSelection ? 28 : 0)
                .padding(CGFloat(min(24, max(0, context.number("padding") ?? 3))) * theme.spacingUnit)
                .frame(minHeight: theme.minimumControlHeight, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: theme.radius(named: context.string("radius"), points: context.number("radius"))))
                .background(context.string("background").map { theme.backgroundColor($0) } ?? .clear,
                            in: RoundedRectangle(cornerRadius: theme.radius(named: context.string("radius"), points: context.number("radius"))))
                .overlay(RoundedRectangle(cornerRadius: theme.radius(named: context.string("radius"), points: context.number("radius")))
                    .fill(selected ? theme.actionAccent.opacity(0.06) : .clear))
                .overlay(RoundedRectangle(cornerRadius: theme.radius(named: context.string("radius"), points: context.number("radius")))
                    .strokeBorder(selected ? theme.actionAccent.opacity(0.35) : .clear))
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.actionAccent).padding(8).accessibilityHidden(true)
                    }
                }
        }.buttonStyle(QuietControlStyle(cornerRadius: theme.radius(named: context.string("radius"), points: context.number("radius"))))
            .disabled(context.action() == nil)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
