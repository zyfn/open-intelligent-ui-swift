import SwiftUI
import OpenUILang
import OpenUICore

enum ColumnComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Col", description: "Vertical editorial flow following pinned upstream: root blocks use 24 points, nested flow 12, heading-to-text 8 and caption-to-heading 4. Prose-to-image uses 12 points; a figure-to-caption uses 8. Explicit gap overrides this in 4-point theme units. align defaults to start.", params: [
            OpenUIParameter.slot("children", required: true),
            Parameter.number("gap", minimum: 0, maximum: 24),
            OpenUIParameter.string("align", required: false, values: ["start", "center", "end", "stretch"])
        ]) { ColumnView(context: $0) }
    }
}

private struct ColumnView: View {
    let context: OpenUIComponentContext
    @EnvironmentObject private var state: OpenUIState
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.intelligentUIEditorial) private var editorial
    @Environment(\.intelligentUIReadingAnchors) private var readingAnchors
    @Environment(\.intelligentUIReadingDepth) private var readingDepth
    private var hasReadingTargets: Bool { readingAnchors && readingDepth == 0 }
    private var alignment: HorizontalAlignment {
        switch context.string("align") {
        case "center": return .center
        case "end": return .trailing
        default: return .leading
        }
    }
    var body: some View {
        let children = context.children()
        return VStack(alignment: alignment, spacing: 0) {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                context.render(child.value)
                    .environment(\.intelligentUIEditorial, childContext)
                    .environment(\.intelligentUIReadingDepth, readingDepth + 1)
                    .frame(maxWidth: context.string("align") == "stretch" ? .infinity : nil, alignment: .leading)
                    .intelligentUIReadingTarget(hasReadingTargets ? ReadingAnchor(state: state, child: child.id) : nil)
                    .padding(.top, index == 0 ? 0 : context.number("gap").map { CGFloat(min(24, max(0, $0))) * theme.spacingUnit }
                        ?? EditorialSpacing.between(children[index - 1].value, child.value, opening: index == 1, theme: theme, nested: editorial.flowDepth > 0 || editorial.cardDepth > 0))
            }
        }.intelligentUILayoutTrace("column", "count=\(children.count)")
    }
    private var childContext: EditorialContext {
        var value = editorial
        value.flowDepth += 1
        value.openingCardTitle = false; value.cardSubtitle = false
        return value
    }
}
