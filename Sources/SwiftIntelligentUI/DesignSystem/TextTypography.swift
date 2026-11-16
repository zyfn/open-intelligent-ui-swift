import SwiftUI

/// A single role decision shared by SwiftUI Text and the TextKit bridge.
/// Content roles are independent of layout containers and color scheme.
struct TextTypography {
    let role: OpenIntelligentUITextFontRole
    let font: Font
    let weight: Font.Weight
    let weightName: String
    let lineSpacing: CGFloat
    let nativeFont: OpenIntelligentUINativeFont?

    init(size: String?, weight: String?, theme: OpenIntelligentUITheme) {
        switch size {
        case "xs": role = .caption
        case "sm": role = .secondary
        case "lg": role = .bodyLarge
        default: role = .body
        }
        switch role {
        case .caption: font = theme.captionFont
        case .secondary: font = theme.secondaryFont
        case .body: font = theme.bodyFont
        case .bodyLarge: font = theme.bodyLargeFont
        }
        if weight == "semibold" { self.weight = .semibold; weightName = "semibold" }
        else if weight == "medium" { self.weight = .medium; weightName = "medium" }
        else { self.weight = .regular; weightName = "normal" }
        lineSpacing = (role == .caption || role == .secondary) ? theme.bodyLineSpacing / 2 : theme.bodyLineSpacing
        nativeFont = theme.nativeTextFonts[role]
    }

    var sizeName: String {
        switch role {
        case .caption: return "xs"
        case .secondary: return "sm"
        case .body: return "md"
        case .bodyLarge: return "lg"
        }
    }
}

enum TitleTypography {
    static func font(size: String?, theme: OpenIntelligentUITheme) -> Font {
        switch size {
        case "sm": return theme.secondaryFont.weight(theme.headingWeight)
        case "lg": return theme.sectionTitleFont
        case "xl": return theme.pageTitleFont
        case "2xl": return theme.largeTitleFont
        case "3xl": return theme.displayFont
        default: return theme.titleFont
        }
    }

    static func size(forMarkdownLevel level: Int) -> String {
        switch level {
        case 1: return "xl"
        case 2: return "lg"
        case 3, 4: return "md"
        default: return "sm"
        }
    }
}
