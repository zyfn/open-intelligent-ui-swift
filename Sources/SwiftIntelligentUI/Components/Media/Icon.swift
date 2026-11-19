import SwiftUI
import SwiftLang

enum IconCatalog {
    // Known Lucide identifiers map to native SF Symbols. Model-authored names
    // are not narrowed to this list: unsupported names get an explicit fallback.
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
        case "clock": return "clock"
        case "calendar": return "calendar"
        case "arrow-left": return "arrow.left"
        case "arrow-right": return "arrow.right"
        case "arrow-up": return "arrow.up"
        case "arrow-down": return "arrow.down"
        case "chevron-left": return "chevron.left"
        case "chevron-right": return "chevron.right"
        case "chevron-up": return "chevron.up"
        case "chevron-down": return "chevron.down"
        case "check-circle", "circle-check": return "checkmark.circle"
        case "check-circle-2": return "checkmark.circle.fill"
        case "alert-circle": return "exclamationmark.circle"
        case "alert-triangle": return "exclamationmark.triangle"
        case "help-circle": return "questionmark.circle"
        case "mail": return "envelope"
        case "phone": return "phone"
        case "home", "house": return "house"
        case "menu": return "line.3.horizontal"
        case "globe": return "globe"
        case "download": return "square.and.arrow.down"
        case "upload": return "square.and.arrow.up"
        case "trash", "trash-2": return "trash"
        case "settings": return "gearshape"
        case "user", "circle-user": return "person.crop.circle"
        case "users": return "person.2"
        case "coffee": return "cup.and.saucer"
        case "sun": return "sun.max"
        case "moon": return "moon"
        case "cloud": return "cloud"
        case "cloud-sun": return "cloud.sun"
        case "image", "images": return "photo"
        case "file-text": return "doc.text"
        case "file": return "doc"
        case "share-2": return "square.and.arrow.up"
        case "copy": return "doc.on.doc"
        case "edit", "pencil": return "pencil"
        case "play": return "play"
        case "pause": return "pause"
        case "refresh-cw", "rotate-cw": return "arrow.clockwise"
        case "filter": return "line.3.horizontal.decrease"
        case "list": return "list.bullet"
        case "grid-2x2": return "square.grid.2x2"
        case "layers": return "square.3.layers.3d"
        case "link": return "link"
        case "lock": return "lock"
        case "shield-check": return "checkmark.shield"
        case "package": return "shippingbox"
        case "truck": return "truck.box"
        case "train": return "tram"
        case "plane": return "airplane"
        case "map": return "map"
        case "book-open": return "book"
        case "message-circle": return "bubble.left"
        case "message-square": return "bubble.left.and.bubble.right"
        case "sparkles": return "sparkles"
        default: return name?.isEmpty == false ? "questionmark.circle" : nil
        }
    }
}

enum IconComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Icon", description: "Decorative native icon. Names follow the upstream free-form Lucide identifier contract; known names map to SF Symbols and unknown nonempty names use an explicit accessible native fallback. Size md and ink are defaults; meaningful symbols need visible text.", params: [
            OpenUIParameter.string("name"),
            OpenUIParameter.string("size", required: false, values: ["sm", "md", "lg"]),
            OpenUIParameter.string("color", required: false, values: Parameter.colors)
        ]) { IconView(context: $0) }
    }
}

private struct IconView: View {
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    var body: some View {
        if let symbol = IconCatalog.symbol(context.string("name")) {
            Image(systemName: symbol)
                .font(context.string("size") == "sm" ? .caption : context.string("size") == "lg" ? .title2 : theme.bodyFont)
                .foregroundStyle(theme.textColor(context.string("color")))
                .accessibilityHidden(true)
        }
    }
}
