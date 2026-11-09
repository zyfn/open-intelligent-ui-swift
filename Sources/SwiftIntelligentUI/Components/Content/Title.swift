import SwiftUI
import OpenUISwiftUI

enum TitleComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Title", description: "Accessible heading. size defaults to md; uses Dynamic Type.", params: [
            OpenUIParameter.string("text"),
            OpenUIParameter.string("size", required: false, values: ["sm", "md", "lg", "xl", "2xl", "3xl"]),
            OpenUIParameter.string("color", required: false, values: Parameter.colors)
        ]) { TitleView(context: $0) }
    }
}

private struct TitleView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.intelligentUIEditorial) private var editorial
    private var font: Font {
        if editorial.openingCardTitle && [nil, "sm", "md"].contains(context.string("size")) { return theme.secondaryFont.weight(.medium) }
        if editorial.compactContent && ["lg", "xl", "2xl", "3xl"].contains(context.string("size") ?? "md") { return theme.bodyLargeFont.weight(theme.headingWeight) }
        switch context.string("size") {
        case "sm": return theme.secondaryFont.weight(theme.headingWeight)
        case "lg": return theme.sectionTitleFont
        case "xl": return theme.pageTitleFont
        case "2xl": return theme.largeTitleFont
        case "3xl": return theme.displayFont
        default: return theme.titleFont
        }
    }
    var body: some View {
        Text(InlineTypography.attributed(context.string("text") ?? "", font: font, emphasis: theme.headingWeight))
            .font(font)
            .foregroundStyle(theme.textColor(context.string("color")))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .environment(\.openURL, OpenURLAction { url in
                guard context.canInteract, SourceURL.isActionable(url.absoluteString) else { return .discarded }
                Task { await context.perform(OpenUIActions.openURL(url.absoluteString)) }; return .handled
            })
    }
}
