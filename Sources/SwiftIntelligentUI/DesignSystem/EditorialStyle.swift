import SwiftUI
import SwiftLang

struct EditorialContext: Equatable {
    var flowDepth = 0
    var cardDepth = 0
    var mediaRatio: CGFloat? = nil
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

    static func isProse(_ value: Value) -> Bool {
        ["Text", "Title", "Caption", "Markdown", "Col", "ImageText"].contains(kind(readingEdge(value)))
    }

    static func isSourceParagraph(_ value: Value) -> Bool {
        guard kind(value) == "Text" else { return false }
        let segments = ValueReading.array(ValueReading.field(value, "text"))
        return segments.contains { kind($0) == "Citation" } && segments.allSatisfy {
            if case .string = $0 { return true }
            return kind($0) == "Citation"
        }
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
        let leading = EditorialNode.readingEdge(previous), trailing = EditorialNode.readingEdge(next)
        let before = EditorialNode.kind(leading), after = EditorialNode.kind(trailing)
        let figures = ["Image", "SearchImage", "Chart", "Table", "Svg", "YouTube", "Map", "Math", "HtmlView"]
        if ["Text", "Markdown"].contains(before) && figures.contains(after) { return theme.paragraphSpacing }
        if figures.contains(before) && (["Caption", "Citation"].contains(after) || EditorialNode.isSourceParagraph(trailing)) { return theme.innerSpacing }
        if before == "Caption" && after == "Title" { return theme.spacingUnit }
        let badgeRow = after == "Row" && ValueReading.array(ValueReading.field(trailing, "children")).contains { EditorialNode.kind($0) == "Badge" }
        if before == "Title" && (["Text", "Caption", "Markdown"].contains(after) || badgeRow) { return theme.innerSpacing }
        if before == "Title" || nested || (["Text", "Markdown"].contains(before) && ["Text", "Markdown"].contains(after)) { return theme.paragraphSpacing }
        return section(theme)
    }
}

