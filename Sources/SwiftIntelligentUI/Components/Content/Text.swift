import SwiftUI
import OpenUISwiftUI

enum TextComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Text", description: "Inline Markdown text or mixed strings/components. Sizes are only xs/sm/md/lg; xl and 2xl belong to Title, not Text. Prominent amounts/statistics use lg with semibold and tabularNums true. Defaults: size md, color ink, weight normal, italic false, lineThrough false, tabularNums false, unlimited lines. Positive maxLines applies to string segments. Mixed strings and inline components share a native TextKit paragraph, including last-line wrapping; no HTML interpretation.", params: [
            Parameter.textOrChildren("text"),
            OpenUIParameter.string("size", required: false, values: ["xs", "sm", "md", "lg"]),
            OpenUIParameter.string("color", required: false, values: Parameter.colors),
            OpenUIParameter.string("weight", required: false, values: ["normal", "medium", "semibold"]),
            OpenUIParameter.flag("italic"), OpenUIParameter.flag("lineThrough"),
            OpenUIParameter.flag("tabularNums"), Parameter.number("maxLines", minimum: 0, maximum: 1000)
        ]) { TextView(context: $0) }
    }
}

private struct TextView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.intelligentUIEditorial) private var editorial
    @Environment(\.intelligentUIMapContent) private var inMap
    private var font: Font {
        if inMap { return theme.mapCardSecondaryFont }
        if editorial.cardSubtitle { return theme.captionFont }
        if editorial.compactContent && (context.string("size") == nil || context.string("size") == "md") { return theme.secondaryFont }
        switch context.string("size") {
        case "xs": return theme.captionFont
        case "sm": return theme.secondaryFont
        case "lg": return theme.bodyLargeFont
        default: return theme.bodyFont
        }
    }
    private var weight: Font.Weight {
        switch context.string("weight") {
        case "medium": return .medium
        case "semibold": return .semibold
        default: return .regular
        }
    }
    @ViewBuilder var body: some View {
        if let text = context.string("text") { styled(text) }
        else {
            InlineParagraph(context: context)
        }
    }
    private func styled(_ text: String) -> some View {
        Text(InlineTypography.attributed(text, font: context.flag("tabularNums") == true ? font.monospacedDigit() : font, emphasis: theme.emphasisWeight))
            .font((context.flag("tabularNums") == true ? font.monospacedDigit() : font).weight(weight))
            .foregroundStyle((inMap || editorial.cardSubtitle) && context.string("color") == nil ? theme.secondaryText : theme.textColor(context.string("color")))
            .italic(context.flag("italic") ?? false)
            .strikethrough(context.flag("lineThrough") ?? false)
            .lineSpacing(["xs", "sm"].contains(context.string("size") ?? "md") ? theme.bodyLineSpacing / 2 : theme.bodyLineSpacing)
            .lineLimit(inMap ? 1 : TextLineLimit.resolve(context.number("maxLines")))
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                guard context.canInteract, SourceURL.isActionable(url.absoluteString) else { return .discarded }
                Task { await context.perform(OpenUIActions.openURL(url.absoluteString)) }
                return .handled
            })
    }
}

enum TextLineLimit {
    static func resolve(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return Int(min(1000, max(1, value.rounded())))
    }
}
