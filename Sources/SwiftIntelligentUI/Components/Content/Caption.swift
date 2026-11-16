import SwiftUI
import SwiftLang

enum CaptionComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Caption", description: "Small secondary text with inline Markdown and links. color defaults to muted.", params: [
            OpenUIParameter.string("text"), OpenUIParameter.string("color", required: false, values: Parameter.colors)
        ]) { CaptionView(context: $0) }
    }
}

private struct CaptionView: View {
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.openIntelligentUIInteractiveContent) private var interactive
    private var typography: TextTypography { TextTypography(size: "xs", weight: nil, theme: theme) }
    var body: some View {
        Text(InlineTypography.attributed(context.string("text") ?? "", font: typography.font, emphasis: theme.emphasisWeight))
            .font(typography.font)
            .lineSpacing(typography.lineSpacing)
            .foregroundStyle(theme.textColor(context.string("color") ?? "muted"))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                guard context.canInteract, !interactive, SourceURL.isActionable(url.absoluteString) else { return .discarded }
                Task { await context.perform(OpenUIActions.openURL(url.absoluteString)) }; return .handled
            })
    }
}
