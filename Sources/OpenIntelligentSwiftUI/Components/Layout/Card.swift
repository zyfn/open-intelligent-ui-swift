import SwiftUI
import OpenUILang
import OpenUICore

enum CardComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Card", description: "A restrained content group. Single ProductCard/TransportCard children reuse their own surface; in Map the SDK summary card owns presentation instead of nested borders. variant defaults to outline; padding defaults to 16 points on iOS and 20 on macOS (16 when nested). Omitted gap uses nested editorial flow and contextual card typography. Explicit padding and gap use 4-point theme units, from 0 to 24.", params: [
            OpenUIParameter.slot("children", required: true),
            OpenUIParameter.string("variant", required: false, values: ["outline", "soft"]),
            Parameter.number("padding", minimum: 0, maximum: 24),
            Parameter.number("gap", minimum: 0, maximum: 24)
        ]) { context in
            CardView(context: context)
                .environment(\.openUIInteractionScopeReady, context.canInteract)
        }
    }
}

private struct CardView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.intelligentUIContentBackground) private var contentBackground
    @Environment(\.intelligentUIEditorial) private var editorial
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
        guard children.count == 1, case .element(let child) = children[0].value else { return false }
        return ["ProductCard", "TransportCard"].contains(child.typeName)
    }
    @ViewBuilder var body: some View {
        if ownsSurface {
            VStack(alignment: .leading, spacing: theme.innerSpacing) { context.slot() }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else { surface }
    }
    private var surface: some View {
        let children = context.children()
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                context.render(child.value)
                    .environment(\.intelligentUIEditorial, childContext(child.value, index: index, previous: index > 0 ? children[index - 1].value : nil))
                    .padding(.top, index == 0 ? 0 : context.number("gap").map { CGFloat(min(24, max(0, $0))) * theme.spacingUnit }
                        ?? EditorialSpacing.between(children[index - 1].value, child.value, theme: theme, nested: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(CGFloat(min(24, max(0, context.number("padding") ?? defaultPadding))) * theme.spacingUnit)
        .background(context.string("variant") == "soft" ? theme.surface : theme.canvas,
                    in: RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius)
            .strokeBorder(context.string("variant") == "soft" ? .clear : theme.fieldBorder))
        .environment(\.intelligentUIContentBackground, context.string("variant") == "soft" ? theme.surface : contentBackground ?? theme.canvas)
    }
    private func childContext(_ value: OpenUILang.Value, index: Int, previous: OpenUILang.Value?) -> EditorialContext {
        var result = editorial
        result.cardDepth += 1; result.compactContent = true
        result.openingCardTitle = index == 0 && EditorialNode.smallTitle(value)
        result.cardSubtitle = false
        return result
    }
}
