import SwiftUI
import OpenUICore
import OpenUILang

enum ButtonComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Button", description: "Action button. Defaults: variant solid, color primary, size md, disabled false, block false. icon accepts the enumerated Lucide-name subset mapped to SF Symbols. Uses native platform button styles and platform-sized targets. Missing or incomplete actions are disabled.", params: [
            OpenUIParameter.string("label"), OpenUIParameter.action(),
            OpenUIParameter.string("variant", required: false, values: ["solid", "outline", "soft", "ghost"]),
            OpenUIParameter.string("color", required: false, values: ["primary", "danger", "success"]),
            OpenUIParameter.string("size", required: false, values: ["sm", "md", "lg"]),
            OpenUIParameter.string("icon", required: false, values: IconCatalog.names),
            OpenUIParameter.flag("disabled"), OpenUIParameter.flag("block")
        ]) { ActionButtonView(context: $0) }
    }
}

private struct ActionButtonView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    private var tint: Color {
        switch context.string("color") {
        case "danger": return theme.danger
        case "success": return theme.success
        default: return theme.actionAccent
        }
    }
    private var foreground: Color {
        guard (context.string("variant") ?? "solid") == "solid" else { return tint }
        return context.string("color") == nil || context.string("color") == "primary"
            ? theme.actionForeground : theme.onAccent
    }
    @ViewBuilder var body: some View {
        let variant = context.string("variant") ?? "solid"
        surface.buttonStyle(UpstreamButtonStyle(variant: variant, tint: tint, size: context.string("size") ?? "md"))
        .font(context.string("size") == "sm" ? theme.compactActionFont : theme.labelFont)
        .tint(tint)
        .controlSize(context.string("size") == "sm" ? .small : context.string("size") == "lg" ? .large : .regular)
        .frame(minHeight: theme.minimumControlHeight)
        .contentShape(Rectangle())
        .disabled(context.flag("disabled") == true || context.action() == nil)
    }
    private var surface: some View {
        IntelligentUIActionSurface(context: context, action: context.action() ?? ActionPlan(),
            showsProgress: true, progressTint: foreground) {
            HStack(spacing: theme.iconSpacing) {
                if let symbol = IconCatalog.symbol(context.string("icon")) { Image(systemName: symbol).accessibilityHidden(true) }
                Text(context.string("label") ?? "").fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: context.flag("block") == true ? .infinity : nil)
        }
    }
}

struct UpstreamButtonStyle: ButtonStyle {
    var variant = "solid"
    var tint: Color = .primary
    var size = "md"
    @Environment(\.isEnabled) private var enabled
    @Environment(\.intelligentUIActionAppearance) private var appearance
    @Environment(\.isFocused) private var focused
    @Environment(\.intelligentUITheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, size == "sm" ? 12 : size == "lg" ? 20 : 16)
            .padding(.vertical, size == "sm" ? 6 : size == "lg" ? 10 : 8)
            .frame(minHeight: max(theme.minimumControlHeight, size == "lg" ? 44 : 0))
            .contentShape(Capsule())
            .background(variant == "solid" ? tint : variant == "soft" ? theme.surface : variant == "outline" ? theme.canvas : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(variant == "outline" ? theme.fieldBorder : .clear))
            .overlay(Capsule().fill(theme.primaryText.opacity(configuration.isPressed ? 0.08 : 0)))
            .overlay(Capsule().strokeBorder(focused ? tint : .clear, lineWidth: 2))
            .opacity(enabled || appearance == .pending || appearance == .performing ? 1 : 0.5)
    }
}

/// Shared feedback for controls whose label already owns its layout and surface.
/// Native Button continues to own activation, focus and accessibility semantics.
struct QuietControlStyle: ButtonStyle {
    var cornerRadius: CGFloat? = nil
    @Environment(\.isEnabled) private var enabled
    @Environment(\.intelligentUIActionAppearance) private var appearance
    @Environment(\.isFocused) private var focused
    @Environment(\.intelligentUITheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? theme.actionAccent.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: cornerRadius ?? theme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius ?? theme.controlRadius)
                .strokeBorder(focused ? theme.actionAccent : .clear, lineWidth: 2))
            .opacity(enabled || appearance == .pending || appearance == .performing ? 1 : 0.55)
    }
}
