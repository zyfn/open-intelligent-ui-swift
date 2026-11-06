import SwiftUI
import OpenUILang
import OpenUISwiftUI

enum SliderComponent {
    static var component: OpenUIComponent {
        var value = Parameter.number("value")
        value.required = true
        value.isBindable = true
        return OpenUIComponent(name: "Slider", description: "Numeric input. Defaults: min 0, max 100, step 1, empty label/unit. Bind value to edit it; literals are read-only. Invalid ranges/steps disable input. Marks in range appear as labeled reference values below the native slider. Currency units prefix the value.", params: [
            value, Parameter.number("min"), Parameter.number("max"), Parameter.number("step", minimum: 0),
            OpenUIParameter.string("label", required: false),
            OpenUIParameter.string("unit", required: false),
            Parameter.array("marks", items: .object([.init(key: "type", value: .string("object")), .init(key: "properties", value: .object([
                .init(key: "value", value: .object([.init(key: "type", value: .string("number"))])),
                .init(key: "label", value: .object([.init(key: "type", value: .string("string"))]))
            ])), .init(key: "required", value: .array([.string("value"), .string("label")]))]), required: false)
        ]) { SliderView(context: $0) }
    }
}

struct SliderRange: Equatable {
    let bounds: ClosedRange<Double>
    let step: Double

    init?(minimum: Double, maximum: Double, step: Double) {
        let width = maximum - minimum
        guard minimum.isFinite, maximum.isFinite, width.isFinite, width > 0,
              step.isFinite, step > 0, step <= width else { return nil }
        bounds = minimum...maximum
        self.step = step
    }

    func clamped(_ value: Double) -> Double {
        value.isFinite ? min(bounds.upperBound, max(bounds.lowerBound, value)) : bounds.lowerBound
    }
}

private struct SliderView: View {
    let context: OpenUIComponentContext
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.intelligentUITheme) private var theme
    private var current: Double {
        if case .number(let value) = context.binding("value")?.wrappedValue { return value }
        return context.number("value") ?? context.number("min") ?? 0
    }
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacingUnit * 2) {
            if let range = SliderRange(minimum: context.number("min") ?? 0,
                                       maximum: context.number("max") ?? 100,
                                       step: context.number("step") ?? 1) {
                let unit = context.string("unit") ?? ""
                let currency = ["$", "€", "£", "¥", "₹"].contains(String(unit.prefix(1)))
                if context.string("label") != nil || !unit.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text(context.string("label") ?? "").font(theme.secondaryFont)
                        Spacer(minLength: theme.innerSpacing)
                        Text((currency ? unit : "") + range.clamped(current).formatted() + (currency ? "" : unit))
                            .font(theme.captionFont.weight(.medium)).monospacedDigit()
                    }
                }
                Slider(value: Binding(get: { range.clamped(current) }, set: {
                    context.binding("value")?.wrappedValue = .number($0)
                }), in: range.bounds, step: range.step)
                .tint(theme.actionAccent)
                .accessibilityLabel(context.string("label") ?? "数值")
                .accessibilityValue((currency ? unit : "") + range.clamped(current).formatted() + (currency ? "" : unit))
                .accessibilityAdjustableAction { direction in
                    guard context.canInteract, let binding = context.binding("value") else { return }
                    switch direction {
                    case .increment: binding.wrappedValue = .number(range.clamped(current + range.step))
                    case .decrement: binding.wrappedValue = .number(range.clamped(current - range.step))
                    @unknown default: break
                    }
                }
                .disabled(!context.canInteract || context.binding("value") == nil)
                let marks = ValueReading.array(context.value("marks")).compactMap { value -> (Double, String)? in
                    guard let n = ValueReading.number(ValueReading.field(value, "value")), range.bounds.contains(n) else { return nil }
                    return ((n - range.bounds.lowerBound) / (range.bounds.upperBound - range.bounds.lowerBound), ValueReading.string(ValueReading.field(value, "label")))
                }
                if !marks.isEmpty {
                    SliderMarkLayout(positions: marks.map(\.0)) {
                        ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in Text(mark.1).font(theme.captionFont).foregroundStyle(theme.secondaryText) }
                    }.accessibilityHidden(true)
                }
            } else {
                Text("数值范围不可用").font(theme.captionFont).foregroundStyle(theme.secondaryText)
            }
        }
    }
}

private struct SliderMarkLayout: Layout {
    let positions: [Double]
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        .init(width: proposal.width ?? 240, height: subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let center = 9 + max(0, bounds.width - 18) * positions[index]
            let x = max(0, min(bounds.width - size.width, center - size.width / 2))
            subviews[index].place(at: .init(x: bounds.minX + x, y: bounds.minY), proposal: .init(size))
        }
    }
}
