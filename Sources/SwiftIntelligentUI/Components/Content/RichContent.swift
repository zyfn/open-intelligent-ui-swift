import SwiftUI
import MarkdownUI
import SwiftLang
import CoreText

enum MarkdownComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Markdown", description: "Native rich text with headings, lists, quotes, code and tables. Links are dispatched to the caller.", params: [OpenUIParameter.string("text")]) {
            RichMarkdown(context: $0, text: $0.string("text") ?? "")
        }
    }
}

struct RichMarkdown: View {
    let context: OpenUIComponentContext
    let text: String
    var compact = false
    var isTitle = false
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var displayScale
    @Environment(\.openIntelligentUIInteractiveContent) private var interactive
    @ScaledMetric(relativeTo: .body) private var bodyScale: CGFloat = 1
    #if compiler(>=6.2)
    @Environment(\.fontResolutionContext) private var fontContext
    #endif
    private var typography: TextTypography {
        TextTypography(size: nil, weight: nil, theme: theme)
    }
    private var usesSystemBodyFamily: Bool {
        let defaults = OpenIntelligentUITheme()
        return isTitle ? theme.titleFont == defaults.titleFont : theme.bodyFont == defaults.bodyFont
    }
    private var nativeBodyFont: PlatformFont {
        #if compiler(>=6.2)
        let font = isTitle ? theme.titleFont : typography.font.weight(typography.weight)
        if #available(iOS 26, macOS 26, *) { return font.resolve(in: fontContext).ctFont as PlatformFont }
        #endif
        let fallback = isTitle
            ? InlineFonts.semantic(style: .headline, typeSize: typeSize)
            : typography.nativeFont ?? InlineFonts.semantic(size: typography.sizeName, typeSize: typeSize)
        return InlineFonts.styled(fallback, weight: isTitle ? theme.headingWeight : typography.weight, tabular: false, italic: false)
    }
    private func nativeHeadingFont(level: Int) -> PlatformFont {
        #if compiler(>=6.2)
        let font = TitleTypography.font(size: TitleTypography.size(forMarkdownLevel: level), theme: theme)
        if #available(iOS 26, macOS 26, *) { return font.resolve(in: fontContext).ctFont as PlatformFont }
        #endif
        return InlineFonts.styled(InlineFonts.semantic(style: MarkdownTypography.nativeHeadingStyle(level: level), typeSize: typeSize),
                                  weight: theme.headingWeight, tabular: false, italic: false)
    }
    var body: some View {
        let bodyFont = nativeBodyFont
        Markdown(text)
            .markdownTextStyle {
                MarkdownFontStyle(bodyFont, usesSystemFamily: usesSystemBodyFamily,
                                  size: MarkdownTypography.rootSize(bodyFont.pointSize, bodyScale: bodyScale))
                ForegroundColor(theme.primaryText)
            }
            .markdownTheme(Theme.basic
                .strong { FontWeight(theme.emphasisWeight) }
                .paragraph { configuration in
                    configuration.label.fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(typography.lineSpacing)
                        .markdownMargin(top: 0, bottom: compact ? theme.innerSpacing : theme.paragraphSpacing)
                }
                .heading1 { heading($0, level: 1, bodyFont: bodyFont) }
                .heading2 { heading($0, level: 2, bodyFont: bodyFont) }
                .heading3 { heading($0, level: 3, bodyFont: bodyFont) }
                .heading4 { heading($0, level: 4, bodyFont: bodyFont) }
                .heading5 { heading($0, level: 5, bodyFont: bodyFont) }
                .heading6 { heading($0, level: 6, bodyFont: bodyFont) }
                .codeBlock { configuration in
                    CodeBlockContent(context: context, code: configuration.content, language: configuration.language)
                        .markdownMargin(top: theme.innerSpacing, bottom: theme.groupSpacing)
                }
                .table { configuration in
                configuration.label
                    .markdownTableBorderStyle(.init(.horizontalBorders, color: theme.separator, width: 0.5))
                    .markdownMargin(top: theme.innerSpacing, bottom: theme.groupSpacing)
            })
            .foregroundStyle(theme.primaryText)
            .tint(theme.accent)
            .environment(\.openURL, OpenURLAction { url in
                guard context.canInteract, !interactive, SourceURL.isActionable(url.absoluteString) else { return .discarded }
                Task { await context.perform(OpenUIActions.openURL(url.absoluteString)) }
                return .handled
            })
    }
    private func heading(_ configuration: BlockConfiguration, level: Int, bodyFont: PlatformFont) -> some View {
        let semantic = MarkdownTypography.usesSemanticHeading(level: level, theme: theme)
        let font = semantic ? nativeHeadingFont(level: level) : bodyFont
        let size = semantic ? font.pointSize : bodyFont.pointSize * CGFloat(MarkdownTypography.headingScale(level: level, theme: theme))
        let role = TitleTypography.size(forMarkdownLevel: level)
        let systemFamily = semantic
            ? TitleTypography.font(size: role, theme: theme) == TitleTypography.font(size: role, theme: OpenIntelligentUITheme())
            : usesSystemBodyFamily
        let style = MarkdownFontStyle(font, usesSystemFamily: systemFamily, size: size, weight: semantic ? nil : theme.headingWeight)
        #if os(macOS)
        let leading: CGFloat
        if semantic && systemFamily {
            let native = MarkdownTypography.measureHeadingFont(TitleTypography.font(size: role, theme: theme),
                                                                size: typeSize, displayScale: displayScale)
            let fixed = MarkdownTypography.measureHeadingFont(.system(size: style.size.rounded()).weight(style.weight),
                                                               size: typeSize, displayScale: displayScale)
            leading = max(0, native.advance - fixed.advance)
        } else { leading = 0 }
        #else
        let leading: CGFloat = 0
        #endif
        return configuration.label
            .markdownTextStyle { style }
            .transformEnvironment(\.lineSpacing) { $0 += leading }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .markdownMargin(top: EditorialSpacing.section(theme), bottom: theme.innerSpacing)
    }
}

enum QuoteComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Quote", description: "A quotation with an optional attribution.", params: [OpenUIParameter.string("text"), OpenUIParameter.string("cite", required: false)]) {
            QuoteView(context: $0)
        }
    }
}
private struct QuoteView: View {
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacingUnit * 2) {
            RichMarkdown(context: context, text: context.string("text") ?? "", compact: true)
            if let cite = context.string("cite") { Text(cite).font(theme.captionFont).foregroundStyle(theme.secondaryText) }
        }.padding(.vertical, 14).padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .leading) { Rectangle().fill(theme.primaryText).frame(width: 3) }
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

enum BadgeComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Badge", description: "A compact status label. color defaults to neutral; icons use the supported symbol mapping.", params: [
            OpenUIParameter.string("text"), OpenUIParameter.string("color", required: false, values: ["neutral", "info", "success", "warning", "danger", "purple", "pink"]),
            OpenUIParameter.string("icon", required: false, values: IconCatalog.names)
        ]) { BadgeView(context: $0) }
    }
}
private struct BadgeView: View {
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        let token = context.string("color") ?? "neutral"
        let color = theme.textColor(token)
        HStack(spacing: theme.spacingUnit) {
            if let icon = IconCatalog.symbol(context.string("icon")) { Image(systemName: icon).foregroundStyle(color).accessibilityHidden(true) }
            Text(context.string("text") ?? "").fixedSize(horizontal: false, vertical: true)
        }.font(theme.captionFont.weight(.medium)).foregroundStyle(theme.primaryText)
            .padding(.horizontal, theme.innerSpacing).padding(.vertical, theme.spacingUnit)
            .background(token == "neutral" ? theme.surface : color.opacity(0.12), in: RoundedRectangle(cornerRadius: theme.radiusSM))
            .overlay(RoundedRectangle(cornerRadius: theme.radiusSM).strokeBorder(color.opacity(contrast == .increased ? 0.6 : 0.16)))
    }
}
