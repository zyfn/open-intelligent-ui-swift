import SwiftUI
import Foundation
import OpenUILang
import OpenUICore

enum CodeComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "Code", description: "Selectable monospaced code with syntax coloring for Swift, JS/TS, Python, JSON and shell. Unknown languages remain plain text. Copy dispatches CopyToClipboard to the host; long lines scroll horizontally.", params: [OpenUIParameter.string("code"), OpenUIParameter.string("language", required: false)]) {
            CodeBlockContent(context: $0, code: $0.string("code") ?? "", language: $0.string("language"))
        }
    }
    static func copyAction(_ code: String) -> ActionPlan {
        ActionPlan(steps: [.custom(name: "CopyToClipboard", args: [("text", .str(code))])])
    }
}

struct CodeBlockContent: View {
    @Environment(\.locale) private var locale
    let context: OpenUIComponentContext
    let code: String
    let language: String?
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.intelligentUIInteractiveContent) private var interactive
    @State private var expanded = false
    private var preview: CodePreview { CodePreview(code) }
    var body: some View {
        VStack(alignment: .leading, spacing: theme.innerSpacing) {
            HStack {
                if let language { Text(language).font(theme.captionFont).foregroundStyle(theme.secondaryText) }
                Spacer()
                IntelligentUIActionSurface(context: context, action: CodeComponent.copyAction(code), showsProgress: true) {
                    Label(SDKStrings.text("code.copy", locale: locale), systemImage: "doc.on.doc").font(theme.captionFont)
                        .frame(minHeight: theme.minimumControlHeight)
                }.buttonStyle(.borderless).tint(theme.actionAccent)
                    .accessibilityLabel(SDKStrings.text("code.copyAccessibility", locale: locale))
            }
            ScrollView(expanded && preview.isTruncated ? [.horizontal, .vertical] : [.horizontal]) {
                Text(CodeColoring.highlight(expanded ? code : preview.text, language: language, theme: theme))
                    .font(theme.codeFont).textSelection(.enabled).fixedSize()
            }.frame(maxHeight: expanded && preview.isTruncated ? 480 : nil)
            if preview.isTruncated {
                Button(SDKStrings.text(expanded ? "code.collapse" : "code.expand", locale: locale)) { expanded.toggle() }
                    .buttonStyle(.plain).font(theme.captionFont).underline()
                    .frame(minHeight: theme.minimumControlHeight, alignment: .leading)
                    .disabled(!context.canInteract || interactive)
                    .accessibilityHint(SDKStrings.text("code.fullCopyHint", locale: locale))
            }
        }
        .padding(theme.groupSpacing)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
    }
}

/// The collapsed preview never modifies the source sent to CopyToClipboard.
struct CodePreview {
    let text: String
    let isTruncated: Bool
    init(_ source: String, maximumLines: Int = 40, maximumCharacters: Int = 12_000) {
        var end = source.startIndex
        var lines = 1, characters = 0
        while end < source.endIndex && characters < maximumCharacters {
            if source[end] == "\n" {
                if lines >= maximumLines { break }
                lines += 1
            }
            characters += 1
            end = source.index(after: end)
        }
        text = String(source[..<end]); isTruncated = end < source.endIndex
    }
}

enum CodeColoring {
    static func highlight(_ source: String, language: String?, theme: IntelligentUITheme) -> AttributedString {
        var output = AttributedString(source)
        output.foregroundColor = theme.primaryText
        let language = language?.lowercased() ?? ""
        guard source.utf8.count <= 200_000, ["swift", "js", "javascript", "ts", "typescript", "python", "py", "json", "bash", "sh", "shell"].contains(language) else { return output }
        let comment = ["python", "py", "bash", "sh", "shell"].contains(language) ? #"#.*$"# : #"//[^\n]*|/\*[\s\S]*?\*/"#
        let literal = #"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'"#
        let keywords = #"\b(?:let|var|func|class|struct|enum|import|return|if|else|guard|for|while|switch|case|break|throw|throws|try|await|async|public|private|static|self|true|false|null|nil|const|function|export|from|def|in|as|None|True|False|print|echo|do|done|fi)\b"#
        let pattern = "(?m)(?<comment>" + comment + ")|(?<literal>" + literal + ")|(?<number>\\b\\d+(?:\\.\\d+)?\\b)|(?<keyword>" + keywords + ")"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return output }
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            let colors: [(String, Color)] = [("comment", theme.secondaryText), ("literal", theme.codeLiteral), ("number", theme.codeNumber), ("keyword", theme.codeKeyword)]
            for (name, color) in colors {
                guard let range = Range(match.range(withName: name), in: source),
                      let start = AttributedString.Index(range.lowerBound, within: output),
                      let end = AttributedString.Index(range.upperBound, within: output) else { continue }
                output[start..<end].foregroundColor = color
            }
        }
        return output
    }
}
