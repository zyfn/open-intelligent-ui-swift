import SwiftUI
import OpenUISwiftUI

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
    let context: OpenUIComponentContext
    let text: String
    let url: String?
    @Environment(\.intelligentUITheme) private var theme
    var body: some View {
        if let url, SourceURL.isActionable(url) {
            OpenUIActionSurface(context: context, action: OpenUIActions.openURL(url), useNativeStyle: true) {
                Text(text.isEmpty ? url : text).underline()
                    .foregroundStyle(theme.primaryText).fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("由应用打开链接")
        } else {
            Text(text).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }
}
