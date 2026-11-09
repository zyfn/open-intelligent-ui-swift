import SwiftUI
import MarkdownUI
import OpenUILang
import OpenUISwiftUI

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
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Markdown(text)
            .markdownTheme(Theme.basic
                .strong { FontWeight(theme.emphasisWeight) }
                .paragraph { configuration in
                    configuration.label.fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(theme.bodyLineSpacing)
                        .markdownMargin(top: 0, bottom: compact ? 0 : theme.paragraphSpacing)
                }
                .heading1 { configuration in
                    configuration.label.markdownTextStyle { FontSize(.em(theme.headingScale(0))); FontWeight(theme.headingWeight) }
                        .markdownMargin(top: theme.sectionSpacing + theme.innerSpacing, bottom: theme.innerSpacing)
                }
                .heading2 { configuration in
                    configuration.label.markdownTextStyle { FontSize(.em(theme.headingScale(1))); FontWeight(theme.headingWeight) }
                        .markdownMargin(top: theme.sectionSpacing + theme.innerSpacing, bottom: theme.innerSpacing)
                }
                .heading3 { configuration in
                    configuration.label.markdownTextStyle { FontSize(.em(theme.headingScale(2))); FontWeight(theme.headingWeight) }
                        .markdownMargin(top: theme.groupSpacing, bottom: theme.innerSpacing)
                }
                .heading4 { configuration in
                    configuration.label.markdownTextStyle { FontSize(.em(1)); FontWeight(theme.headingWeight) }
                        .markdownMargin(top: .rem(1.5), bottom: .rem(1))
                }
                .heading5 { configuration in
                    configuration.label.markdownTextStyle { FontSize(.em(0.83)); FontWeight(theme.headingWeight) }
                        .markdownMargin(top: .rem(1.5), bottom: .rem(1))
                }
                .heading6 { configuration in
                    configuration.label.markdownTextStyle { FontSize(.em(0.67)); FontWeight(theme.headingWeight) }
                        .markdownMargin(top: .rem(1.5), bottom: .rem(1))
                }
                .codeBlock { configuration in
                    CodeBlockContent(context: context, code: configuration.content, language: configuration.language)
                        .markdownMargin(top: theme.innerSpacing, bottom: theme.groupSpacing)
                }
                .table { configuration in
                configuration.label
                    .markdownTableBorderStyle(.init(.horizontalBorders, color: theme.separator, width: 0.5))
                    .markdownMargin(top: theme.innerSpacing, bottom: theme.groupSpacing)
            })
            .font(isTitle ? theme.titleFont : theme.bodyFont(for: colorScheme))
            .foregroundStyle(theme.primaryText)
            .tint(theme.accent)
            .environment(\.openURL, OpenURLAction { url in
                guard context.canInteract, SourceURL.isActionable(url.absoluteString) else { return .discarded }
                Task { await context.perform(OpenUIActions.openURL(url.absoluteString)) }
                return .handled
            })
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
    @Environment(\.intelligentUITheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacingUnit * 2) {
            RichMarkdown(context: context, text: context.string("text") ?? "", compact: true)
            if let cite = context.string("cite") { Text(cite).font(theme.captionFont).foregroundStyle(theme.secondaryText) }
        }.padding(.vertical, 14).padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .leading) { Rectangle().fill(theme.primaryText).frame(width: 3) }
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
    @Environment(\.intelligentUITheme) private var theme
    var body: some View {
        let token = context.string("color") ?? "neutral"
        let color = token == "info" ? theme.primaryText : theme.textColor(token)
        HStack(spacing: theme.spacingUnit) {
            if let icon = IconCatalog.symbol(context.string("icon")) { Image(systemName: icon).accessibilityHidden(true) }
            Text(context.string("text") ?? "").fixedSize(horizontal: false, vertical: true)
        }.font(theme.captionFont.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, theme.innerSpacing).padding(.vertical, theme.spacingUnit)
            .background(color.opacity(token == "neutral" || token == "info" ? 0.06 : 0.12), in: Capsule())
    }
}
