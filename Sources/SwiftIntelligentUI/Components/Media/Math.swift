import Foundation
import JavaScriptCore
import SwiftUI
import OpenUISwiftUI

final class MathTypesetter: @unchecked Sendable {
    enum Failure: Error { case missingResource, invalidExpression }
    private let context: JSContext
    private let lock = NSLock()
    init() throws {
        guard let context = JSContext(), let url = Bundle.module.url(forResource: "katex.min", withExtension: "js") else { throw Failure.missingResource }
        self.context = context
        context.exceptionHandler = { _, _ in }
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        guard context.exception == nil, context.objectForKeyedSubscript("katex")?.isObject == true else { throw Failure.missingResource }
    }
    func render(_ tex: String, inline: Bool) throws -> String {
        guard tex.count <= 20_000 else { throw Failure.invalidExpression }
        lock.lock(); defer { context.exception = nil; lock.unlock() }
        context.exception = nil
        let options: [String: Any] = ["output": "mathml", "displayMode": !inline, "throwOnError": true, "trust": false, "strict": "error", "maxExpand": 1000, "maxSize": 10]
        let result = context.objectForKeyedSubscript("katex")?.invokeMethod("renderToString", withArguments: [tex, options])
        guard context.exception == nil, let html = result?.toString(), html.contains("<math") else { throw Failure.invalidExpression }
        return html
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
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    let typesetter: MathTypesetter
    @State private var markup: String?
    @State private var failed = false
    @State private var measured = CGSize(width: 200, height: 60)
    @ScaledMetric(relativeTo: .body) private var fontSize = 20.0
    private var tex: String { context.string("tex") ?? "" }
    private var inline: Bool { context.flag("inline") == true }
    var body: some View {
        Group {
            if let markup {
                WebContent(context: context,
                           content: "<style>html,body{background:transparent}math{margin:0}</style><div id=\"equation\" style=\"display:inline-block;vertical-align:top;line-height:normal;font-size:\(fontSize)px;padding:4px\">\(markup)</div>",
                           height: min(480, max(28, measured.height)),
                           onMeasure: { measured = $0 })
                    .frame(width: inline ? min(760, max(28, measured.width)) : nil)
                    .accessibilityLabel(tex)
            } else if failed {
                VStack(alignment: .leading, spacing: theme.spacingUnit) {
                    Text("公式无法排版").font(theme.captionFont).foregroundStyle(theme.secondaryText)
                    Text(tex).font(theme.codeFont).textSelection(.enabled)
                }
            } else { ProgressView("正在排版公式") }
        }
        .task(id: tex + "#" + String(inline)) {
            markup = nil; failed = false
            let tex = tex, inline = inline, typesetter = typesetter
            do {
                let value = try await Task.detached { try typesetter.render(tex, inline: inline) }.value
                guard !Task.isCancelled else { return }
                markup = value
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}
