import SwiftUI
import SwiftLang

enum ColumnComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Col", description: "Vertical flex flow. Cross-axis alignment defaults to stretch. Without gap, direct sibling content follows the editorial spacing rules; explicit gap uses 4-point theme units. Box flex distributes vertical free space when an ancestor establishes a finite height. Ordinary message columns keep natural height.", params: [
            OpenUIParameter.slot("children", required: true), Parameter.number("gap"),
            OpenUIParameter.string("align", required: false, values: ["start", "center", "end", "stretch"])
        ]) { ColumnView(context: $0) }
    }
}

private struct ColumnView: View {
    let context: OpenUIComponentContext
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.openIntelligentUIEditorial) private var editorial
    @Environment(\.openIntelligentUIReadingAnchors) private var readingAnchors
    @Environment(\.openIntelligentUIReadingDepth) private var readingDepth
    @Environment(\.openIntelligentUIItemSizing) private var parentSizing
    @Environment(\.openIntelligentUIViewportSize) private var viewport
    @Environment(\.layoutDirection) private var direction
    @Environment(\.multilineTextAlignment) private var inheritedTextAlignment
    @ScaledMetric(relativeTo: .body) private var fontUnit: CGFloat = 17
    private var hasReadingTargets: Bool { readingAnchors && readingDepth == 0 }

    var body: some View {
        let children = context.children()
        let alignment = context.string("align") ?? "stretch"
        let boundedHeight = parentSizing.height != .natural
        let textAlignment: TextAlignment = alignment == "center" ? .center : alignment == "end" ? .trailing : inheritedTextAlignment
        return IntelligentUIColumnLayout(alignment: alignment, gap: theme.spacing(context.number("gap")), boundedHeight: boundedHeight,
            rightToLeft: direction == .rightToLeft, viewport: viewport) {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                let item = IntelligentUIFlexItem.read(child.value, theme: theme, fontUnit: fontUnit)
                context.render(child.value)
                    .environment(\.openIntelligentUIEditorial, childContext)
                    .environment(\.openIntelligentUIReadingDepth, readingDepth + 1)
                    .environment(\.openIntelligentUIItemSizing, IntelligentUIItemSizing.forChild(child.value,
                        width: alignment == "stretch" ? .stretch : .natural,
                        height: boundedHeight || item.grow != nil ? .allocated : .natural,
                        hasDefiniteHeight: boundedHeight))
                    .environment(\.openIntelligentUIRowMediaAspectRatio, nil)
                    .frame(maxWidth: alignment == "stretch" && !item.isBox ? .infinity : nil, alignment: .leading)
                    .openIntelligentUIReadingTarget(hasReadingTargets ? ReadingAnchor(state: state, child: child.id) : nil)
                    .layoutValue(key: IntelligentUIFlexItemKey.self, value: item)
                    .layoutValue(key: ColumnGapBefore.self, value: index == 0 || context.number("gap") != nil ? 0
                        : EditorialSpacing.between(children[index - 1].value, child.value, opening: index == 1, theme: theme,
                            nested: editorial.flowDepth > 0))
            }
        }
        .environment(\.multilineTextAlignment, textAlignment)
        .modifier(IntelligentUILengthModifier(width: nil, height: nil, fontUnit: fontUnit,
            itemSizing: parentSizing, rightToLeft: direction == .rightToLeft))
        .openIntelligentUILayoutTrace("column", "count=\(children.count)")
    }
    private var childContext: EditorialContext {
        var value = editorial
        if context.number("gap") == nil { value.flowDepth += 1 }
        return value
    }
}
