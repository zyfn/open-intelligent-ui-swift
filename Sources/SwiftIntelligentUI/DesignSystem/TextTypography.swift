import SwiftUI

/// A single role decision shared by SwiftUI Text and the TextKit bridge.
/// Container context supplies defaults only; a supplied size always wins.
struct TextTypography {
    let role: IntelligentUITextFontRole
    let font: Font
    let weight: Font.Weight
    let weightName: String
    let lineSpacing: CGFloat
    let nativeFont: IntelligentUINativeFont?

    init(size: String?, weight: String?, editorial: EditorialContext,
         theme: IntelligentUITheme, colorScheme: ColorScheme) {
        switch size {
        case "xs": role = .caption
        case "sm": role = .secondary
        case "lg": role = .bodyLarge
        case "md": role = .body
        default: role = editorial.compactContent ? .secondary : .body
        }
        switch role {
        case .caption: font = theme.captionFont
        case .secondary: font = theme.secondaryFont
        case .body: font = theme.bodyFont
        case .bodyLarge: font = theme.bodyLargeFont
        }
        if weight == "semibold" { self.weight = .semibold; weightName = "semibold" }
        else if weight == "medium" { self.weight = .medium; weightName = "medium" }
        else if weight == nil && role == .body {
            self.weight = theme.defaultBodyWeight(for: colorScheme)
            weightName = self.weight == .medium ? "medium" : "normal"
        } else { self.weight = .regular; weightName = "normal" }
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
    static func font(size: String?, editorial: EditorialContext, theme: IntelligentUITheme) -> Font {
        if editorial.openingCardTitle && size == nil { return theme.secondaryFont.weight(theme.headingWeight) }
        switch size {
        case "sm": return theme.secondaryFont.weight(theme.headingWeight)
        case "lg": return theme.sectionTitleFont
        case "xl": return theme.pageTitleFont
        case "2xl": return theme.largeTitleFont
        case "3xl": return theme.displayFont
        default: return theme.titleFont
        }
    }
}
