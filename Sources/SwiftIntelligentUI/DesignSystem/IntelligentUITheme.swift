import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Semantic styles scoped to an individual render subtree.
public struct IntelligentUITheme {
    public var primaryText: Color = .primary
    public var secondaryText: Color = .secondary
    public var canvas: Color = NativeColors.canvas
    public var surface: Color = NativeColors.surface
    public var separator: Color = NativeColors.separator
    public var accent: Color = .accentColor
    public var actionAccent: Color = .primary
    public var actionForeground: Color = NativeColors.canvas
    public var onAccent: Color = .white
    public var success: Color = .green
    public var danger: Color = .red
    public var info: Color = .blue
    public var warning: Color = .orange
    public var chartColors: [Color] = [.blue, .teal, .orange, .purple, .pink, .green, .indigo, .brown]
    public var bodyFont: Font = .body
    public var secondaryFont: Font = .subheadline
    public var captionFont: Font = .caption
    public var labelFont: Font = .subheadline.weight(.medium)
    public var bodyLargeFont: Font = .title3
    public var sectionTitleFont: Font = .title3.weight(.medium)
    public var pageTitleFont: Font = .title2.weight(.medium)
    public var largeTitleFont: Font = .title.weight(.medium)
    public var displayFont: Font = .largeTitle.weight(.semibold)
    public var headingWeight: Font.Weight = .medium
    public var emphasisWeight: Font.Weight = .medium
    public var codeFont: Font = .system(.body, design: .monospaced)
    public var markdownHeadingScales: [Double] = [22.0 / 17.0, 20.0 / 17.0, 1]
    public var codeKeyword: Color = .purple
    public var codeLiteral: Color = .red
    public var codeNumber: Color = .blue
    public var titleFont: Font = .headline.weight(.medium)
    public var priceFont: Font = .title3.weight(.semibold)
    public var coverImageAspectRatio: CGFloat = 16.0 / 9.0
    public var compactActionFont: Font = .footnote
    public var spacingUnit: CGFloat = 4
    public var sectionSpacing: CGFloat = 20
    public var groupSpacing: CGFloat = 16
    public var innerSpacing: CGFloat = 8
    public var iconSpacing: CGFloat = 6
    public var controlHorizontalPadding: CGFloat = 12
    public var controlVerticalPadding: CGFloat = 6
    public var fieldHorizontalPadding: CGFloat = 12
    public var fieldVerticalPadding: CGFloat = NativeColors.minimumControlHeight == 44 ? 12 : 8
    public var fieldBorder: Color = .primary.opacity(0.18)
    public var fieldMultilineRadius: CGFloat = 18
    public var contentCardRadius: CGFloat = 20
    public var nestedContentCardRadius: CGFloat = 16
    public var paragraphSpacing: CGFloat = 12
    public var bodyLineSpacing: CGFloat = 4
    public var readingWidth: CGFloat = 680
    public var radiusSM: CGFloat = 6
    public var radiusMD: CGFloat = 10
    public var radiusLG: CGFloat = 14
    public var radiusXL: CGFloat = 20
    public var cornerRadius: CGFloat = 16
    public var controlRadius: CGFloat = 8
    public var minimumControlHeight: CGFloat = NativeColors.minimumControlHeight
    public init() {}

    func headingScale(_ level: Int) -> Double {
        markdownHeadingScales.indices.contains(level) ? markdownHeadingScales[level] : 1
    }

    func defaultBodyWeight(for colorScheme: ColorScheme) -> Font.Weight {
        colorScheme == .dark ? .medium : .regular
    }

    func bodyFont(for colorScheme: ColorScheme) -> Font {
        bodyFont.weight(defaultBodyWeight(for: colorScheme))
    }

    func textColor(_ token: String?) -> Color {
        if let token, let index = Int(token.dropFirst(5)), token.hasPrefix("chart"), chartColors.indices.contains(index - 1) {
            return chartColors[index - 1]
        }
        switch token {
        case "muted", "faint": return secondaryText
        case "surface": return surface
        case "info": return info
        case "warning": return warning
        case "purple": return .purple
        case "pink": return .pink
        case "success": return success
        case "danger": return danger
        default: return primaryText
        }
    }

    func backgroundColor(_ token: String) -> Color {
        if ["faint", "muted"].contains(token) { return surface }
        if ["info", "success", "warning", "danger", "purple", "pink"].contains(token) { return textColor(token).opacity(0.12) }
        return textColor(token)
    }

    func radius(named name: String?, points: Double? = nil, fallback: CGFloat? = nil) -> CGFloat {
        if let points, points.isFinite { return CGFloat(min(10_000, max(0, points))) }
        switch name {
        case "sm": return radiusSM
        case "md": return radiusMD
        case "lg": return radiusLG
        case "xl": return radiusXL
        case "full": return 10_000
        default: return fallback ?? cornerRadius
        }
    }
}

private enum NativeColors {
    #if canImport(UIKit)
    static var canvas: Color { Color(uiColor: .systemBackground) }
    static var surface: Color { Color(uiColor: .secondarySystemBackground) }
    static var separator: Color { Color(uiColor: .separator) }
    static let minimumControlHeight: CGFloat = 44
    #else
    static var canvas: Color { Color(nsColor: .windowBackgroundColor) }
    static var surface: Color { Color(nsColor: .controlBackgroundColor) }
    static var separator: Color { Color(nsColor: .separatorColor) }
    static let minimumControlHeight: CGFloat = 28
    #endif
}

extension EnvironmentValues {
    @Entry public var intelligentUITheme = IntelligentUITheme()
    @Entry var intelligentUIContentBackground: Color? = nil
    @Entry var intelligentUIScrolling = false
}

extension View {
    public func intelligentUITheme(_ theme: IntelligentUITheme) -> some View {
        environment(\.intelligentUITheme, theme)
    }
}
