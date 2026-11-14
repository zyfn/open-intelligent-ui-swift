import SwiftUI
import OpenUILang
import OpenSwiftUI

enum CitationComponent {
    static var component: OpenUIComponent {
        let source = Parameter.objectSchema([("title", Parameter.stringSchema), ("url", Parameter.stringSchema)], required: ["title", "url"])
        return OpenUIComponent(name: "Citation", description: "Compact optional source references. sources contain caller-supplied title/url, duplicate URLs use the first. A single source opens its original URL; several sources open an accessible source list popover. Never invent references or append them to product cards by default.", params: [ParamDef(name: "sources", required: true, schema: Parameter.arraySchema(source, maximum: 30))]) { CitationView(context: $0) }
    }
}

struct CitationSource: Identifiable {
    let title: String
    let url: String
    var id: String { url }
    var domain: String {
        guard let host = URL(string: url)?.host else { return title }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    static func decode(_ value: Value?) -> [Self] {
        var seen = Set<String>()
        return ValueReading.array(value).compactMap { source in
            let title = ValueReading.string(ValueReading.field(source, "title")), url = ValueReading.string(ValueReading.field(source, "url"))
            guard !title.isEmpty, !url.isEmpty, seen.insert(url).inserted else { return nil }
            return Self(title: title, url: url)
        }
    }
}
private struct CitationView: View {
    @Environment(\.locale) private var locale
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.intelligentUIInlineContent) private var inline
    @Environment(\.intelligentUIInteractiveContent) private var interactive
    @State private var presented = false
    private var sources: [CitationSource] { CitationSource.decode(context.value("sources")) }
    var body: some View {
        if let first = sources.first {
            Group {
                if interactive { label(first) }
                else if sources.count == 1 {
                    OpenUIActionSurface(context: context, action: OpenUIActions.openURL(first.url), useNativeStyle: true) { label(first) }
                        .disabled(!SourceURL.isActionable(first.url))
                } else {
                    Button { presented = true } label: { label(first) }.disabled(!context.canInteract)
                        .popover(isPresented: $presented) { details }
                }
            }.buttonStyle(.plain).accessibilityLabel(sources.count == 1 ? SDKStrings.text("citation.openOne", locale: locale, first.title) : SDKStrings.text("citation.openMany", locale: locale, Int64(sources.count)))
                .onChange(of: sources.map(\.id)) { _ in presented = false }
        }
    }
    private func label(_ source: CitationSource) -> some View {
        HStack(spacing: theme.spacingUnit) {
            Image(systemName: "globe").accessibilityHidden(true)
            Text(source.domain).lineLimit(1)
            if sources.count > 1 { Text("+\(sources.count - 1)").monospacedDigit() }
        }.font(theme.captionFont).foregroundStyle(theme.secondaryText)
            .padding(.horizontal, theme.innerSpacing).padding(.vertical, theme.spacingUnit)
            .background(theme.surface, in: Capsule()).frame(minHeight: inline ? nil : theme.minimumControlHeight, alignment: .leading)
            .contentShape(Rectangle())
    }
    @ViewBuilder private var details: some View {
        let content = VStack(alignment: .leading, spacing: theme.innerSpacing) {
            HStack { Text(SDKStrings.text("citation.title", locale: locale)).font(theme.titleFont); Spacer(); Button(SDKStrings.text("common.done", locale: locale)) { presented = false }.accessibilityLabel(SDKStrings.text("citation.close", locale: locale)).frame(minHeight: theme.minimumControlHeight) }
            BoundedContentScroll(maximumHeight: 400) {
                VStack(alignment: .leading, spacing: theme.innerSpacing) {
                    ForEach(sources) { source in
                        OpenUIActionSurface(context: context, action: OpenUIActions.openURL(source.url), useNativeStyle: true) {
                            VStack(alignment: .leading, spacing: theme.spacingUnit) { Text(source.title).font(theme.bodyFont); Text(source.domain).font(theme.captionFont).foregroundStyle(theme.secondaryText) }
                                .frame(maxWidth: .infinity, minHeight: theme.minimumControlHeight, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }.buttonStyle(.plain).disabled(!SourceURL.isActionable(source.url))
                    }
                }
            }
        }.padding(theme.groupSpacing).frame(minWidth: 240, idealWidth: 300, maxWidth: 360).tint(theme.actionAccent)
        if #available(iOS 16.4, macOS 13.3, *) { content.presentationCompactAdaptation(.popover) } else { content }
    }
}
