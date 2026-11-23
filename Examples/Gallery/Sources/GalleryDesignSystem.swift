import SwiftUI
import SwiftOpenUI

struct GalleryDesignSystem: Decodable {
    static let id = "DesignSystem"

    enum Theme: String, CaseIterable, Identifiable {
        case original, liquidSphere
        var id: String { rawValue }
        var title: String { self == .original ? "Muse 默认" : "Liquid Sphere" }
    }

    let revision: String
    private let base: GalleryThemeTokens
    private let liquidSphere: GalleryThemeTokens

    static func load(resourceRoot: URL) throws -> Self {
        let data = try Data(contentsOf: resourceRoot.appendingPathComponent("DesignSystem/muse.tokens.json"))
        let system = try JSONDecoder().decode(Self.self, from: data)
        for theme in Theme.allCases {
            let tokens = system.tokens(for: theme)
            guard baseRolesPresent(tokens, matching: system.base) else {
                throw GalleryFailure("Muse \(theme.title) 缺少 OpenUI 主题值。")
            }
        }
        return system
    }

    private static func baseRolesPresent(_ tokens: GalleryThemeTokens, matching base: GalleryThemeTokens) -> Bool {
        !base.colors.isEmpty && !base.typography.isEmpty && !base.spacing.isEmpty
            && base.colors.keys.allSatisfy { name in
                tokens.colorValue(name, scheme: .light)?.color != nil && tokens.colorValue(name, scheme: .dark)?.color != nil
            }
    }

    func tokens(for theme: Theme) -> GalleryThemeTokens {
        if theme == .original { return base }
        return GalleryThemeTokens(
            colors: base.colors.merging(liquidSphere.colors) { base, override in
                .init(light: override.light ?? base.light, dark: override.dark ?? base.dark)
            },
            typography: base.typography.merging(liquidSphere.typography) { _, override in override },
            spacing: base.spacing.merging(liquidSphere.spacing) { _, override in override }
        )
    }
}

struct GalleryThemeTokens: Decodable {
    struct ColorValue: Decodable {
        let hex: String
        let alpha: Double?

        var color: Color? {
            guard hex.count == 7, hex.hasPrefix("#"), let rgb = UInt32(hex.dropFirst(), radix: 16) else { return nil }
            return Color(.sRGB, red: Double(rgb >> 16) / 255, green: Double((rgb >> 8) & 255) / 255,
                         blue: Double(rgb & 255) / 255, opacity: alpha ?? 1)
        }
    }

    struct Palette: Decodable {
        let light: ColorValue?
        let dark: ColorValue?
    }

    struct Typography: Decodable {
        let size: CGFloat
        let weight: String
        let lineSpacing: CGFloat?
        let lineHeight: CGFloat?

        var font: OpenUIFont {
            OpenUIFont(size: size, weight: weight == "medium" ? .medium : .regular,
                       lineSpacing: lineSpacing, lineHeight: lineHeight)
        }
    }

    let colors: [String: Palette]
    let typography: [String: Typography]
    let spacing: [String: CGFloat]

    static let spacingFields: [(String, WritableKeyPath<OpenUITheme, CGFloat?>)] = [
        ("space000", \.space000), ("space3xs", \.space3xs), ("space2xs", \.space2xs),
        ("spaceXs", \.spaceXs), ("spaceS", \.spaceS), ("spaceSM", \.spaceSM),
        ("spaceM", \.spaceM), ("spaceML", \.spaceML), ("spaceL", \.spaceL), ("spaceXl", \.spaceXl),
        ("space2xl", \.space2xl), ("space3xl", \.space3xl), ("markdownListItemGap", \.markdownListItemSpacing)
    ]

    func colorValue(_ role: String, scheme: ColorScheme) -> ColorValue? {
        scheme == .dark ? colors[role]?.dark : colors[role]?.light
    }

    func openUITheme(_ mode: GalleryDesignSystem.Theme, scheme: ColorScheme) -> OpenUITheme {
        func color(_ name: String) -> Color? { colorValue(name, scheme: scheme)?.color }
        func font(_ name: String) -> OpenUIFont? { typography[name]?.font }
        var theme = OpenUITheme()
        Self.spacingFields.forEach { name, field in theme[keyPath: field] = spacing[name] }
        if mode == .liquidSphere {
            theme.radiusXl = spacing["cardCornerRadius"]
            theme.radius2xl = theme.radiusXl
            theme.radius3xl = theme.radiusXl
            theme.radius5xl = theme.radiusXl
        }
        theme.background = color("canvas")
        theme.foreground = color("surface")
        theme.sunkLight = theme.foreground
        theme.popoverBackground = theme.foreground
        theme.highlight = color("accentSoft")
        theme.borderDefault = color("separator")
        theme.borderInteractive = theme.borderDefault
        theme.borderAccent = theme.highlight
        theme.textNeutralPrimary = color("textPrimary")
        theme.textNeutralSecondary = color("textSecondary")
        theme.textNeutralTertiary = color("textTertiary")
        theme.textNeutralLink = color("link")
        theme.textAccentPrimary = color("onAccent")
        theme.invertedBackground = color("invertedBackground")
        theme.interactiveAccentDefault = color("accent")
        theme.interactiveAccentHover = color("buttonActive")
        theme.interactiveAccentPressed = theme.interactiveAccentHover
        theme.interactiveAccentDisabled = color("buttonDisabled")
        theme.textDangerPrimary = color("warning")
        theme.textAlertPrimary = color("payment")
        theme.textHeadingMd = font("title1")
        theme.textHeadingSm = font("title2")
        theme.textHeadingXs = font("title3")
        theme.textBodyDefault = font("body")
        theme.textBodyDefaultHeavy = theme.textBodyDefault?.weight(.medium)
        theme.textBodyLg = theme.textBodyDefault
        theme.textBodyLgHeavy = theme.textBodyDefaultHeavy
        theme.textBodySm = font("bodySecondary")
        theme.textBodySmHeavy = theme.textBodySm?.weight(.medium)
        theme.textBodyXs = font("labelSecondary")
        theme.textLabelSm = font("caption")
        theme.textLabelSmHeavy = theme.textBodyXs?.weight(.medium)
        theme.textLabelDefaultHeavy = theme.textLabelSmHeavy
        theme.textNumbersDefaultHeavy = theme.textBodyDefaultHeavy
        theme.markdownEmphasisFont = theme.textBodyDefaultHeavy
        if let grid = color("tableGrid"), let header = color("tagMutedBackground"), let surface = theme.foreground {
            var headerFont = theme.textHeadingXs
            if let body = theme.textBodyDefault {
                headerFont?.size = body.size
                headerFont?.lineHeight = body.lineHeight
            }
            theme.tableAppearance = OpenUITableAppearance(
                gridLine: grid, headerBackground: header, background: surface, cornerRadius: spacing["tableCornerRadius"],
                headerFont: headerFont, bodyFont: theme.textBodyDefault
            )
        }
        return theme
    }
}
