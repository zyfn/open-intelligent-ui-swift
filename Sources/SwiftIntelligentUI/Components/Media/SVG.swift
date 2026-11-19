import SwiftUI
import Foundation
import SwiftLang

enum SVGComponents {
    static var components: [OpenUIComponent] {
        let paint: [ParamDef] = [OpenUIParameter.string("fill", required: false), OpenUIParameter.string("stroke", required: false), Parameter.number("strokeWidth", minimum: 0), Parameter.number("opacity", minimum: 0, maximum: 1)]
        func numbers(_ names: [String]) -> [ParamDef] { names.map { var p = Parameter.number($0); p.required = true; return p } }
        let paintNames = ["Circle", "Ellipse", "Rect", "Line", "Path", "Polyline", "Polygon", "SvgText"]
        let shapes: [(String, [ParamDef])] = [
            ("Svg", [OpenUIParameter.slot("children", required: true, accepting: paintNames + ["G"]), OpenUIParameter.string("viewBox"), OpenUIParameter.string("label", required: false), Parameter.length("width"), Parameter.length("height")]),
            ("Circle", numbers(["cx", "cy", "r"]) + paint),
            ("Ellipse", numbers(["cx", "cy", "rx", "ry"]) + paint),
            ("Rect", numbers(["x", "y", "width", "height"]) + paint + [Parameter.number("rx", minimum: 0)]),
            ("Line", numbers(["x1", "y1", "x2", "y2"]) + [OpenUIParameter.string("stroke", required: false), Parameter.number("strokeWidth", minimum: 0), Parameter.number("opacity", minimum: 0, maximum: 1)]),
            ("Path", [OpenUIParameter.string("d")] + paint),
            ("Polyline", [OpenUIParameter.string("points"), OpenUIParameter.string("fill", required: false), OpenUIParameter.string("stroke", required: false), Parameter.number("strokeWidth", minimum: 0), Parameter.number("opacity", minimum: 0, maximum: 1)]),
            ("Polygon", [OpenUIParameter.string("points")] + paint),
            ("G", [OpenUIParameter.slot("children", required: true, accepting: paintNames), OpenUIParameter.string("transform", required: false), Parameter.number("opacity", minimum: 0, maximum: 1)]),
            ("SvgText", [OpenUIParameter.string("text")] + numbers(["x", "y"]) + [Parameter.number("size", minimum: 0), OpenUIParameter.string("fill", required: false), OpenUIParameter.string("anchor", required: false, values: ["start", "middle", "end"]), OpenUIParameter.string("weight", required: false, values: ["normal", "medium", "semibold"])])
        ]
        return shapes.map { name, params in
            let detail = name == "Svg" ? " viewBox defines drawing coordinates; displayed width/height can scale the whole diagram. Keep essential labels at least about 14 display points on phones; put detailed/accessibility explanations in native text outside the drawing." : name == "SvgText" ? " size is in viewBox units, not guaranteed display points: size * displayedWidth / viewBoxWidth estimates the rendered size when width-constrained. Avoid tiny labels; text does not independently grow with Dynamic Type." : ""
            return OpenUIComponent(name: name, description: "SVG drawing element rendered in a script-free local WebKit bridge. Numeric attributes use drawing coordinates; shapes accept finite values and safe paint/transform attributes only." + detail, params: params) { context in
                SVGView(context: context)
            }
        }
    }
}

enum SVGMarkup {
    enum Failure: Error {
        case invalid(String), budget
        func message(locale: Locale) -> String {
            switch self {
            case .invalid(let field):
                let name = field == "type" ? SDKStrings.text("svg.field.type", locale: locale)
                    : field == "children" ? SDKStrings.text("svg.field.children", locale: locale) : field
                return SDKStrings.text("svg.invalid.field", locale: locale, name)
            case .budget: return SDKStrings.text("svg.limit", locale: locale)
            }
        }
    }
    struct Document { let markup: String; let labels: [String] }
    private struct Budget {
        var nodes = 0, bytes = 0, commands = 0, points = 0
        var fragments: [String] = [], labels: [String] = []
        mutating func append(_ text: String) throws {
            bytes += text.utf8.count
            guard bytes <= 512 * 1024 else { throw Failure.budget }
            fragments.append(text)
        }
    }
    static let semanticColors = ["ink", "muted", "faint", "surface", "info", "success", "warning", "danger", "purple", "pink"]
        + (1...6).map { "chart\($0)" }
    private static let names = ["Svg": "svg", "Circle": "circle", "Ellipse": "ellipse", "Rect": "rect", "Line": "line", "Path": "path", "Polyline": "polyline", "Polygon": "polygon", "G": "g", "SvgText": "text"]
    private static let numberPattern = #"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?"#

    /// Kept for callers of the existing internal sanitizer. The view uses the throwing document API.
    static func render(_ element: EvaluatedElement, depth: Int = 0) -> String {
        (try? document(element, depth: depth).markup) ?? ""
    }
    static func document(_ element: EvaluatedElement, palette: [String: String] = [:], depth: Int = 0) throws -> Document {
        var budget = Budget()
        try write(element, palette: palette, depth: depth, budget: &budget)
        return Document(markup: budget.fragments.joined(), labels: budget.labels)
    }
    static func viewBox(_ text: String) throws -> [Double] {
        guard text.count < 20_000 else { throw Failure.budget }
        let values = try text.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map { token -> Double in
            guard let value = Double(token), value.isFinite, abs(value) <= 10_000_000 else { throw Failure.invalid("viewBox") }
            return value
        }
        guard values.count == 4, values[2] > 0, values[3] > 0 else { throw Failure.invalid("viewBox") }
        return values
    }
    private static func write(_ element: EvaluatedElement, palette: [String: String], depth: Int, budget: inout Budget) throws {
        budget.nodes += 1
        guard depth < 64, budget.nodes <= 4096 else { throw Failure.budget }
        guard let tag = names[element.typeName] else { throw Failure.invalid("type") }
        func value(_ key: String) -> Value? { element.props.last { $0.0 == key }?.1 }
        var attrs: [String] = []
        for key in ["cx", "cy", "r", "rx", "ry", "x", "y", "width", "height", "x1", "x2", "y1", "y2", "strokeWidth", "opacity", "size"] {
            guard let number = ValueReading.number(value(key)) else { continue }
            guard abs(number) <= 10_000_000 else { throw Failure.invalid(key) }
            if ["r", "rx", "ry", "width", "height", "strokeWidth", "size"].contains(key), number < 0 { throw Failure.invalid(key) }
            let name = key == "strokeWidth" ? "stroke-width" : key == "size" ? "font-size" : key
            attrs.append("\(name)=\"\(key == "opacity" ? min(1, max(0, number)) : number)\"")
        }
        let filled = ["Circle", "Ellipse", "Rect", "Polygon", "SvgText"].contains(element.typeName) || value("fill") != nil
        if tag != "svg" && tag != "g" {
            attrs.append("fill=\"\(paint(ValueReading.string(value("fill")), palette: palette) ?? (filled && value("stroke") == nil ? "currentColor" : "none"))\"")
            if let stroke = paint(ValueReading.string(value("stroke")), palette: palette) { attrs.append("stroke=\"\(stroke)\"") }
            else if !filled {
                attrs.append("stroke=\"currentColor\"")
                if value("strokeWidth") == nil { attrs.append("stroke-width=\"2\"") }
            }
        }
        if tag == "svg" {
            let source = ValueReading.string(value("viewBox"))
            let box = try viewBox(source.isEmpty ? "0 0 100 100" : source)
            attrs.append("viewBox=\"\(box.map { String($0) }.joined(separator: " "))\"")
            attrs.append("xmlns=\"http://www.w3.org/2000/svg\" preserveAspectRatio=\"xMidYMid meet\" style=\"width:100%;height:100%\"")
        }
        if tag == "polyline" || tag == "polygon" {
            let source = ValueReading.string(value("points"))
            let coordinates = try numbers(source, field: "points")
            guard !coordinates.isEmpty, coordinates.count.isMultiple(of: 2) else { throw Failure.invalid("points") }
            budget.points += coordinates.count / 2
            guard budget.points <= 32_768 else { throw Failure.budget }
            attrs.append("points=\"\(XMLText.escape(source))\"")
        }
        if tag == "path" {
            let source = ValueReading.string(value("d"))
            budget.commands += try pathCommandCount(source)
            guard budget.commands <= 8192 else { throw Failure.budget }
            attrs.append("d=\"\(XMLText.escape(source))\"")
        }
        if tag == "g" {
            let source = ValueReading.string(value("transform"))
            if !source.isEmpty {
                try validateTransform(source)
                attrs.append("transform=\"\(XMLText.escape(source))\"")
            }
        }
        if ["start", "middle", "end"].contains(ValueReading.string(value("anchor"))) { attrs.append("text-anchor=\"\(ValueReading.string(value("anchor")))\"") }
        let weight = ValueReading.string(value("weight"))
        if ["normal", "medium", "semibold"].contains(weight) { attrs.append("font-weight=\"\(weight == "semibold" ? 600 : weight == "medium" ? 500 : 400)\"") }
        try budget.append("<\(tag) \(attrs.joined(separator: " "))>")
        if tag == "text" {
            let text = ValueReading.string(value("text"))
            guard text.utf8.count <= 32_768 else { throw Failure.budget }
            try budget.append(XMLText.escape(text))
            if !text.isEmpty { budget.labels.append(text) }
        } else {
            for child in ValueReading.array(value("children")) {
                guard case .element(let child) = child else { throw Failure.invalid("children") }
                try write(child, palette: palette, depth: depth + 1, budget: &budget)
            }
        }
        try budget.append("</\(tag)>")
    }
    static func paint(_ text: String, palette: [String: String] = [:]) -> String? {
        if semanticColors.contains(text) { return palette[text] ?? "currentColor" }
        guard !text.isEmpty, text.count < 20_000,
              text.range(of: #"^(#[0-9a-fA-F]{3}|#[0-9a-fA-F]{4}|#[0-9a-fA-F]{6}|#[0-9a-fA-F]{8}|[a-zA-Z]+|rgba?\([\d\s,.%]+\)|hsla?\([\d\s,.%]+\))$"#, options: .regularExpression) != nil else { return nil }
        return XMLText.escape(text)
    }
    private static func tokens(_ text: String, pattern: String, field: String) throws -> [String] {
        guard text.count < 20_000 else { throw Failure.budget }
        let regex = try NSRegularExpression(pattern: pattern)
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        var end = 0, result: [String] = []
        for match in matches {
            let separator = source.substring(with: NSRange(location: end, length: match.range.location - end))
            guard separator.allSatisfy({ $0.isWhitespace || $0 == "," }) else { throw Failure.invalid(field) }
            result.append(source.substring(with: match.range)); end = NSMaxRange(match.range)
        }
        guard source.substring(from: end).allSatisfy({ $0.isWhitespace || $0 == "," }) else { throw Failure.invalid(field) }
        return result
    }
    private static func numbers(_ text: String, field: String) throws -> [Double] {
        try tokens(text, pattern: numberPattern, field: field).map {
            guard let number = Double($0), number.isFinite, abs(number) <= 10_000_000 else { throw Failure.invalid(field) }
            return number
        }
    }
    private static func pathCommandCount(_ text: String) throws -> Int {
        guard text.count < 20_000 else { throw Failure.budget }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 0 }
        // SVG has compact arc flags and implicit commands. Keep its grammar in WebKit;
        // this layer only limits work and excludes markup/resource-bearing characters.
        guard text.range(of: #"^[MmLlHhVvCcSsQqTtAaZz\d\s,.eE+\-]+$"#, options: .regularExpression) != nil else { throw Failure.invalid("path") }
        let regex = try NSRegularExpression(pattern: "[MmLlHhVvCcSsQqTtAaZz]|" + numberPattern)
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
    private static func validateTransform(_ text: String) throws {
        guard text.count < 20_000 else { throw Failure.budget }
        let regex = try NSRegularExpression(pattern: #"(translate|rotate|scale|skewX|skewY|matrix)\s*\(([^)]*)\)"#)
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty, matches.count <= 128 else { throw Failure.invalid("transform") }
        var end = 0
        for match in matches {
            guard source.substring(with: NSRange(location: end, length: match.range.location - end)).allSatisfy({ $0.isWhitespace || $0 == "," }) else { throw Failure.invalid("transform") }
            let name = source.substring(with: match.range(at: 1))
            let values = try numbers(source.substring(with: match.range(at: 2)), field: "transform")
            let allowed = name == "matrix" ? [6] : name == "rotate" ? [1, 3] : ["translate", "scale"].contains(name) ? [1, 2] : [1]
            guard allowed.contains(values.count) else { throw Failure.invalid("transform") }
            end = NSMaxRange(match.range)
        }
        guard source.substring(from: end).allSatisfy({ $0.isWhitespace || $0 == "," }) else { throw Failure.invalid("transform") }
    }
}

private struct SVGView: View {
    @Environment(\.locale) private var locale
    let context: OpenUIComponentContext
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var fontUnit: CGFloat = 17
    private var height: CGFloat {
        let requested = IntelligentUILength.read(context.value("height"))?.resolve(relativeTo: nil, em: fontUnit)
        return min(2400, max(40, requested ?? 240))
    }
    private var document: Result<SVGMarkup.Document, Error> {
        Result {
            let palette = Dictionary(uniqueKeysWithValues: SVGMarkup.semanticColors.map {
                ($0, BridgeColor.css(theme.textColor($0), dark: colorScheme == .dark))
            })
            return try OpenIntelligentUIPerformance.measure("svg.markup") { try SVGMarkup.document(context.element, palette: palette) }
        }
    }
    var body: some View {
        Group {
            if !context.element.isSourceComplete {
                placeholder(status: "svg.preparing")
            } else {
                switch document {
                case .success(let document):
                    let source = context.element.typeName == "Svg" ? document.markup
                        : "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\" style=\"width:100%;height:100%\">\(document.markup)</svg>"
                    VStack(alignment: .leading, spacing: theme.innerSpacing) {
                        GeometryReader { geometry in
                            let preferred = IntelligentUILength.read(context.value("width"))?.resolve(relativeTo: geometry.size.width, em: fontUnit)
                            WebContent(context: context, content: source, height: height)
                                .frame(width: min(geometry.size.width, preferred ?? geometry.size.width))
                                .frame(maxWidth: .infinity)
                        }.frame(height: height)
                        if typeSize.isAccessibilitySize, !document.labels.isEmpty {
                            Text(document.labels.joined(separator: " · ")).font(theme.bodyFont).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityLabel(context.string("label") ?? (document.labels.isEmpty ? SDKStrings.text("svg.label", locale: locale) : SDKStrings.text("svg.label_details", locale: locale, document.labels.joined(separator: " · "))))
                case .failure:
                    placeholder(status: "svg.failed")
                }
            }
        }
    }

    private func placeholder(status: String) -> some View {
        theme.surface.overlay {
            Image(systemName: "square.on.circle")
                .font(.title3).foregroundStyle(theme.secondaryText.opacity(0.35))
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(context.string("label") ?? SDKStrings.text("svg.label", locale: locale))
        .accessibilityValue(SDKStrings.text(status, locale: locale))
    }
}
