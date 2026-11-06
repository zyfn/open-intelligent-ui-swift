import SwiftUI

/// Keep Markdown emphasis consistent with the theme instead of allowing Text
/// to promote every strongly-emphasized run to the platform's bold face.
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
