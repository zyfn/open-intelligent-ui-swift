// Native data projection and structural comparison, without schema validation.
import Foundation

public func jsonToValue(_ j: JSONValue) -> Value {
    switch j {
    case .string(let s): return .string(s)
    case .number(let n): return .number(n)
    case .boolean(let b): return .boolean(b)
    case .null: return .null
    case .array(let items): return .array(items.map(jsonToValue))
    case .object(let fields):
        return .object(fields.map { ObjectField(key: $0.key, value: jsonToValue($0.value)) })
    }
}


func jsonValuesEqual(_ a: JSONValue, _ b: JSONValue) -> Bool {
    switch (a, b) {
    case (.string(let x), .string(let y)): return jsStringEqual(x, y)
    case (.number(let x), .number(let y)): return x == y
    case (.boolean(let x), .boolean(let y)): return x == y
    case (.null, .null): return true
    case (.array(let x), .array(let y)):
        return x.count == y.count && zip(x, y).allSatisfy(jsonValuesEqual)
    case (.object(let x), .object(let y)):
        return x.count == y.count && zip(x, y).allSatisfy { jsStringEqual($0.key, $1.key) && jsonValuesEqual($0.value, $1.value) }
    default: return false
    }
}


func materializedToPlain(_ m: Materialized) -> Value? {
    switch m {
    case .stateDefault(let value): return value.value
    case .value(let v): return v
    case .null: return .null
    case .element: return nil // Unevaluated element has no plain Value form.
    case .array(let items):
        var out: [Value] = []
        for i in items { guard let v = materializedToPlain(i) else { return nil }; out.append(v) }
        return .array(out)
    case .object(let entries):
        var out: [ObjectField] = []
        for (k, v) in entries { guard let pv = materializedToPlain(v) else { return nil }; out.append(ObjectField(key: k, value: pv)) }
        return .object(out)
    case .expr: return nil
    }
}
