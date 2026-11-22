import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Semantic styles scoped to an individual render subtree.
public struct OpenIntelligentUITheme: Equatable {
    public var primaryText: Color = .primary
    public var secondaryText: Color = .secondary
    public var faintText: Color = .secondary.opacity(0.6)
    public var canvas: Color = NativeColors.canvas
    public var surface: Color = NativeColors.surface
    public var surfaceStrong: Color = NativeColors.surfaceStrong
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
    public var bodyFont: Font = .body { didSet { nativeTextFonts.removeValue(forKey: .body) } }
    public var secondaryFont: Font = .subheadline { didSet { nativeTextFonts.removeValue(forKey: .secondary) } }
    public var captionFont: Font = .footnote { didSet { nativeTextFonts.removeValue(forKey: .caption) } }
    public var labelFont: Font = .subheadline.weight(.medium)
    public var bodyLargeFont: Font = .title3 { didSet { nativeTextFonts.removeValue(forKey: .bodyLarge) } }
    public var sectionTitleFont: Font = .title3.weight(.semibold)
    public var pageTitleFont: Font = .title2.weight(.semibold)
    public var largeTitleFont: Font = .title.weight(.semibold)
    public var displayFont: Font = .largeTitle.weight(.semibold)
    public var headingWeight: Font.Weight = .semibold
    public var emphasisWeight: Font.Weight = .semibold
    public var codeFont: Font = .system(.body, design: .monospaced)
    public var markdownHeadingScales: [Double] = [22.0 / 17.0, 20.0 / 17.0, 1] {
        didSet { hasCustomMarkdownHeadingScales = true }
    }
    var hasCustomMarkdownHeadingScales = false
    public var codeKeyword: Color = .purple
    public var codeLiteral: Color = .red
    public var codeNumber: Color = .blue
    public var titleFont: Font = .headline.weight(.semibold)
    public var priceFont: Font = .title3.weight(.semibold)
    public var coverImageAspectRatio: CGFloat = 3.0 / 2.0
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
    // Optional native partners for TextKit on systems that cannot resolve Font.
    var nativeTextFonts: [OpenIntelligentUITextFontRole: OpenIntelligentUINativeFont] = [:]
    // Native fields and outline/soft buttons own an opaque theme surface.
    // Keep that surface's original text roles when onBackground changes text
    // on the surrounding raw-color surface. This is not a model-facing option.
    private struct OpaqueSurfaceColors: Equatable {
        let primary: Color
        let secondary: Color
        let accent: Color
    }
    private var opaqueSurfaceColors: OpaqueSurfaceColors?
    var fieldText: Color { opaqueSurfaceColors?.primary ?? primaryText }
    var fieldSecondaryText: Color { opaqueSurfaceColors?.secondary ?? secondaryText }
    var surfaceAccent: Color { opaqueSurfaceColors?.accent ?? actionAccent }
    var fieldAccent: Color { surfaceAccent }
    public init() {}

    func headingScale(_ level: Int) -> Double {
        markdownHeadingScales.indices.contains(level) ? markdownHeadingScales[level] : 1
    }

    func textColor(_ token: String?) -> Color {
        guard let token else { return primaryText }
        return foregroundToken(token) ?? CSSColor.parse(token)?.color ?? primaryText
    }

    /// Foreground and background have distinct upstream token maps. In
    /// particular, muted/faint keep their paint when used as a background;
    /// only status backgrounds are replaced by their soft tint.
    private func foregroundToken(_ token: String) -> Color? {
        switch token {
        case "ink": return primaryText
        case "muted": return secondaryText
        case "faint": return faintText
        case "canvas": return canvas
        case "surface": return surface
        case "info": return info
        case "warning": return warning
        case "purple": return .purple
        case "pink": return .pink
        case "success": return success
        case "danger": return danger
        default:
            if token.hasPrefix("chart"), let index = Int(token.dropFirst(5)),
               (1...6).contains(index), token == "chart\(index)", chartColors.indices.contains(index - 1) {
                return chartColors[index - 1]
            }
            return nil
        }
    }

    func backgroundColor(_ token: String) -> Color {
        switch token {
        case "surface-strong": return surfaceStrong
        case "border": return fieldBorder
        case "info", "success", "warning", "danger", "purple", "pink":
            return textColor(token).opacity(0.12)
        default: return foregroundToken(token) ?? CSSColor.parse(token)?.color ?? .clear
        }
    }

    /// Upstream onColor changes text roles on recognized raw backgrounds.
    /// Passing a theme token preserves this theme. Explicit child CSS colors
    /// still resolve independently through textColor(_:).
    func onBackground(_ value: String?) -> OpenIntelligentUITheme {
        guard let value, foregroundToken(value) == nil,
              !["surface-strong", "border"].contains(value),
              let ink = CSSColor.contrastInk(on: value) else { return self }
        var result = self
        result.opaqueSurfaceColors = opaqueSurfaceColors
            ?? OpaqueSurfaceColors(primary: primaryText, secondary: secondaryText, accent: actionAccent)
        result.primaryText = ink.color
        result.secondaryText = ink.color.opacity(0.72)
        result.faintText = ink.color.opacity(0.55)
        result.actionAccent = ink.color
        result.actionForeground = ink.red < 1
            ? Color(.sRGB, red: 1, green: 1, blue: 1)
            : Color(.sRGB, red: 13.0 / 255, green: 13.0 / 255, blue: 13.0 / 255)
        return result
    }

    /// Only the native opaque variants need the saved surface accent. Explicit
    /// status colors keep their existing paint; solid/ghost follow onBackground.
    func buttonAccent(_ color: String?, variant: String) -> Color {
        switch color {
        case "danger": return danger
        case "success": return success
        default: return variant == "outline" || variant == "soft" ? surfaceAccent : actionAccent
        }
    }

    /// Values and fallback count theme units. Like upstream space(), negative
    /// inputs become zero; no model-facing maximum is imposed. Non-finite
    /// values or overflowing arithmetic use the finite default instead.
    func spacing(_ value: Double?, fallback: CGFloat = 0) -> CGFloat {
        let unit = spacingUnit.isFinite ? max(0, spacingUnit) : 4
        let defaultPoints = max(0, fallback.isFinite ? fallback : 0) * unit
        let safeDefault = defaultPoints.isFinite ? defaultPoints : 0
        guard let value, value.isFinite else { return safeDefault }
        let points = CGFloat(max(0, value)) * unit
        return points.isFinite ? points : safeDefault
    }

    func radius(named name: String?, points: Double? = nil, fallback: CGFloat? = nil) -> CGFloat {
        if let points, points.isFinite { return CGFloat(max(0, points)) }
        switch name {
        case "sm": return radiusSM
        case "md": return radiusMD
        case "lg": return radiusLG
        case "xl": return radiusXL
        case "full": return 999
        default: return fallback ?? cornerRadius
        }
    }
}

/// The four existing Text size roles. This is a Swift host configuration API,
/// not an additional component or language parameter.
public enum OpenIntelligentUITextFontRole: String, Hashable, Sendable {
    case body, secondary, caption, bodyLarge
}

#if canImport(UIKit)
typealias OpenIntelligentUINativeFont = UIFont
extension OpenIntelligentUITheme {
    /// Pairs a concrete font with its SwiftUI representation for identical
    /// string/inline typography on every supported OS. The supplied size is
    /// preserved; callers can supply a UIFontMetrics-scaled font when needed.
    public mutating func setTextFont(_ font: UIFont, for role: OpenIntelligentUITextFontRole) {
        setSwiftUIFont(Font(font), for: role)
        nativeTextFonts[role] = font
    }
}
#else
typealias OpenIntelligentUINativeFont = NSFont
extension OpenIntelligentUITheme {
    /// Pairs a concrete font with its SwiftUI representation. Its supplied
    /// point size is preserved in both ordinary and inline text.
    public mutating func setTextFont(_ font: NSFont, for role: OpenIntelligentUITextFontRole) {
        setSwiftUIFont(Font(font), for: role)
        nativeTextFonts[role] = font
    }
}
#endif

private extension OpenIntelligentUITheme {
    mutating func setSwiftUIFont(_ font: Font, for role: OpenIntelligentUITextFontRole) {
        switch role {
        case .body: bodyFont = font
        case .secondary: secondaryFont = font
        case .caption: captionFont = font
        case .bodyLarge: bodyLargeFont = font
        }
    }
}

private enum NativeColors {
    #if canImport(UIKit)
    static var canvas: Color { Color(uiColor: .systemBackground) }
    static var surface: Color { Color(uiColor: .secondarySystemBackground) }
    static var surfaceStrong: Color { Color(uiColor: .tertiarySystemBackground) }
    static var separator: Color { Color(uiColor: .separator) }
    static let minimumControlHeight: CGFloat = 44
    #else
    static var canvas: Color { Color(nsColor: .windowBackgroundColor) }
    static var surface: Color { Color(nsColor: .controlBackgroundColor) }
    static var surfaceStrong: Color { Color(nsColor: .underPageBackgroundColor) }
    static var separator: Color { Color(nsColor: .separatorColor) }
    static let minimumControlHeight: CGFloat = 28
    #endif
}

extension EnvironmentValues {
    @Entry public var openIntelligentUITheme = OpenIntelligentUITheme()
    @Entry var openIntelligentUIContentBackground: Color? = nil
    @Entry var openIntelligentUIScrolling = false
}

extension View {
    public func openIntelligentUITheme(_ theme: OpenIntelligentUITheme) -> some View {
        environment(\.openIntelligentUITheme, theme)
    }
}
