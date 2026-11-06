import SwiftUI
import OpenUILang
import OpenUISwiftUI

enum TimerComponent {
    static var component: OpenUIComponent {
        var seconds = Parameter.number("seconds", minimum: 0); seconds.required = true; seconds.isBindable = true
        return OpenUIComponent(name: "Timer", description: "Visible countdown with start, pause and reset. Bind seconds to a number; reset restores the first started value. Stops when removed from view. Uses elapsed time rather than tick counts.", params: [seconds, OpenUIParameter.string("label", required: false)]) { TimerView(context: $0) }
    }
}
private struct TimerView: View {
    let context: OpenUIComponentContext
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.intelligentUITheme) private var theme
    @State private var running = false
    @State private var initial: Double?
    private var seconds: Double { max(0, min(31_536_000, ValueReading.number(context.binding("seconds")?.wrappedValue ?? context.value("seconds")) ?? 0)) }
    var body: some View {
        VStack(alignment: .leading, spacing: theme.groupSpacing) {
            if let label = context.string("label") { Text(label).font(theme.titleFont) }
            Text(String(format: "%02d:%02d:%02d", Int(seconds) / 3600, (Int(seconds) / 60) % 60, Int(seconds) % 60))
                .font(theme.timerFont).monospacedDigit().accessibilityLabel("剩余 \(Int(seconds)) 秒")
            HStack {
                Button {
                    if initial == nil { initial = seconds }
                    running.toggle()
                } label: { Text(running ? "暂停" : "开始").foregroundStyle(theme.actionForeground) }
                .buttonStyle(.borderedProminent).tint(theme.actionAccent).disabled(seconds <= 0)
                Button("重置") {
                    running = false
                    if let initial { context.binding("seconds")?.wrappedValue = .number(initial) }
                    initial = nil
                }.buttonStyle(.bordered).tint(theme.actionAccent).disabled(initial == nil)
            }.disabled(!context.canInteract || context.binding("seconds") == nil)
        }
        .task(id: running) {
            guard running else { return }
            var last = Date()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                guard context.canInteract else { running = false; return }
                let now = Date(), elapsed = floor(now.timeIntervalSince(last))
                if elapsed >= 1 {
                    let next = max(0, seconds - elapsed)
                    context.binding("seconds")?.wrappedValue = .number(next)
                    last = last.addingTimeInterval(elapsed)
                    if next == 0 { running = false; return }
                }
            }
        }.onDisappear { running = false }
    }
}
