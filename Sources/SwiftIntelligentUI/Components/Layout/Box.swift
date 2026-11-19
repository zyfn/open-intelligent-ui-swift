import SwiftUI
import SwiftLang

enum BoxComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Box", description: "Container, direction col by default. gap uses theme units, padding defaults to 0, background clear, border false. Background roles muted/faint use a neutral surface; status background tokens use soft tints, while chart colors retain their paint. Prefer surface + ink with a status-colored accent; foreground must differ from the containing background and remain readable in light/dark. Width/height accept numbers, px, percentages of the offered size, and Dynamic Type-scaled em/rem. Unsupported viewport CSS expressions are not simulated. flex weights share free space in nonwrapping Row. align/justify control placement; wrap applies to row direction. Radius clips when supplied. CSS lengths are not supported.", params: [
            OpenUIParameter.slot("children"),
            OpenUIParameter.string("direction", required: false, values: ["row", "col"]),
            Parameter.number("gap", minimum: 0, maximum: 24), Parameter.number("padding", minimum: 0, maximum: 24),
            OpenUIParameter.string("background", required: false, values: Parameter.colors), Parameter.radius(),
            OpenUIParameter.flag("border"), Parameter.length("width"),
            Parameter.length("height"), Parameter.number("flex", minimum: 0, maximum: 1000),
            OpenUIParameter.string("align", required: false, values: ["start", "center", "end", "stretch"]),
            OpenUIParameter.string("justify", required: false, values: ["start", "center", "end", "between"]), OpenUIParameter.flag("wrap")
        ]) { BoxView(context: $0) }
    }
}

private struct BoxView: View {
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.openIntelligentUIContentBackground) private var contentBackground
    @Environment(\.openIntelligentUIEditorial) private var editorial
    @Environment(\.layoutDirection) private var direction
    @ScaledMetric(relativeTo: .body) private var fontUnit: CGFloat = 17
    private var radius: CGFloat { theme.radius(named: context.string("radius"), points: context.number("radius"), fallback: 0) }
    @ViewBuilder var body: some View {
        Group {
            if context.string("radius") != nil || context.number("radius") != nil { content.clipShape(RoundedRectangle(cornerRadius: radius)) }
            else { content }
        }.layoutValue(key: RowFlexWeight.self, value: CGFloat(min(1000, max(0, context.number("flex") ?? 0))))
    }
    private var content: some View {
        let isRow = context.string("direction") == "row"
        let gap = context.number("gap").map { CGFloat(min(24, max(0, $0))) * theme.spacingUnit } ?? (isRow ? theme.spacingUnit * 2 : 0)
        let cross = context.string("align") ?? (isRow ? "center" : "start")
        let justify = context.string("justify") ?? "start"
        let horizontal: HorizontalAlignment = cross == "end" ? .trailing : cross == "center" ? .center : .leading
        let layout = isRow ? AnyLayout(WrappingRowLayout(gap: gap, alignment: cross, justification: justify, wraps: context.flag("wrap") == true, rightToLeft: direction == .rightToLeft)) : AnyLayout(VStackLayout(alignment: horizontal, spacing: gap))
        return layout {
            let children = context.children()
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                context.render(child.value).frame(maxWidth: !isRow && cross == "stretch" ? .infinity : nil, alignment: .leading)
                    .environment(\.openIntelligentUIEditorial, flowContext(isRow))
                    .padding(.top, !isRow && context.number("gap") == nil && index > 0 ? EditorialSpacing.between(children[index - 1].value, child.value, theme: theme, nested: editorial.flowDepth > 0 || editorial.cardDepth > 0) : 0)
                    .layoutValue(key: RowFlexWeight.self, value: RowFlexRules.weight(child.value))
                    .layoutValue(key: RowDivider.self, value: EditorialNode.kind(child.value) == "Divider")
                if !isRow && justify == "between" && child.id != context.children().last?.id { Spacer(minLength: 0) }
            }
        }
        .padding(CGFloat(min(24, max(0, context.number("padding") ?? 0))) * theme.spacingUnit)
        .modifier(IntelligentUILengthModifier(width: IntelligentUILength.read(context.value("width")),
            height: IntelligentUILength.read(context.value("height")), fontUnit: fontUnit))
        .background(context.string("background").map { theme.backgroundColor($0) } ?? .clear)
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(context.flag("border") == true ? theme.fieldBorder : .clear))
        .environment(\.openIntelligentUIContentBackground, context.string("background").map { theme.backgroundColor($0) } ?? contentBackground ?? theme.canvas)
    }
    private func flowContext(_ row: Bool) -> EditorialContext {
        var value = editorial
        if !row { value.flowDepth += 1 }
        return value
    }
}
