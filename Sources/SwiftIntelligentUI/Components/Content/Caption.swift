import SwiftUI
import OpenUISwiftUI

enum CaptionComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Caption", description: "Small secondary text with inline Markdown and links. color defaults to muted.", params: [
            OpenUIParameter.string("text"), OpenUIParameter.string("color", required: false, values: Parameter.colors)
        ]) { CaptionView(context: $0) }
    }
}

private struct CaptionView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    var body: some View {
        Text(InlineTypography.attributed(context.string("text") ?? "", font: theme.captionFont, emphasis: theme.emphasisWeight)).font(theme.captionFont)
            .foregroundStyle(theme.textColor(context.string("color") ?? "muted"))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                guard context.canInteract, SourceURL.isActionable(url.absoluteString) else { return .discarded }
                Task { await context.perform(OpenUIActions.openURL(url.absoluteString)) }; return .handled
            })
    }
}
