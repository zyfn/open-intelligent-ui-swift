import SwiftLang
import SwiftUI

private struct OpenUICardMediaInsetKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    var openUICardMediaInset: CGFloat {
        get { self[OpenUICardMediaInsetKey.self] }
        set { self[OpenUICardMediaInsetKey.self] = newValue }
    }
}

/// Dedicated object cards may extend header media to their top corners.
/// Standard Card never supplies this treatment; its images keep their own radius.
struct NativeCardTopMediaShape: Shape {
    let radius: CGFloat
    var topOnly = false
    func path(in rect: CGRect) -> Path {
        var path = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        if topOnly { path.addRect(CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2)) }
        return path
    }
}

struct OpenUIStyledCard: View {
    let context: OpenUIComponentContext

    var body: some View {
        OpenUIStack(context: context)
            .environment(\.openUICardMediaInset, 0)
            .modifier(OpenUIStandardCardSurface(theme: context.theme, variant: context.string("variant"),
                active: context.layoutConfigurationReady))
    }
}

/// The standard Card box includes its border even when that border is transparent.
/// Its zero content flex basis and these physical insets share the same geometry.
struct OpenUIStandardCardSurface: ViewModifier {
    let theme: OpenUIThemeValues
    let variant: String?
    var active = true
    @Environment(\.openUIPresentation) private var presentation
    @Environment(\.openUIAncestorLayoutReady) private var parentLayoutReady

    private static func resolvedBorderWidth(_ width: CGFloat) -> CGFloat {
        width.isFinite ? max(0, width) : 0
    }

    static func insets(theme: OpenUIThemeValues, variant: String?, borderWidth: CGFloat) -> EdgeInsets {
        let surface = NativeContentSurface(variant, fallback: .card)
        let border = resolvedBorderWidth(borderWidth)
        let horizontal = surface == .card ? 0 : theme.spaceL
        let vertical = surface == .sunk ? theme.spaceL : 0
        return EdgeInsets(top: vertical + border, leading: horizontal + border,
            bottom: vertical + border, trailing: horizontal + border)
    }

    func body(content: Content) -> some View {
        let surface = NativeContentSurface(variant, fallback: .card)
        let ready = active && parentLayoutReady
        let borderWidth = ready ? Self.resolvedBorderWidth(presentation.borderWidth) : 0
        let insets = ready ? Self.insets(theme: theme, variant: variant, borderWidth: borderWidth) : EdgeInsets()
        let radius = surface == .card ? 0 : theme.radius3xl
        let fill: Color = !ready || surface == .clear ? .clear
            : surface == .sunk ? theme.sunk : presentation.cardBackgroundColor
        let border: Color = !ready || surface == .clear ? .clear
            : surface == .sunk ? theme.borderDefault : presentation.cardBorderColor ?? .clear
        content.environment(\.openUIActionDensity, .compact)
            .padding(insets)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Paint the box without clipping its descendants or changing their
            // identity. Images and controls continue to own their own corners.
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .openUIShadow(ready && surface == .sunk ? theme.shadowM : OpenUIShadow(), cornerRadius: radius)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: borderWidth)
                    .allowsHitTesting(false)
            }
    }
}

/// Form panels and Carousel items have their own surface contract.
struct OpenUICardSurface: ViewModifier {
    let theme: OpenUIThemeValues
    let variant: String?
    var active = true
    @Environment(\.openUIAncestorLayoutReady) private var parentLayoutReady

    static func insets(theme: OpenUIThemeValues, variant: String?) -> EdgeInsets {
        if NativeContentSurface(variant, fallback: .card) == .clear {
            return EdgeInsets()
        }
        let inset = theme.componentStyle.panelInset
        return EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset)
    }

    func body(content: Content) -> some View {
        let surface = NativeContentSurface(variant, fallback: .card)
        let ready = active && parentLayoutReady
        let insets = ready ? Self.insets(theme: theme, variant: variant) : EdgeInsets()
        content.environment(\.openUIActionDensity, .compact)
            .padding(insets)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Background and media own their corners; the open container must
            // not mask glyphs at the edge of its unpadded content.
            .modifier(NativeCardSurface(
                theme: theme,
                fill: ready ? surface.fill(theme) : .clear,
                bordered: ready && surface.bordered))
    }
}

private struct OpenUIStretchHeightKey: EnvironmentKey { static let defaultValue = false }
private struct OpenUIControlWidthKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var openUIFillControlWidth: Bool {
        get { self[OpenUIControlWidthKey.self] }
        set { self[OpenUIControlWidthKey.self] = newValue }
    }
    var openUIStretchHeight: Bool {
        get { self[OpenUIStretchHeightKey.self] }
        set { self[OpenUIStretchHeightKey.self] = newValue }
    }
}

struct OpenUIStack: View {
    @Environment(\.openUIMediaWidthReady) private var parentMediaWidthReady
    @Environment(\.openUIAncestorLayoutReady) private var parentLayoutReady
    @Environment(\.openUICardMediaInset) private var cardMediaInset
    let context: OpenUIComponentContext
    // Upstream Stack normalizes wrapped space-between; upstream Card does not.
    var wrapJustifyBetweenAsStart = false
    private var layoutReady: Bool { parentLayoutReady && context.layoutConfigurationReady }
    private var direction: String { layoutReady ? context.string("direction") ?? "column" : "column" }
    private var gap: CGFloat { layoutReady ? context.theme.spacing(context.string("gap")) : context.theme.spaceM }
    private var projection: (value: Value, blocked: Bool) {
        let value = context.presentationValue()
        return layoutReady ? (value, false) : NativeLayoutContract.readingPrefix(value)
    }
    private var children: [OpenUIRenderChild] {
        OpenUIRenderChild.children(of: projection.value, registry: context.registry)
    }

    var body: some View {
        let mediaWidthReady = parentMediaWidthReady && layoutReady && (direction != "row" || context.rowWidthReady)
        let content = children
        let first = content.first?.id
        OpenUIFlexLayout(
            direction: direction, gap: gap,
            align: layoutReady ? context.string("align") ?? "stretch" : "stretch",
            justify: layoutReady ? context.string("justify") ?? "start" : "start",
            wrap: layoutReady && context.flag("wrap") == true, fillsHeight: layoutReady && context.stretchesVertically,
            wrapJustifyBetweenAsStart: wrapJustifyBetweenAsStart
        ) {
            ForEach(content) { child in
                renderChild(child)
                    .environment(\.openUICardMediaInset,
                        layoutReady && direction == "column" && child.id == first ? cardMediaInset : 0)
                    .environment(\.openUIAncestorLayoutReady, layoutReady)
                    // Unknown siblings can still change the whole row's width
                    // allocation. Once all flexible item roles are known, copy
                    // can grow independently inside their stable columns.
                    .environment(\.openUIMediaWidthReady,
                        mediaWidthReady)
                    .environment(\.openUIFillControlWidth,
                        direction == "column" && stretches)
                    .environment(\.openUIStretchHeight, direction == "row" && stretches)
            }
            // Keep source/layout diagnostics on the runtime. Once generation
            // stops, readable prose must not gain a generic diagnostic footer.
            // Empty surfaces and actual data failures still need local feedback.
            if !layoutReady && (projection.blocked || content.isEmpty),
               context.isStreaming || context.hasPendingData || context.hasDataFailure || content.isEmpty {
                NativePendingContent(loading: !context.hasDataFailure && (context.isStreaming || context.hasPendingData),
                    terminalMessage: context.hasDataFailure ? "Content unavailable" : nil)
            }
        }
    }

    @ViewBuilder private func renderChild(_ child: OpenUIRenderChild) -> some View {
        if case .element(let element) = child.value,
           let contract = context.registry.presentationValue(element.typeName, NativeFlexItemKey.self) {
            let width = contract.minimumOuterWidth(element, context.theme, context.presentation)
            // The parent owns allocation at its direct child boundary, outside
            // the dynamic renderer. Replaced renderers keep their own contract.
            context.render(child.value)
                .layoutValue(key: OpenUIFlexGrowKey.self, value: true)
                .layoutValue(key: OpenUIFlexMinimumWidthKey.self,
                    value: max(0, width.isFinite ? width : 0))
        } else {
            context.render(child.value)
        }
    }
    private var stretches: Bool { !layoutReady || context.string("align") == nil || context.string("align") == "stretch" }
}

struct NativeContentImage: View {
    let context: OpenUIComponentContext
    @Environment(\.openUICardMediaInset) private var cardMediaInset
    var body: some View {
        NativeRemoteImage(src: context.string("src"), alt: context.string("alt") ?? "",
            layout: .cover)
            // Suggest a media width when a row measures its children. Grid card
            // widths are unrelated; the parent still controls the final width.
            // Standard Image uses the shared native cover role.
            .frame(idealWidth: context.presentation.thumbnailSize)
            .clipShape(NativeCardTopMediaShape(radius: cardMediaInset > 0 ? context.theme.radius3xl : context.theme.radiusM,
                topOnly: cardMediaInset > 0))
            .padding(.horizontal, -cardMediaInset)
            .padding(.top, -cardMediaInset)
    }
}
