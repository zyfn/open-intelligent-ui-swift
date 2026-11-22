import SwiftUI
import SwiftLang

enum TitleComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Title", description: "Accessible heading. size defaults to md; uses Dynamic Type.", params: [
            OpenUIParameter.string("text"),
            OpenUIParameter.string("size", required: false, values: ["sm", "md", "lg", "xl", "2xl", "3xl"]),
            Parameter.color()
        ]) { TitleView(context: $0) }
    }
}

private struct TitleView: View {
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.openIntelligentUIInteractiveContent) private var interactive
    private var font: Font {
        TitleTypography.font(size: context.string("size"), theme: theme)
    }
    var body: some View {
        Text(InlineTypography.attributed(context.string("text") ?? "", font: font, emphasis: theme.headingWeight))
            .font(font)
            .foregroundStyle(theme.textColor(context.string("color")))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .environment(\.openURL, OpenURLAction { url in
                guard context.canInteract, !interactive, SourceURL.isActionable(url.absoluteString) else { return .discarded }
                Task { await context.perform(OpenUIActions.openURL(url.absoluteString)) }; return .handled
            })
    }
}
