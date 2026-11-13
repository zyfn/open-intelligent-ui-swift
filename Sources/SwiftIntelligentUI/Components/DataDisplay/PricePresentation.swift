import Foundation
import OpenUILang

/// One supplied amount. Source scope is separate; no inference from links or legs.
struct PricePresentation {
    enum Diagnostic: Hashable {
        case grouping
        case currencyConflict(amount: String, field: String)
        case invalidCurrency(String)
        func message(locale: Locale) -> String {
            switch self {
            case .grouping: return SDKStrings.text("price.grouping_review", locale: locale)
            case .currencyConflict(let amount, let field):
                return SDKStrings.text("price.currency_conflict", locale: locale, amount, field)
            case .invalidCurrency(let code): return SDKStrings.text("price.currency_review", locale: locale, code)
            }
        }
    }
    static let missingLabel = "价格待补充"
    static let pattern = #"^(?:[A-Z]{3}\s*|HK\$|NT\$|US\$|CA\$|A\$|S\$|[¥￥$€£₩₹])?\d[\d,]*(?:\.\d+)?$"#
    static let schema: JSONValue = .object([.init(key: "anyOf", value: .array([
        .object([.init(key: "type", value: .string("number")), .init(key: "minimum", value: .number(0))]),
        .object([.init(key: "type", value: .string("string")), .init(key: "pattern", value: .string(OpenUIString(pattern)))])
    ]))])
    // Runtime reader compatibility; omitted from writer-facing declarations.
    static let legacySchema: JSONValue = .object([.init(key: "type", value: .string("string"))])
    let text: String?
    let note: String?
    let legacyText: String?
    let canonical: Bool
    let currencyCode: String?
    /// Display diagnostics preserve the historical reader and never repair an amount.
    let diagnostics: [Diagnostic]
    var displayText: String? {
        guard let text else { return nil }
        guard let currencyCode, !currencyCode.isEmpty else { return text }
        if let embedded = Self.embeddedCurrency(text), embedded != currencyCode {
            // Conflicting source fields are reported below, not silently reconciled.
            return text
        }
        if text.hasPrefix(currencyCode) { return text }
        return currencyCode + " " + text
    }
    func accessibilityText(locale: Locale = .current) -> String? {
        guard let displayText else { return nil }
        return ([displayText] + diagnostics.map { $0.message(locale: locale) }).joined(separator: ", ")
    }

    init(_ value: Value?) {
        note = Self.string(ValueReading.field(value, "priceNote"))
        legacyText = Self.string(ValueReading.field(value, "priceText"))
        let currency = Self.string(ValueReading.field(value, "currency"))
        currencyCode = Self.normalizedCurrencyCode(currency)
        if let price = ValueReading.field(value, "price"), price != .undefined {
            canonical = true
            switch price {
            case .number(let amount) where amount.isFinite && amount >= 0:
                text = Self.currencyPrefix(currency) + jsNumberString(amount)
            case .string(let raw):
                let cleaned = Self.cleanLegacy(raw.displayString)
                let numeric = cleaned.range(of: #"^\d[\d,]*(?:\.\d+)?$"#, options: .regularExpression) != nil
                text = cleaned.isEmpty ? nil : (numeric ? Self.currencyPrefix(currency) : "") + cleaned
            default: text = nil
            }
        } else {
            canonical = false
            text = legacyText.map(Self.cleanLegacy)
        }
        var diagnostics: [Diagnostic] = []
        if let text, text.contains(","), !Self.hasCanonicalGrouping(text) {
            diagnostics.append(.grouping)
        }
        if let currencyCode, let embedded = text.flatMap(Self.embeddedCurrency), embedded != currencyCode {
            diagnostics.append(.currencyConflict(amount: embedded, field: currencyCode))
        }
        if let currencyCode, currencyCode.range(of: "^[A-Z]{3}$", options: .regularExpression) == nil {
            diagnostics.append(.invalidCurrency(currencyCode))
        }
        self.diagnostics = diagnostics
    }
    static func hasCanonicalGrouping(_ text: String) -> Bool {
        let prefix = #"(?:[A-Z]{3}\s*|HK\$|NT\$|US\$|CA\$|A\$|S\$|[¥￥$€£₩₹])?"#
        return text.range(of: "^" + prefix + #"(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]+)?$"#, options: .regularExpression) != nil
    }
    private static func embeddedCurrency(_ text: String) -> String? {
        if let range = text.range(of: "^[A-Z]{3}(?=\\s|[0-9])", options: .regularExpression) { return String(text[range]) }
        let explicit = [("HK$", "HKD"), ("NT$", "TWD"), ("US$", "USD"), ("CA$", "CAD"), ("A$", "AUD"), ("S$", "SGD")]
        return explicit.first { text.hasPrefix($0.0) }?.1
    }
    static func valid(_ value: Value) -> Bool {
        switch value {
        case .null, .undefined: return true
        case .number(let n): return n.isFinite && n >= 0
        case .string(let s): return s.displayString.range(of: pattern, options: .regularExpression) != nil
        default: return false
        }
    }
    private static func string(_ value: Value?) -> String? {
        guard case .string(let value) = value, !value.displayString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value.displayString
    }
    private static func normalizedCurrencyCode(_ currency: String?) -> String? {
        guard let code = currency?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !code.isEmpty else { return nil }
        return code
    }
    private static func currencyPrefix(_ currency: String?) -> String {
        guard let code = normalizedCurrencyCode(currency) else { return "" }
        return ["CNY":"¥", "JPY":"¥", "USD":"$", "EUR":"€", "GBP":"£", "HKD":"HK$", "TWD":"NT$", "KRW":"₩", "INR":"₹"][code] ?? code + " "
    }
    private static func cleanLegacy(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["查询报价", "来源查询价", "来源报价", "报价快照"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "：:")))
            break
        }
        for suffix in ["（查询报价）", "（来源查询价）", "（来源报价）"] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return text.isEmpty ? raw : text
    }
}
