import Foundation
import OpenUILang
import OpenUISwiftUI

/// Validation does not change parsing or rendering. Historical reading keeps
/// the full RC20-era contract; generation uses only the advertised writer.
public enum IntelligentUIValidationProfile: Sendable, Equatable {
    case historical
    case generation
}

extension IntelligentUILibrary {
    /// Combined source/runtime/schema check. Presentation warnings are intentionally separate.
    @MainActor public func validationIssues(in state: IntelligentUIState, source: String) -> [String] {
        validationIssues(in: state, source: source, profile: .historical)
    }

    @MainActor public func validationIssues(in state: IntelligentUIState, source: String,
                                           profile: IntelligentUIValidationProfile) -> [String] {
        var issues = sourceIssues(in: source) + state.errors.map { String(describing: $0) }
        guard let root = state.root else { return issues + ["program: missing evaluated root"] }
        if state.isComplete && !root.isSourceComplete {
            issues.append("program: unfinished or unresolved source remains after stream completion")
        }
        issues += validationIssues(in: root, profile: profile)
        return issues
    }

    /// Contract preflight for the pinned ASCII identifier grammar. Not a second parser.
    /// Quoted content is preserved, including non-ASCII labels and HTML/SVG strings.
    public func sourceIssues(in source: String) -> [String] {
        let text = Array(source.unicodeScalars)
        var index = 0, line = 1
        var quoted = false, escaped = false, lineComment = false, blockComment = false
        var reported = Set<Int>(), issues: [String] = []
        while index < text.count {
            let char = text[index], next = index + 1 < text.count ? text[index + 1] : nil
            if char == "\n" { line += 1; lineComment = false }
            if lineComment { index += 1; continue }
            if blockComment {
                if char == "*", next == "/" { blockComment = false; index += 2 } else { index += 1 }
                continue
            }
            if quoted {
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == "\"" { quoted = false }
                index += 1; continue
            }
            if char == "/", next == "/" { lineComment = true; index += 2; continue }
            if char == "/", next == "*" { blockComment = true; index += 2; continue }
            if char == "\"" { quoted = true; index += 1; continue }
            if char.value > 127, CharacterSet.alphanumerics.contains(char) || CharacterSet.nonBaseCharacters.contains(char), reported.insert(line).inserted {
                issues.append("source line \(line): non-ASCII code identifier; quote business field keys and use string bracket access instead of dot access")
            }
            index += 1
        }
        return issues
    }

    /// Conservative, non-blocking presentation diagnostics, not a measured contrast audit.
    /// Explicit paint remains untouched and strict schema validation is independent.
    public func presentationWarnings(in root: EvaluatedElement) -> [String] {
        let aliases = ["faint": "muted", "chart1": "info", "chart2": "success", "chart3": "purple", "chart4": "warning", "chart5": "pink", "chart6": "teal"]
        func token(_ value: Value?) -> String? {
            guard case .string(let text) = value else { return nil }
            return aliases[text.displayString] ?? text.displayString
        }
        var warnings: [String] = []
        func walk(_ value: Value, background: String?, path: String, depth: Int) {
            guard depth < 64 else { return }
            switch value {
            case .element(let element):
                func prop(_ key: String) -> Value? { element.props.last { $0.0 == key }?.1 }
                if ["Svg", "HtmlView", "YouTube", "Map"].contains(element.typeName) { return }
                var surface = background
                if element.typeName == "Card" { surface = nil }
                if ["Box", "Pressable"].contains(element.typeName), let own = token(prop("background")) {
                    let raw = ValueReading.string(prop("background"))
                    surface = ["info", "success", "warning", "danger", "purple", "pink"].contains(raw) ? "soft:" + own : own == "muted" ? "surface" : own
                }
                if ["Text", "Title", "Caption", "Label", "Icon", "Markdown", "Quote"].contains(element.typeName) {
                    let foreground = token(prop("color")) ?? (element.typeName == "Caption" ? "muted" : "ink")
                    if foreground == surface {
                        warnings.append(path + "." + element.typeName + ": foreground and containing background resolve to the same semantic color (" + foreground + ")")
                    }
                }
                for (key, child) in element.props { walk(child, background: surface, path: path + "." + key, depth: depth + 1) }
            case .array(let values):
                for (index, child) in values.enumerated() { walk(child, background: background, path: path + "[\(index)]", depth: depth + 1) }
            case .object(let object):
                for field in object.fields { walk(field.value, background: background, path: path + "." + field.key.displayString, depth: depth + 1) }
            default: break
            }
        }
        walk(.element(root), background: nil, path: "root", depth: 0)
        return warnings
    }

    /// Content checks supplement parser errors; consumers should also inspect OpenUIState.errors.
    public func validationIssues(in root: EvaluatedElement) -> [String] {
        validationIssues(in: root, profile: .historical)
    }

    public func validationIssues(in root: EvaluatedElement, profile: IntelligentUIValidationProfile) -> [String] {
        var issues = undeclaredFieldIssues(in: root, profile: profile)
        func visit(_ value: Value, path: String, depth: Int) {
            guard depth < 64 else { return }
            switch value {
            case .element(let element):
                if element.typeName == "Map" {
                    let markers = element.props.first { $0.0 == "markers" }?.1
                    if MapPoint.decode(markers).isEmpty { issues.append(path + ".Map.markers: at least one valid supplied place marker is required") }
                    let duplicates = MapPoint.duplicateLabels(markers)
                    if !duplicates.isEmpty { issues.append(path + ".Map.markers: duplicate labels cannot be selected independently: " + duplicates.joined(separator: ", ")) }
                }
                if ["ProductCard", "TransportCard"].contains(element.typeName) {
                    let key = element.typeName == "ProductCard" ? "product" : "journey"
                    if let price = ValueReading.field(element.props.first { $0.0 == key }?.1, "price"), !PricePresentation.valid(price) {
                        issues.append(path + "." + element.typeName + "." + key + ".price: use a nonnegative amount or currency/amount string only; put units/conditions in priceNote")
                    }
                }
                if element.typeName == "TransportCard", TransportData(element.props.first { $0.0 == "journey" }?.1) == nil { issues.append(path + ".TransportCard.journey: invalid route, time/date or connection data") }
                if element.typeName == "ProductCard", ProductCardData(element.props.first { $0.0 == "product" }?.1) == nil { issues.append(path + ".ProductCard.product: incomplete product data") }
                for (name, child) in element.props { visit(child, path: path + "." + name, depth: depth + 1) }
            case .array(let array): for (index, child) in array.enumerated() { visit(child, path: path + "[\(index)]", depth: depth + 1) }
            case .object(let object): for field in object.fields { visit(field.value, path: path + "." + field.key.displayString, depth: depth + 1) }
            default: break
            }
        }
        visit(.element(root), path: "root", depth: 0)
        return issues
    }

    /// Supplements runtime type/required checks with undeclared-object-field diagnostics.
    /// Reading keeps the complete schema so historical messages remain valid.
    public func undeclaredFieldIssues(in root: EvaluatedElement) -> [String] {
        undeclaredFieldIssues(in: root, profile: .historical)
    }

    public func undeclaredFieldIssues(in root: EvaluatedElement, profile: IntelligentUIValidationProfile) -> [String] {
        let catalog = profile == .generation ? components : readerComponents
        guard let data = catalog.toSpec().jsonString().data(using: .utf8),
              let spec = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schema = spec["schema"] as? [String: Any],
              let definitions = schema["$defs"] as? [String: Any] else { return ["Component schema could not be read"] }
        return FieldDiagnostics(definitions: definitions, componentNames: Set(catalog.library.components.map(\.name)))
            .inspect(.element(root), schema: [:], path: "root", depth: 0)
    }
}

private struct FieldDiagnostics {
    let definitions: [String: Any]
    let componentNames: Set<String>

    func inspect(_ value: Value, schema: [String: Any], path: String, depth: Int) -> [String] {
        guard depth < 64 else { return [path + ": object inspection depth exceeded"] }
        if case .element(let element) = value {
            guard componentNames.contains(element.typeName) else {
                return [path + "." + element.typeName + ": component is not available in this validation profile"]
            }
            let definition = definitions[element.typeName] as? [String: Any] ?? [:]
            return inspectFields(element.props, schema: definition, path: path + "." + element.typeName, depth: depth + 1)
        }
        if let reference = schema["$ref"] as? String, reference.hasPrefix("#/$defs/"), let definition = definitions[String(reference.dropFirst(8))] as? [String: Any] {
            return inspect(value, schema: definition, path: path, depth: depth + 1)
        }
        if let allowed = schema["enum"] as? [String], case .string(let text) = value,
           !allowed.contains(text.displayString) {
            return [path + ": invalid option; expected one of " + allowed.joined(separator: ", ")]
        }
        if let alternatives = schema["anyOf"] as? [[String: Any]] {
            let applicable = alternatives.filter { alternative in
                if alternative["$ref"] != nil { return true }
                switch value {
                case .object: return alternative["type"] as? String == "object"
                case .array: return alternative["type"] as? String == "array"
                default: return false
                }
            }
            if !applicable.isEmpty {
                return applicable.map { inspect(value, schema: $0, path: path, depth: depth + 1) }.min(by: { $0.count < $1.count }) ?? []
            }
        }
        switch value {
        case .object(let object):
            return inspectFields(object.fields.map { ($0.key.displayString, $0.value) }, schema: schema, path: path, depth: depth + 1)
        case .array(let values):
            let item = schema["items"] as? [String: Any] ?? [:]
            return values.enumerated().flatMap { inspect($0.element, schema: item, path: path + "[\($0.offset)]", depth: depth + 1) }
        default: return []
        }
    }

    private func inspectFields(_ fields: [(String, Value)], schema: [String: Any], path: String, depth: Int) -> [String] {
        let properties = schema["properties"] as? [String: Any] ?? [:]
        let strict = schema["additionalProperties"] as? Bool == false
        var issues: [String] = []
        for (key, value) in fields {
            // Reader evaluation may retain omitted optional fields as undefined.
            // They do not constitute arguments in a generated program.
            if case .undefined = value { continue }
            if strict && properties[key] == nil { issues.append(path + "." + key + ": undeclared field") }
            let child = properties[key] as? [String: Any] ?? schema["additionalProperties"] as? [String: Any] ?? [:]
            issues += inspect(value, schema: child, path: path + "." + key, depth: depth)
        }
        return issues
    }
}
