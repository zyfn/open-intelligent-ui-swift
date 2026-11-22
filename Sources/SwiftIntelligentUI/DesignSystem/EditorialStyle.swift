import SwiftUI
import SwiftLang

struct EditorialContext: Equatable {
    var flowDepth = 0
    var cardDepth = 0
    var mediaRatio: CGFloat? = nil
}

enum EditorialMetrics {
    static let imageWidth: CGFloat = 116
    static let imageAspectRatio: CGFloat = 0.8
    static let minimumRowWidth: CGFloat = 260
}

extension EnvironmentValues {
    @Entry var openIntelligentUIEditorial = EditorialContext()
    @Entry var openIntelligentUIInlineContent = false
    @Entry var openIntelligentUIInteractiveContent = false
}

enum EditorialNode {
    static func kind(_ value: Value) -> String {
        if case .element(let element) = value { return element.typeName }
        return "Text"
    }
    static func media(_ value: Value) -> Bool {
        if kind(value) == "Image" || kind(value) == "SearchImage" { return true }
        guard kind(value) == "Box", case .array(let values) = ValueReading.field(value, "children"), values.count == 1 else { return false }
        return ["Image", "SearchImage"].contains(kind(values[0]))
    }

    /// Only unstyled, single-child wrappers are transparent to reading edges.
    /// Real surfaces and groups keep their own boundaries.
    static func readingEdge(_ value: Value, depth: Int = 0) -> Value {
        guard depth < 16, ["Col", "Box"].contains(kind(value)) else { return value }
        if kind(value) == "Box", ValueReading.field(value, "background") != nil || ValueReading.field(value, "border") == .boolean(true) || (ValueReading.number(ValueReading.field(value, "padding")) ?? 0) > 0 { return value }
        let children = ValueReading.array(ValueReading.field(value, "children"))
        guard children.count == 1 else { return value }
        return readingEdge(children[0], depth: depth + 1)
    }

}

enum InlineTypography {
    static func attributed(_ text: String, font: Font, emphasis: Font.Weight) -> AttributedString {
        var result = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        for run in result.runs {
            guard var intent = run.inlinePresentationIntent, intent.contains(.stronglyEmphasized) else { continue }
            intent.remove(.stronglyEmphasized)
            result[run.range].inlinePresentationIntent = intent
            result[run.range].font = font.weight(emphasis)
        }
        return result
    }
}

enum EditorialSpacing {
    static func section(_ theme: OpenIntelligentUITheme) -> CGFloat { theme.sectionSpacing + theme.spacingUnit }
    static func between(_ previous: Value, _ next: Value, opening: Bool = false, theme: OpenIntelligentUITheme, nested: Bool = false) -> CGFloat {
        // These are direct-sibling relationships in upstream flow.styles.ts
        // (c531b0d). A wrapper is a block, not an implicit media/text recipe.
        let before = EditorialNode.kind(previous), after = EditorialNode.kind(next)
        if before == "Caption" && after == "Title" { return theme.spacingUnit }
        let badgeRow = after == "Row" && ValueReading.array(ValueReading.field(next, "children")).contains { EditorialNode.kind($0) == "Badge" }
        if before == "Title" && (["Text", "Caption"].contains(after) || badgeRow) { return theme.innerSpacing }
        if before == "Title" || nested || (before == "Text" && after == "Text") { return theme.paragraphSpacing }
        return section(theme)
    }
}


enum EditorialRowMetrics {
    static func columns(width: CGFloat, preferred: CGFloat, gap: CGFloat) -> (image: CGFloat, text: CGFloat) {
        let width = max(1, width), gap = max(0, gap)
        let image = min(max(1, preferred), width * 0.34)
        return (image, max(1, width - image - gap))
    }
}

struct EditorialRowLayout: Layout {
    let preferredImageWidth: CGFloat
    let ratio: CGFloat
    let gap: CGFloat
    let rightToLeft: Bool
    var idealWidth: CGFloat = 280
    var mediaIndex = 0
    static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties(); properties.stackOrientation = .horizontal; return properties
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? idealWidth
        let columns = EditorialRowMetrics.columns(width: width, preferred: preferredImageWidth, gap: gap)
        let text = subviews.count > 1 ? subviews[1 - mediaIndex].sizeThatFits(.init(width: columns.text, height: nil)).height : 0
        return CGSize(width: width, height: max(columns.image / max(0.2, ratio), text))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let columns = EditorialRowMetrics.columns(width: bounds.width, preferred: preferredImageWidth, gap: gap)
        let imageOnRight = rightToLeft != (mediaIndex == 1)
        subviews[mediaIndex].place(at: CGPoint(x: imageOnRight ? bounds.maxX - columns.image : bounds.minX, y: bounds.minY), anchor: .topLeading, proposal: .init(width: columns.image, height: columns.image / max(0.2, ratio)))
        subviews[1 - mediaIndex].place(at: CGPoint(x: imageOnRight ? bounds.minX : bounds.minX + columns.image + gap, y: bounds.minY), anchor: .topLeading, proposal: .init(width: columns.text, height: bounds.height))
    }
}
