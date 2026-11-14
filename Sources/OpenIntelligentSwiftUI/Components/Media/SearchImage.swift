import SwiftUI
import OpenSwiftUI
import OpenUILang

/// Caller-owned service. It returns source data; the component does not choose a provider.
@MainActor public final class IntelligentUIImageSearch: ObservableObject {
    public struct Result: Sendable {
        public let url: String
        public let alt: String
        public let revision: String
        public let attribution: String?
        public let sourceURL: String?
        public init(url: String, alt: String, revision: String = "", attribution: String? = nil, sourceURL: String? = nil) {
            self.url = url; self.alt = alt; self.revision = revision
            self.attribution = attribution; self.sourceURL = sourceURL
        }
    }
    private struct Pending {
        let id: UUID
        let task: Task<Void, Never>
        var consumers: [UUID: CheckedContinuation<Result, Error>]
    }
    private let search: (String) async throws -> Result
    private var pending: [String: Pending] = [:]
    public init(search: @escaping (String) async throws -> Result) { self.search = search }

    /// Shares simultaneous exact queries, but never caches an expiring result indefinitely.
    public func image(for query: String) async throws -> Result {
        let consumer = UUID()
        let result = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Result, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                if var work = pending[query] {
                    work.consumers[consumer] = continuation; pending[query] = work
                } else {
                    let id = UUID()
                    let task = Task {
                        do {
                            let value = try await search(query)
                            try Task.checkCancellation()
                            finish(query, id: id, result: .success(value))
                        } catch { finish(query, id: id, result: .failure(error)) }
                    }
                    pending[query] = Pending(id: id, task: task, consumers: [consumer: continuation])
                }
            }
        } onCancel: { Task { @MainActor in self.cancel(query, consumer: consumer) } }
        try Task.checkCancellation()
        return result
    }
    private func finish(_ query: String, id: UUID, result: Swift.Result<Result, Error>) {
        guard let work = pending[query], work.id == id else { return }
        pending[query] = nil
        for continuation in work.consumers.values { continuation.resume(with: result) }
    }
    private func cancel(_ query: String, consumer: UUID) {
        guard var work = pending[query], let continuation = work.consumers.removeValue(forKey: consumer) else { return }
        continuation.resume(throwing: CancellationError())
        if work.consumers.isEmpty { pending[query] = nil; work.task.cancel() }
        else { pending[query] = work }
    }
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
    @Environment(\.locale) private var locale
    let context: OpenUIComponentContext
    @ObservedObject var provider: IntelligentUIImageSearch
    @State private var result: IntelligentUIImageSearch.Result?
    @State private var resultQuery: String?
    @State private var failed = false
    @State private var retry = 0
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.intelligentUIEditorial) private var editorial
    @Environment(\.intelligentUIImageRevisions) private var revisions
    @Environment(\.intelligentUIInteractiveContent) private var interactive
    private var ratio: CGFloat { CGFloat(context.number("aspectRatio").map { min(5, max(0.2, $0)) } ?? Double(editorial.mediaRatio ?? theme.coverImageAspectRatio)) }
    private var query: String { context.string("query") ?? "" }
    var body: some View {
        VStack(alignment: .leading, spacing: theme.innerSpacing) {
            if let result, resultQuery == query {
                SourceImage(source: result.url, alt: result.alt, ratio: ratio,
                            radius: theme.radius(named: context.string("radius"), points: context.number("radius")), fit: context.string("fit") == "contain" ? .fit : .fill,
                            sourceReady: context.element.isSourceComplete, reloadSource: { retry &+= 1 })
                    .environment(\.intelligentUIImageRevisions, result.revision.isEmpty ? revisions : revisions.merging([result.url: result.revision], uniquingKeysWith: { _, new in new }))
                if let attribution = result.attribution, !attribution.isEmpty {
                    if let url = result.sourceURL, SourceURL.isActionable(url), !interactive {
                        Button {
                            guard context.canInteract else { return }
                            Task { await context.perform(OpenUIActions.openURL(url)) }
                        } label: { Text(attribution).font(theme.captionFont).foregroundStyle(theme.secondaryText) }
                            .buttonStyle(.plain).accessibilityHint(SDKStrings.text("image.source", locale: locale))
                    } else { Text(attribution).font(theme.captionFont).foregroundStyle(theme.secondaryText) }
                }
            } else {
                Rectangle().fill(theme.surface)
                    .aspectRatio(ratio, contentMode: .fit)
                    .overlay {
                        if failed {
                            ImageFailurePlaceholder(alt: query, status: SDKStrings.text("image.search_failed", locale: locale), retry: { retry &+= 1 })
                        } else {
                            ImageLoadingPlaceholder(alt: query, surface: theme.surface)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius(named: context.string("radius"), points: context.number("radius"))))
            }
        }
        .task(id: query + "#" + String(describing: ObjectIdentifier(provider)) + "#" + String(retry) + "#" + String(context.element.isSourceComplete)) {
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
