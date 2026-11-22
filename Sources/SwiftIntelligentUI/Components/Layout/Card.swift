import SwiftUI
import SwiftLang

enum CardComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Card", description: "A restrained content group. A single ProductCard child reuses its own surface. variant defaults to outline; padding defaults to 16 points on iOS and 20 on macOS (16 when nested). Omitted gap uses nested editorial flow; text keeps its declared role. Explicit padding and gap use 4-point theme units; negative values become zero.", params: [
            OpenUIParameter.slot("children", required: true),
            OpenUIParameter.string("variant", required: false, values: ["outline", "soft"]),
            Parameter.number("gap"),
            Parameter.number("padding")
        ]) { context in
            CardView(context: context)
        }
    }
}

private struct CardView: View {
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.openIntelligentUIContentBackground) private var contentBackground
    @Environment(\.openIntelligentUIEditorial) private var editorial
    private var radius: CGFloat { editorial.cardDepth > 0 ? theme.nestedContentCardRadius : theme.contentCardRadius }
    private var defaultPadding: Double {
        #if os(macOS)
        editorial.cardDepth > 0 ? 4 : 5
        #else
        4
        #endif
    }
    private var ownsSurface: Bool {
        let children = context.children()
        guard children.count == 1 else { return false }
        let content = EditorialNode.readingEdge(children[0].value)
        return EditorialNode.kind(content) == "ProductCard"
    }
    @ViewBuilder var body: some View {
        Group {
            if ownsSurface {
                VStack(alignment: .leading, spacing: theme.innerSpacing) { context.slot() }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else { surface }
        }
        .environment(\.openUIInteractionScopeReady, context.canInteract)
    }
    private var surface: some View {
        let children = context.children()
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                context.render(child.value)
                    .environment(\.openIntelligentUIEditorial, childContext)
                    .padding(.top, index == 0 ? 0 : context.number("gap").map { theme.spacing($0) }
                        ?? EditorialSpacing.between(children[index - 1].value, child.value, theme: theme, nested: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(theme.spacing(context.number("padding"), fallback: CGFloat(defaultPadding)))
        .background(context.string("variant") == "soft" ? theme.surface : theme.canvas,
                    in: RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius)
            .strokeBorder(context.string("variant") == "soft" ? .clear : theme.fieldBorder))
        .environment(\.openIntelligentUIContentBackground, context.string("variant") == "soft" ? theme.surface : contentBackground ?? theme.canvas)
    }
    private var childContext: EditorialContext {
        var result = editorial
        result.cardDepth += 1
        if context.number("gap") == nil { result.flowDepth += 1 }
        return result
    }
}
