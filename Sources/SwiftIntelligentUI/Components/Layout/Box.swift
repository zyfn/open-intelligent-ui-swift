import SwiftUI
import SwiftLang

enum BoxComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Box", description: "Flex container, a column by default. Column alignment defaults to stretch; row alignment defaults to center. gap and padding use 4-point theme units. Background is clear and border false by default. Width/height accept numbers and supported CSS length strings. Explicit flex, including zero, takes priority over the main-axis size; without flex, a numeric width prevents shrinking. Rows apply the photo sizing rule. align/justify control cross/main-axis placement. wrap forms further rows, or further columns when height is definite. Radius clips when supplied.", params: [
            OpenUIParameter.slot("children"),
            OpenUIParameter.string("direction", required: false, values: ["row", "col"]),
            Parameter.number("gap"), Parameter.number("padding"),
            Parameter.color("background"), Parameter.radius(),
            OpenUIParameter.flag("border"), Parameter.length("width"),
            Parameter.length("height"), Parameter.number("flex"),
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
    @Environment(\.openIntelligentUIItemSizing) private var parentSizing
    @Environment(\.openIntelligentUIRowMediaAspectRatio) private var rowMediaRatio
    @Environment(\.openIntelligentUIViewportSize) private var viewport
    @Environment(\.multilineTextAlignment) private var inheritedTextAlignment
    @ScaledMetric(relativeTo: .body) private var fontUnit: CGFloat = 17
    private var radius: CGFloat { theme.radius(named: context.string("radius"), points: context.number("radius"), fallback: 0) }
    @ViewBuilder var body: some View {
        Group {
            if context.string("radius") != nil || context.number("radius") != nil { content.clipShape(RoundedRectangle(cornerRadius: radius)) }
            else { content }
        }.layoutValue(key: IntelligentUIFlexItemKey.self,
            value: IntelligentUIFlexItem.read(.element(context.element), theme: theme, fontUnit: fontUnit))
    }
    private var content: some View {
        let children = context.children()
        let isRow = context.string("direction") == "row"
        let directPhoto = isRow && RowMediaRules.hasDirectPhoto(children)
        let gap = directPhoto ? 16 : theme.spacing(context.number("gap"), fallback: isRow ? 2 : 0)
        let cross = directPhoto ? "start" : context.string("align") ?? (isRow ? "center" : "stretch")
        let justify = context.string("justify") ?? "start"
        let height = IntelligentUILength.read(context.value("height"))
        let definiteHeight = parentSizing.height == .allocated ? parentSizing.hasDefiniteHeight
            : parentSizing.height == .stretch || height?.isDefinite(parent: parentSizing.hasDefiniteHeight, viewport: viewport) == true
        let inset = theme.spacing(context.number("padding")) + (context.flag("border") == true ? 1 : 0)
        let textAlignment: TextAlignment = !isRow && cross == "center" ? .center
            : !isRow && cross == "end" ? .trailing : inheritedTextAlignment
        let childTheme = theme.onBackground(context.string("background"))
        let layout = isRow ? AnyLayout(WrappingRowLayout(gap: gap, alignment: cross, justification: justify,
            wraps: context.flag("wrap") == true, rightToLeft: direction == .rightToLeft,
            fillsHeight: definiteHeight, viewport: viewport))
            : AnyLayout(IntelligentUIColumnLayout(alignment: cross, justification: justify, gap: gap, wraps: context.flag("wrap") == true,
                boundedHeight: definiteHeight, rightToLeft: direction == .rightToLeft, viewport: viewport))
        return layout {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                let item = IntelligentUIFlexItem.read(child.value, theme: theme, fontUnit: fontUnit)
                let childSizing = IntelligentUIItemSizing.forChild(child.value,
                    width: isRow && item.isBox ? .allocated : !isRow && cross == "stretch" ? .stretch : .natural,
                    height: isRow ? (cross == "stretch" ? .stretch : .natural)
                        : (definiteHeight || item.grow != nil ? .allocated : .natural),
                    hasDefiniteHeight: definiteHeight)
                let mediaRatio: CGFloat? = isRow && item.media != .none ? 4.0 / 3.0
                    : !isRow && children.count == 1 && item.media == .direct ? rowMediaRatio : nil
                context.render(child.value)
                    .frame(maxWidth: !isRow && cross == "stretch" && !item.isBox ? .infinity : nil, alignment: .leading)
                    .environment(\.openIntelligentUIItemSizing, childSizing)
                    .environment(\.openIntelligentUIRowMediaAspectRatio, mediaRatio)
                    .environment(\.openIntelligentUIEditorial, flowContext(isRow))
                    .layoutValue(key: IntelligentUIFlexItemKey.self, value: item)
                    .layoutValue(key: ColumnGapBefore.self, value: index == 0 || isRow || context.number("gap") != nil ? 0
                        : EditorialSpacing.between(children[index - 1].value, child.value, theme: theme,
                            nested: editorial.flowDepth > 0))
                    .layoutValue(key: RowDivider.self, value: EditorialNode.kind(child.value) == "Divider")
            }
        }
        .environment(\.multilineTextAlignment, textAlignment)
        .environment(\.openIntelligentUITheme, childTheme)
        .foregroundStyle(childTheme.primaryText)
        .padding(inset)
        .modifier(IntelligentUILengthModifier(width: IntelligentUILength.read(context.value("width")),
            height: height, fontUnit: fontUnit, itemSizing: parentSizing,
            minimumSize: FlexGeometry.sum([inset, inset]), rightToLeft: direction == .rightToLeft))
        .background(context.string("background").map { theme.backgroundColor($0) } ?? .clear)
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(context.flag("border") == true ? theme.fieldBorder : .clear))
        .environment(\.openIntelligentUIContentBackground, context.string("background").map { theme.backgroundColor($0) } ?? contentBackground ?? theme.canvas)
    }
    private func flowContext(_ row: Bool) -> EditorialContext {
        var value = editorial
        if !row && context.number("gap") == nil { value.flowDepth += 1 }
        return value
    }
}
