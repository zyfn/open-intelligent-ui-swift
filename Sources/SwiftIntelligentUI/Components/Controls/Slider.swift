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
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var direction
    private var current: Double? { ValueReading.number(context.binding("value")?.wrappedValue ?? context.value("value")) }
    private var canEdit: Bool { context.canInteract && context.binding("value") != nil }
    private func formatted(_ number: Double) -> String {
        let unit = context.string("unit") ?? ""
        let currency = ["$", "€", "£", "¥", "₹"].contains(String(unit.prefix(1)))
        return (currency ? unit : "") + jsNumberString(number) + (currency ? "" : unit)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: theme.innerSpacing) {
            if let range = SliderRange(minimum: context.number("min") ?? 0,
                                       maximum: context.number("max") ?? 100,
                                       step: context.number("step") ?? 1) {
                let valid = current.map { range.bounds.contains($0) } ?? false
                let projected = range.clamped(current ?? range.bounds.lowerBound)
                heading(current.map(formatted) ?? SDKStrings.text("controls.slider.unset", locale: locale))
                Slider(value: Binding(get: { projected }, set: { value in
                    guard canEdit else { return }
                    context.binding("value")?.wrappedValue = .number(value)
                }), in: range.bounds, step: range.step)
                .tint(theme.actionAccent)
                .accessibilityLabel(context.string("label") ?? SDKStrings.text("controls.slider.label", locale: locale))
                .accessibilityValue((current.map(formatted) ?? SDKStrings.text("controls.slider.no_selection", locale: locale)) + (valid ? "" : SDKStrings.text("controls.slider.outside_suffix", locale: locale)))
                .accessibilityHint(valid ? "" : SDKStrings.text("controls.slider.projection_hint", locale: locale))
                .accessibilityAdjustableAction { adjustment in
                    guard canEdit, let binding = context.binding("value") else { return }
                    switch adjustment {
                    case .increment: binding.wrappedValue = .number(range.clamped(projected + range.step))
                    case .decrement: binding.wrappedValue = .number(range.clamped(projected - range.step))
                    @unknown default: break
                    }
                }
                .disabled(!canEdit)
                if !valid {
                    Label(SDKStrings.text("controls.slider.range_message", locale: locale, formatted(range.bounds.lowerBound), formatted(range.bounds.upperBound)), systemImage: "exclamationmark.circle")
                        .font(theme.captionFont).foregroundStyle(theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    if canEdit {
                        Button(SDKStrings.text("controls.slider.use_value", locale: locale, formatted(projected))) { context.binding("value")?.wrappedValue = .number(projected) }
                            .buttonStyle(UpstreamButtonStyle(variant: "outline", tint: theme.actionAccent, size: "sm"))
                    }
                }
                let marks = ValueReading.array(context.value("marks")).compactMap { value -> (Double, Double, String)? in
                    guard let n = ValueReading.number(ValueReading.field(value, "value")), range.bounds.contains(n) else { return nil }
                    return ((n - range.bounds.lowerBound) / (range.bounds.upperBound - range.bounds.lowerBound), n, ValueReading.string(ValueReading.field(value, "label")))
                }
                if !marks.isEmpty {
                    SliderMarkLayout(positions: marks.map(\.0), rightToLeft: direction == .rightToLeft, gap: theme.innerSpacing) {
                        ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                            Text(mark.2).font(theme.captionFont).foregroundStyle(theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel(mark.2 + "，" + formatted(mark.1))
                        }
                    }
                }
            } else {
                Label(SDKStrings.text("controls.slider.invalid_range", locale: locale), systemImage: "exclamationmark.circle")
                    .font(theme.captionFont).foregroundStyle(theme.danger)
            }
        }
    }
    @ViewBuilder private func heading(_ value: String) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: theme.spacingUnit) { headingLabel; headingValue(value) }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { headingLabel; Spacer(minLength: theme.innerSpacing); headingValue(value).fixedSize() }
                VStack(alignment: .leading, spacing: theme.spacingUnit) { headingLabel; headingValue(value) }
            }
        }
    }
    @ViewBuilder private var headingLabel: some View {
        if let label = context.string("label"), !label.isEmpty { Text(label).font(theme.labelFont) }
    }
    private func headingValue(_ text: String) -> some View {
        Text(text).font(theme.secondaryFont).monospacedDigit().fixedSize(horizontal: false, vertical: true)
    }
}

/// Greedy lanes retain each mark's track position without overlapping labels.
/// A long label receives the container width and can wrap; no mark is discarded.
enum SliderMarkGeometry {
    static func frames(width: CGFloat, sizes: [CGSize], positions: [Double], rightToLeft: Bool, gap: CGFloat) -> [CGRect] {
        let width = max(1, width.isFinite ? width : 240)
        let fractions = sizes.indices.map { index -> CGFloat in
            let value = positions.indices.contains(index) ? min(1, max(0, positions[index])) : 0
            return CGFloat(rightToLeft ? 1 - value : value)
        }
        var rowEnds: [CGFloat] = [], rowHeights: [CGFloat] = []
        var rows = Array(repeating: 0, count: sizes.count), xs = Array(repeating: CGFloat(0), count: sizes.count)
        for index in sizes.indices.sorted(by: { fractions[$0] == fractions[$1] ? $0 < $1 : fractions[$0] < fractions[$1] }) {
            let itemWidth = min(width, max(0, sizes[index].width))
            let center = min(9, width / 2) + max(0, width - 18) * fractions[index]
            let x = max(0, min(width - itemWidth, center - itemWidth / 2))
            let row = rowEnds.firstIndex { $0 + gap <= x } ?? rowEnds.count
            if row == rowEnds.count { rowEnds.append(0); rowHeights.append(0) }
            rows[index] = row; xs[index] = x
            rowEnds[row] = x + itemWidth
            rowHeights[row] = max(rowHeights[row], sizes[index].height)
        }
        var tops: [CGFloat] = [], y: CGFloat = 0
        for height in rowHeights { tops.append(y); y += height + gap }
        return sizes.indices.map { index in
            CGRect(x: xs[index], y: tops[rows[index]], width: min(width, max(0, sizes[index].width)), height: sizes[index].height)
        }
    }
}

private struct SliderMarkLayout: Layout {
    let positions: [Double]
    let rightToLeft: Bool
    let gap: CGFloat
    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        SliderMarkGeometry.frames(width: width,
            sizes: subviews.map { $0.sizeThatFits(.init(width: width, height: nil)) },
            positions: positions, rightToLeft: rightToLeft, gap: gap)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 240
        return .init(width: width, height: frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(width: bounds.width, subviews: subviews)
        for index in subviews.indices {
            subviews[index].place(at: .init(x: bounds.minX + frames[index].minX, y: bounds.minY + frames[index].minY),
                                 anchor: .topLeading, proposal: .init(frames[index].size))
        }
    }
}
