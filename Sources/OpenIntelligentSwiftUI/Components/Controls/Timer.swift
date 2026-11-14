import SwiftUI
import OpenUILang
import OpenUICore

private enum TimerMetrics {
    static let font: Font = .system(.largeTitle, design: .rounded)
}

enum TimerComponent {
    static var component: OpenUIComponent {
        var seconds = Parameter.number("seconds", minimum: 0); seconds.required = true; seconds.isBindable = true
        return OpenUIComponent(name: "Timer", description: "Visible countdown with start, pause and reset. Bind seconds to a number; reset restores the first started value. Stops when removed from view. Uses elapsed time rather than tick counts.", params: [seconds, OpenUIParameter.string("label", required: false)]) { TimerView(context: $0) }
    }
}
enum TimerReading {
    static func seconds(_ value: Value?) -> Double? {
        guard let value = ValueReading.number(value), value >= 0 else { return nil }
        return value
    }
    static func display(_ seconds: Double, locale: Locale = .current) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let raw = jsNumberString(seconds)
        // Avoid Int conversion of an unbounded source value. Sub-second scientific
        // notation remains explicit instead of pretending the countdown is zero.
        if raw.contains("e") || raw.contains("E") { return SDKStrings.text("controls.timer.seconds", locale: locale, raw) }
        let hours = jsNumberString(floor(seconds / 3600))
        let minutes = Int(floor(seconds.truncatingRemainder(dividingBy: 3600) / 60))
        let wholeSeconds = Int(floor(seconds.truncatingRemainder(dividingBy: 60)))
        let fraction = raw.firstIndex(of: ".").map { String(raw[$0...]) } ?? ""
        return (hours.count < 2 ? "0" + hours : hours) + String(format: ":%02d:%02d", minutes, wholeSeconds) + fraction
    }
    static func elapsed(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}

private struct TimerView: View {
    let context: OpenUIComponentContext
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var running = false
    @State private var initial: Double?
    private var seconds: Double? { TimerReading.seconds(context.binding("seconds")?.wrappedValue ?? context.value("seconds")) }
    private var canEdit: Bool { context.canInteract && context.binding("seconds") != nil }
    private var status: String {
        if seconds == nil { return SDKStrings.text("controls.timer.invalid", locale: locale) }
        if running { return SDKStrings.text("controls.timer.running", locale: locale) }
        if initial == nil { return SDKStrings.text("controls.timer.ready", locale: locale) }
        return seconds == 0 ? SDKStrings.text("controls.timer.finished", locale: locale) : SDKStrings.text("controls.timer.paused", locale: locale)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: theme.groupSpacing) {
            if let label = context.string("label") { Text(label).font(theme.titleFont) }
            if let seconds {
                Text(TimerReading.display(seconds, locale: locale))
                    .font(TimerMetrics.font).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(SDKStrings.text("controls.timer.remaining", locale: locale, jsNumberString(seconds)))
            }
            Text(status).font(theme.captionFont).foregroundStyle(seconds == nil ? theme.danger : theme.secondaryText)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: theme.innerSpacing) { controls }
                VStack(alignment: .leading, spacing: theme.innerSpacing) { controls }
            }.disabled(!canEdit)
        }
        .task(id: running) {
            guard running else { return }
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                guard canEdit, let remaining = seconds else { running = false; return }
                let now = clock.now
                let duration = last.duration(to: now)
                let elapsed = TimerReading.elapsed(duration)
                let whole = max(0, duration.components.seconds)
                if whole >= 1 || elapsed >= remaining {
                    let next = elapsed >= remaining ? 0 : max(0, remaining - Double(whole))
                    context.binding("seconds")?.wrappedValue = .number(next)
                    last = whole > 0 ? last.advanced(by: .seconds(whole)) : now
                    if next == 0 { running = false; return }
                }
            }
        }
        .onDisappear { running = false }
        .onChange(of: scenePhase) { if $0 != .active { running = false } }
    }
    @ViewBuilder private var controls: some View {
        Button {
            guard canEdit, let seconds, seconds > 0 else { return }
            if initial == nil { initial = seconds }
            running.toggle()
        } label: { Text(running ? SDKStrings.text("controls.timer.pause", locale: locale) : SDKStrings.text("controls.timer.start", locale: locale)).foregroundStyle(theme.actionForeground) }
        .buttonStyle(UpstreamButtonStyle(tint: theme.actionAccent))
        .disabled(seconds == nil || seconds == 0)
        Button(SDKStrings.text("controls.timer.reset", locale: locale)) {
            guard canEdit else { return }
            running = false
            if let initial { context.binding("seconds")?.wrappedValue = .number(initial) }
            initial = nil
        }
        .buttonStyle(UpstreamButtonStyle(variant: "outline", tint: theme.actionAccent))
        .disabled(initial == nil)
    }
}
