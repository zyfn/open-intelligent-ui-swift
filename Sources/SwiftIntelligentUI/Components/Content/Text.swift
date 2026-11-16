import SwiftUI
import SwiftLang

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
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.openIntelligentUIInteractiveContent) private var interactive
    private var typography: TextTypography {
        TextTypography(size: context.string("size"), weight: context.string("weight"), theme: theme)
    }
    @ViewBuilder var body: some View {
        if let text = context.string("text") { styled(text) }
        else {
            InlineParagraph(context: context)
        }
    }
    private func styled(_ text: String) -> some View {
        let font = typography.font
        return Text(InlineTypography.attributed(text, font: context.flag("tabularNums") == true ? font.monospacedDigit() : font, emphasis: theme.emphasisWeight))
            .font((context.flag("tabularNums") == true ? font.monospacedDigit() : font).weight(typography.weight))
            .foregroundStyle(theme.textColor(context.string("color")))
            .italic(context.flag("italic") ?? false)
            .strikethrough(context.flag("lineThrough") ?? false)
            .lineSpacing(typography.lineSpacing)
            .lineLimit(TextLineLimit.resolve(context.number("maxLines")))
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                guard context.canInteract, !interactive, SourceURL.isActionable(url.absoluteString) else { return .discarded }
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
