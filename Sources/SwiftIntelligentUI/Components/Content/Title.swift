import SwiftUI
import SwiftLang

enum TitleComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Title", description: "Accessible heading with Dynamic Type. md (default) is an object or card title; lg introduces a section; xl is a page title. 2xl and 3xl give a short opening heading or key figure stronger emphasis; sm labels a small group. Choose the size for the content's role; containers do not change it.", params: [
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
