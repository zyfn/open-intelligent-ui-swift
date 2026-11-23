import SwiftUI
import SwiftLang

enum ButtonComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Button", description: "Action button. Defaults: variant solid, color primary, size md, disabled false, block false. icon accepts the enumerated Lucide-name subset mapped to SF Symbols. Uses native platform button styles and platform-sized targets. Missing or incomplete actions are disabled.", params: [
            OpenUIParameter.string("label"), OpenUIParameter.action(),
            OpenUIParameter.string("variant", required: false, values: ["solid", "outline", "soft", "ghost"]),
            OpenUIParameter.string("color", required: false, values: ["primary", "danger", "success"]),
            OpenUIParameter.string("size", required: false, values: ["sm", "md", "lg"]),
            OpenUIParameter.string("icon", required: false),
            OpenUIParameter.flag("disabled"), OpenUIParameter.flag("block")
        ]) { context in
            ActionButtonView(
                context: context,
                label: context.string("label") ?? "",
                action: context.action(),
                variant: context.string("variant") ?? "solid",
                color: context.string("color"),
                size: context.string("size") ?? "md",
                icon: context.string("icon"),
                disabled: context.flag("disabled") == true,
                block: context.flag("block") == true
            )
        }
    }
}

struct ActionButtonView: View {
    let context: OpenUIComponentContext
    let label: String
    let action: ActionPlan?
    var variant = "solid"
    var color: String? = nil
    var size = "md"
    var icon: String? = nil
    var disabled = false
    var block = false

    @Environment(\.openIntelligentUITheme) private var theme

    private var tint: Color {
        theme.buttonAccent(color, variant: variant)
    }
    private var foreground: Color {
        guard variant == "solid" else { return tint }
        return color == nil || color == "primary" ? theme.actionForeground : theme.onAccent
    }

    var body: some View {
        let isSmall = size == "sm"
        let hitShape = isSmall ? AnyShape(Capsule()) : AnyShape(Rectangle())
        return surface
            .buttonStyle(UpstreamButtonStyle(variant: variant, tint: tint, size: size))
            .font(isSmall ? theme.compactActionFont : theme.labelFont)
            .tint(tint)
            .controlSize(isSmall ? .small : size == "lg" ? .large : .regular)
            .frame(minHeight: isSmall ? nil : theme.minimumControlHeight)
            .contentShape(hitShape)
            .disabled(disabled || action == nil)
    }

    private var surface: some View {
        OpenIntelligentUIActionSurface(context: context, action: action ?? ActionPlan(),
            showsProgress: true, progressTint: foreground) {
            HStack(spacing: theme.iconSpacing) {
                if let symbol = IconCatalog.symbol(icon) { Image(systemName: symbol).accessibilityHidden(true) }
                Text(label).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: block ? .infinity : nil)
        }
    }
}

struct UpstreamButtonStyle: ButtonStyle {
    var variant = "solid"
    var tint: Color = .primary
    var size = "md"
    @Environment(\.isEnabled) private var enabled
    @Environment(\.openIntelligentUIActionAppearance) private var appearance
    @Environment(\.isFocused) private var focused
    @Environment(\.openIntelligentUITheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        let isSmall = size == "sm"
        let minimumHeight = max(theme.minimumControlHeight, size == "lg" ? 44 : 0)
        let horizontalPadding = isSmall ? theme.controlHorizontalPadding : (size == "lg" ? 20 : 16)
        let verticalPadding = isSmall ? theme.controlVerticalPadding : (size == "lg" ? 10 : 8)
        return configuration.label
            .foregroundStyle(variant == "solid" ? theme.actionForeground : tint)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: isSmall ? nil : minimumHeight)
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
    @Environment(\.openIntelligentUIActionAppearance) private var appearance
    @Environment(\.isFocused) private var focused
    @Environment(\.openIntelligentUITheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? theme.actionAccent.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: cornerRadius ?? theme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius ?? theme.controlRadius)
                .strokeBorder(focused ? theme.actionAccent : .clear, lineWidth: 2))
            .opacity(enabled || appearance == .pending || appearance == .performing ? 1 : 0.55)
    }
}
