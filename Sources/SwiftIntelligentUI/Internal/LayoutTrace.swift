import SwiftUI
import Foundation

/// Opt-in DEBUG diagnostics. Never records source text, URLs, logical ids or business values.
enum LayoutTrace {
    #if DEBUG
    static let enabled = ProcessInfo.processInfo.environment["SWIFT_INTELLIGENT_UI_LAYOUT_TRACE"] == "1"
        || ProcessInfo.processInfo.arguments.contains("--siui-layout-trace")
    private static let lock = NSLock()
    private static var seen = Set<String>()
    #else
    static let enabled = false
    #endif

    static func record(_ phase: String, _ values: @autoclosure () -> String) {
        #if DEBUG
        guard enabled else { return }
        let line = "SIUI_LAYOUT " + phase + " " + values()
        lock.lock()
        let emit = seen.count < 512 && seen.insert(line).inserted
        lock.unlock()
        if emit { print(line) }
        #endif
    }
    static func number(_ value: CGFloat?) -> String {
        value.map { String(format: "%.2f", Double($0)) } ?? "nil"
    }
}

private struct LayoutTraceModifier: ViewModifier {
    let phase: String
    let values: String
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG
        if LayoutTrace.enabled {
            content.background(GeometryReader { geometry in
                Color.clear.onAppear { report(geometry.size) }
                    .onChange(of: geometry.size) { report($0) }
            })
        } else { content }
        #else
        content
        #endif
    }
    private func report(_ size: CGSize) {
        LayoutTrace.record(phase, values + " actualW=" + LayoutTrace.number(size.width) + " actualH=" + LayoutTrace.number(size.height))
    }
}

extension View {
    func intelligentUILayoutTrace(_ phase: String, _ values: String = "") -> some View {
        modifier(LayoutTraceModifier(phase: phase, values: values))
    }
}
