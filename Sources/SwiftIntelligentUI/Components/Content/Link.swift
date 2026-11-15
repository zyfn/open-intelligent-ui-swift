import SwiftUI
import SwiftLang

enum LinkComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Link", description: "Intentional navigation such as an official site or full guide. Dispatches the original URL through the external action handler. Use Citation for supporting sources next to the related sentence or figure credit; do not add a duplicate standalone image-source link. HTTP(S) URLs and relative paths are supported. Empty or unsafe schemes are displayed without an action.", params: [
            OpenUIParameter.string("text"), OpenUIParameter.string("url")
        ]) { SourceLink(context: $0, text: $0.string("text") ?? "", url: $0.string("url")) }
    }
}

enum SourceURL {
    static func isActionable(_ raw: String?) -> Bool {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        guard let scheme = url.scheme?.lowercased() else { return true }
        return ["http", "https"].contains(scheme) && url.host != nil
    }
}

struct SourceLink: View {
    @Environment(\.locale) private var locale
    let context: OpenUIComponentContext
    let text: String
    let url: String?
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.openIntelligentUIEditorial) private var editorial
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openIntelligentUIInteractiveContent) private var interactive
    private var typography: TextTypography {
        TextTypography(size: nil, weight: nil, editorial: editorial, theme: theme, colorScheme: colorScheme)
    }
    var body: some View {
        Group {
        if let url, SourceURL.isActionable(url), !interactive {
            OpenIntelligentUIActionSurface(context: context, action: OpenUIActions.openURL(url)) {
                Text(text.isEmpty ? url : text).underline()
                    .foregroundStyle(theme.primaryText).fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(SDKStrings.text("link.openHint", locale: locale))
        } else {
            Text(text.isEmpty ? (url ?? "") : text).foregroundStyle(interactive ? theme.primaryText : theme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
        }.font(typography.font.weight(typography.weight)).lineSpacing(typography.lineSpacing)
    }
}
