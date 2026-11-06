import Foundation
import OpenUILang

/// One supplied amount. Source scope is separate; no inference from links or legs.
struct PricePresentation {
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

    init(_ value: Value?) {
        note = Self.string(ValueReading.field(value, "priceNote"))
        legacyText = Self.string(ValueReading.field(value, "priceText"))
        let currency = Self.string(ValueReading.field(value, "currency"))
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
    private static func currencyPrefix(_ currency: String?) -> String {
        guard let code = currency?.uppercased(), !code.isEmpty else { return "" }
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
