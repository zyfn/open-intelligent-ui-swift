import SwiftUI
import OpenUISwiftUI

/// Caller-owned service. It returns source data; the component does not choose a provider.
@MainActor public final class IntelligentUIImageSearch: ObservableObject {
    public struct Result: Sendable {
        public let url: String
        public let alt: String
        public init(url: String, alt: String) { self.url = url; self.alt = alt }
    }
    private let search: (String) async throws -> Result
    public init(search: @escaping (String) async throws -> Result) { self.search = search }
    public func image(for query: String) async throws -> Result { try await search(query) }
}
enum SearchImageComponent {
    static func component(provider: IntelligentUIImageSearch) -> OpenUIComponent {
        OpenUIComponent(name: "SearchImage", description: "Image search through the caller-provided service. Shows loading, error and retry. No search provider or credentials are bundled.", params: [
            OpenUIParameter.string("query"), Parameter.number("aspectRatio", minimum: 0.2, maximum: 5), Parameter.radius(),
            OpenUIParameter.string("fit", required: false, values: ["cover", "contain"])
        ]) { SearchImageView(context: $0, provider: provider) }
    }
}
private struct SearchImageView: View {
    let context: OpenUIComponentContext
    @ObservedObject var provider: IntelligentUIImageSearch
    @State private var result: IntelligentUIImageSearch.Result?
    @State private var resultQuery: String?
    @State private var failed = false
    @State private var retry = 0
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.intelligentUIEditorial) private var editorial
    private var ratio: CGFloat { CGFloat(context.number("aspectRatio").map { min(5, max(0.2, $0)) } ?? Double(editorial.mediaRatio ?? theme.coverImageAspectRatio)) }
    private var query: String { context.string("query") ?? "" }
    var body: some View {
        VStack(alignment: .leading, spacing: theme.innerSpacing) {
            if let result, resultQuery == query {
                SourceImage(source: result.url, alt: result.alt, ratio: ratio,
                            radius: theme.radius(named: context.string("radius"), points: context.number("radius")), fit: context.string("fit") == "contain" ? .fit : .fill)
            } else {
                Rectangle().fill(theme.surface)
                    .aspectRatio(ratio, contentMode: .fit)
                    .overlay {
                        if failed {
                            ImageFailurePlaceholder(alt: query, status: "未能获取图片")
                                .overlay(alignment: .bottomTrailing) {
                                    Button { retry += 1 } label: {
                                        Image(systemName: "arrow.clockwise")
                                            .frame(minWidth: theme.minimumControlHeight, minHeight: theme.minimumControlHeight)
                                    }
                                    .buttonStyle(.borderless).tint(theme.actionAccent)
                                    .accessibilityLabel("重新加载图片")
                                }
                        } else {
                            ImageLoadingPlaceholder(alt: query, surface: theme.surface)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius(named: context.string("radius"), points: context.number("radius"))))
            }
        }
        .task(id: query + "#" + String(retry) + "#" + String(context.element.isSourceComplete)) {
            result = nil; resultQuery = nil; failed = false
            guard context.element.isSourceComplete else { return }
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { failed = true; return }
            do {
                let response = try await provider.image(for: query)
                guard !Task.isCancelled else { return }
                result = response
                resultQuery = query
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}
