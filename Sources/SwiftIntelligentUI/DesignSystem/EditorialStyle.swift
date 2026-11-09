import SwiftUI
import OpenUILang

struct EditorialContext {
    var flowDepth = 0
    var cardDepth = 0
    var compactContent = false
    var openingCardTitle = false
    var cardSubtitle = false
    var mediaRatio: CGFloat? = nil
}

enum EditorialMetrics {
    static let imageWidth: CGFloat = 116
    static let imageAspectRatio: CGFloat = 0.8
    static let minimumRowWidth: CGFloat = 260
}

extension EnvironmentValues {
    @Entry var intelligentUIEditorial = EditorialContext()
    @Entry var intelligentUIInlineContent = false
    @Entry var intelligentUIInteractiveContent = false
}

enum EditorialNode {
    static func imageRatio(_ value: Value) -> CGFloat? {
        if let ratio = ValueReading.number(ValueReading.field(value, "aspectRatio")) { return CGFloat(min(5, max(0.2, ratio))) }
        if kind(value) == "Box", let image = ValueReading.array(ValueReading.field(value, "children")).first { return imageRatio(image) }
        return nil
    }
    static func kind(_ value: Value) -> String {
        if case .element(let element) = value { return element.typeName }
        return "Text"
    }
    static func smallTitle(_ value: Value) -> Bool {
        kind(value) == "Title" && ["", "sm", "md"].contains(ValueReading.string(ValueReading.field(value, "size")))
    }
    static func media(_ value: Value) -> Bool {
        if kind(value) == "Image" || kind(value) == "SearchImage" { return true }
        guard kind(value) == "Box", case .array(let values) = ValueReading.field(value, "children"), values.count == 1 else { return false }
        return ["Image", "SearchImage"].contains(kind(values[0]))
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
    static func between(_ previous: Value, _ next: Value, opening: Bool = false, theme: IntelligentUITheme, nested: Bool = false) -> CGFloat {
        func kind(_ value: Value) -> String {
            if case .element(let element) = value { return element.typeName }
            return "Text"
        }
        let before = kind(previous), after = kind(next)
        if ["Text", "Markdown"].contains(before) && ["Image", "SearchImage"].contains(after) { return theme.spacingUnit * 3 }
        if after == "Caption" && ["Image", "SearchImage", "Chart", "Table", "Svg"].contains(before) { return theme.innerSpacing }
        if before == "Caption" && after == "Title" { return theme.spacingUnit }
        let badgeRow = after == "Row" && ValueReading.array(ValueReading.field(next, "children")).contains { kind($0) == "Badge" }
        if before == "Title" && (["Text", "Caption"].contains(after) || badgeRow) { return theme.innerSpacing }
        if before == "Title" || nested || (before == "Text" && after == "Text") { return theme.spacingUnit * 3 }
        return theme.spacingUnit * 6
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
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? idealWidth
        let columns = EditorialRowMetrics.columns(width: width, preferred: preferredImageWidth, gap: gap)
        let text = subviews.count > 1 ? subviews[1].sizeThatFits(.init(width: columns.text, height: nil)).height : 0
        return CGSize(width: width, height: max(columns.image / max(0.2, ratio), text))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let columns = EditorialRowMetrics.columns(width: bounds.width, preferred: preferredImageWidth, gap: gap)
        subviews[0].place(at: CGPoint(x: rightToLeft ? bounds.maxX - columns.image : bounds.minX, y: bounds.minY), proposal: .init(width: columns.image, height: columns.image / max(0.2, ratio)))
        subviews[1].place(at: CGPoint(x: rightToLeft ? bounds.minX : bounds.minX + columns.image + gap, y: bounds.minY), proposal: .init(width: columns.text, height: bounds.height))
    }
}
