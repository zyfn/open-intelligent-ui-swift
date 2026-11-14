import SwiftUI
import OpenUILang
import OpenSwiftUI

enum ProgressComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Progress", description: "Native progress indicator. Omitted value is indeterminate; supplied finite value/max gives progress, clamped to 0...max. max defaults to 1 and must be positive. label is optional. Only use measured progress; do not fabricate completion.", params: [Parameter.number("value", minimum: 0), Parameter.number("max", minimum: 0.000001), OpenUIParameter.string("label", required: false)]) { ProgressComponentView(context: $0) }
    }
}
enum ProgressReading {
    enum State: Equatable { case indeterminate, determinate(Double), invalid }
    static func state(value: Value?, maximum: Value?) -> State {
        let hasMaximum = maximum != nil && maximum != .undefined
        if hasMaximum, ValueReading.number(maximum).map({ $0 > 0 }) != true { return .invalid }
        guard let value, value != .undefined else { return .indeterminate }
        guard let number = ValueReading.number(value), number >= 0,
              let fraction = fraction(value: number, maximum: ValueReading.number(maximum)) else { return .invalid }
        return .determinate(fraction)
    }
    static func fraction(value: Double?, maximum: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        let maximum = maximum ?? 1
        guard maximum.isFinite, maximum > 0 else { return nil }
        return min(1, max(0, value / maximum))
    }
}
private struct ProgressComponentView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.locale) private var locale
    var body: some View {
        Group {
            switch ProgressReading.state(value: context.value("value"), maximum: context.value("max")) {
            case .determinate(let fraction):
                ProgressView(value: fraction) { if let label = context.string("label") { Text(label).font(theme.secondaryFont) } }
                    .progressViewStyle(.linear)
                    .accessibilityLabel(context.string("label") ?? SDKStrings.text("progress.label", locale: locale))
                    .accessibilityValue("\(Int(fraction * 100))%")
            case .indeterminate:
                if let label = context.string("label") { ProgressView(label).font(theme.secondaryFont) }
                else { ProgressView().accessibilityLabel(SDKStrings.text("progress.processing", locale: locale)) }
            case .invalid:
                VStack(alignment: .leading, spacing: theme.spacingUnit) {
                    if let label = context.string("label") { Text(label).font(theme.secondaryFont) }
                    Label(SDKStrings.text("progress.invalid", locale: locale), systemImage: "exclamationmark.circle")
                        .font(theme.captionFont).foregroundStyle(theme.danger)
                }
            }
        }.tint(theme.actionAccent)
    }
}
