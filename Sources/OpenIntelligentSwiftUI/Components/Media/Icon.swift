import SwiftUI
import OpenUICore

enum IconCatalog {
    // Explicit subset of upstream Lucide names mapped to native SF Symbols.
    static let names = ["check", "plus", "minus", "x", "arrow-up-right", "external-link", "shopping-cart", "heart", "search", "info", "map-pin", "landmark", "building-2", "camera", "headphones", "star", "navigation"]
    static func symbol(_ name: String?) -> String? {
        switch name {
        case "check": return "checkmark"
        case "plus": return "plus"
        case "minus": return "minus"
        case "x": return "xmark"
        case "arrow-up-right": return "arrow.up.right"
        case "external-link": return "arrow.up.right.square"
        case "shopping-cart": return "cart"
        case "heart": return "heart"
        case "search": return "magnifyingglass"
        case "info": return "info.circle"
        case "map-pin": return "mappin"
        case "landmark": return "building.columns"
        case "building-2": return "building.2"
        case "camera": return "camera"
        case "headphones": return "headphones"
        case "star": return "star.fill"
        case "navigation": return "location"
        default: return nil
        }
    }
}

enum IconComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Icon", description: "Decorative native icon. Supports the enumerated Lucide-name subset mapped to SF Symbols. size defaults to md and color to ink; accompany with visible text for meaning.", params: [
            OpenUIParameter.string("name", values: IconCatalog.names),
            OpenUIParameter.string("size", required: false, values: ["sm", "md", "lg"]),
            OpenUIParameter.string("color", required: false, values: Parameter.colors)
        ]) { IconView(context: $0) }
    }
}

private struct IconView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    var body: some View {
        if let symbol = IconCatalog.symbol(context.string("name")) {
            Image(systemName: symbol)
                .font(context.string("size") == "sm" ? .caption : context.string("size") == "lg" ? .title2 : theme.bodyFont)
                .foregroundStyle(theme.textColor(context.string("color")))
                .accessibilityHidden(true)
        }
    }
}
