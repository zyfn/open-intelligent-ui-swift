import Foundation
import JavaScriptCore
import SwiftUI
import OpenUICore

final class MathTypesetter: @unchecked Sendable {
    enum Failure: Error { case missingResource, invalidExpression }
    private let context: JSContext
    private let lock = NSLock()
    private static let queue = MathTypesettingQueue()
    private var cache: [String: String] = [:]
    private var order: [String] = []
    private var cacheBytes = 0
    init() throws {
        guard let context = JSContext(), let url = Bundle.module.url(forResource: "katex.min", withExtension: "js") else { throw Failure.missingResource }
        self.context = context
        context.exceptionHandler = { _, _ in }
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        guard context.exception == nil, context.objectForKeyedSubscript("katex")?.isObject == true else { throw Failure.missingResource }
    }
    func render(_ tex: String, inline: Bool) throws -> String {
        guard tex.count <= 20_000 else { throw Failure.invalidExpression }
        try Task.checkCancellation()
        lock.lock(); defer { context.exception = nil; lock.unlock() }
        try Task.checkCancellation()
        let key = "\(inline):\(tex)"
        if let result = cache[key] { return result }
        context.exception = nil
        let options: [String: Any] = ["output": "mathml", "displayMode": !inline, "throwOnError": true, "trust": false, "strict": "error", "maxExpand": 1000, "maxSize": 10]
        let html: String = try IntelligentUIPerformance.measure("math.typeset") {
            let result = context.objectForKeyedSubscript("katex")?.invokeMethod("renderToString", withArguments: [tex, options])
            guard context.exception == nil, let html = result?.toString(), html.contains("<math"),
                  html.utf8.count <= 512 * 1024 else { throw Failure.invalidExpression }
            return html
        }
        try Task.checkCancellation()
        let cost = key.utf8.count + html.utf8.count
        while order.count >= 32 || cacheBytes + cost > 2 * 1024 * 1024 {
            guard let oldest = order.first else { break }
            order.removeFirst()
            if let old = cache.removeValue(forKey: oldest) { cacheBytes -= oldest.utf8.count + old.utf8.count }
        }
        cache[key] = html; order.append(key); cacheBytes += cost
        return html
    }
    func renderAsync(_ tex: String, inline: Bool) async throws -> String {
        try await Self.queue.render(self, tex: tex, inline: inline)
    }

}

/// Actor jobs retain the caller's cancellation; obsolete jobs skip work when they reach the queue.
private actor MathTypesettingQueue {
    func render(_ typesetter: MathTypesetter, tex: String, inline: Bool) throws -> String {
        try Task.checkCancellation()
        return try typesetter.render(tex, inline: inline)
    }
}

enum MathComponent {
    static func component(typesetter: MathTypesetter) -> OpenUIComponent {
        OpenUIComponent(name: "Math", description: "TeX typeset offline to MathML using bundled KaTeX, displayed in local WebKit. No CDN, native bridge or generated script execution. inline defaults to false. Invalid expressions show explicit error and source.", params: [OpenUIParameter.string("tex"), OpenUIParameter.flag("inline")]) {
            MathView(context: $0, typesetter: typesetter)
        }
    }
}
private struct MathView: View {
    @Environment(\.locale) private var locale
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    let typesetter: MathTypesetter
    @State private var markup: String?
    @State private var renderedKey: String?
    @State private var failed = false
    @State private var measured = CGSize(width: 200, height: 60)
    @ScaledMetric(relativeTo: .body) private var fontSize = 20.0
    private var tex: String { context.string("tex") ?? "" }
    private var inline: Bool { context.flag("inline") == true }
    private var key: String { "\(inline):\(tex)" }
    var body: some View {
        Group {
            if !context.element.isSourceComplete {
                placeholder
            } else if let markup, renderedKey == key {
                MathSizingLayout(inline: inline, measured: measured) {
                    WebContent(context: context,
                        content: "<style>html,body{background:transparent}math{margin:0}</style><div id=\"equation\" style=\"display:inline-block;vertical-align:top;line-height:normal;font-size:\(fontSize)px;padding:4px\">\(markup)</div>",
                        height: min(480, max(28, measured.height)), onMeasure: { size in
                            guard renderedKey == key, abs(size.width - measured.width) >= 0.5 || abs(size.height - measured.height) >= 0.5 else { return }
                            measured = size
                        })
                }.accessibilityLabel(tex)
            } else if failed {
                VStack(alignment: .leading, spacing: theme.spacingUnit) {
                    Text(SDKStrings.text("math.failed", locale: locale)).font(theme.captionFont).foregroundStyle(theme.secondaryText)
                    Text(tex).font(theme.codeFont).textSelection(.enabled)
                }
            } else { placeholder }
        }
        .task(id: "\(key):\(context.element.isSourceComplete)") {
            failed = false
            guard context.element.isSourceComplete else { return }
            let requested = key, tex = tex, inline = inline
            do {
                let value = try await typesetter.renderAsync(tex, inline: inline)
                guard !Task.isCancelled else { return }
                markup = value; renderedKey = requested
            } catch { if !Task.isCancelled { markup = nil; renderedKey = nil; failed = true } }
        }
    }
    private var placeholder: some View {
        MathSizingLayout(inline: inline, measured: measured) { ProgressView(SDKStrings.text("math.preparing", locale: locale)) }
    }
}

private struct MathSizingLayout: Layout {
    let inline: Bool
    let measured: CGSize
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = min(760, max(28, measured.width))
        let width = inline ? min(proposal.width ?? ideal, ideal) : proposal.width ?? ideal
        return CGSize(width: max(1, width), height: min(480, max(28, measured.height)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: .init(width: bounds.width, height: bounds.height))
    }
}
