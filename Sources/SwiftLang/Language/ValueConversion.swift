// Native data projection and structural comparison, without schema validation.

extension Value {
    /// Source metadata belongs to a presentation snapshot, not Lang identity.
    /// The summaries on immutable containers make plain-data cache hits O(1).
    var containsSourceMetadata: Bool {
        switch self {
        case .element, .actionPlan: return true
        case .array(let values): return values.containsSourceMetadata
        case .object(let fields): return fields.containsSourceMetadata
        default: return false
        }
    }

    var referenceObject: AnyObject? {
        switch self {
        case .array(let value): return value
        case .object(let value): return value
        case .element(let value): return value
        case .actionPlan(let value): return value
        case .binding(let value), .reactiveBinding(let value): return value
        default: return nil
        }
    }

    /// A metadata-only re-projection is SameValue but is a new native snapshot.
    func isSameSnapshot(as other: Value) -> Bool {
        if let object = referenceObject { return other.referenceObject.map { object === $0 } ?? false }
        return self == other
    }
}

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
    case (.string(let x), .string(let y)): return x == y
    case (.number(let x), .number(let y)): return x == y
    case (.boolean(let x), .boolean(let y)): return x == y
    case (.null, .null): return true
    case (.array(let x), .array(let y)):
        return x.count == y.count && zip(x, y).allSatisfy(jsonValuesEqual)
    case (.object(let x), .object(let y)):
        return x.count == y.count && zip(x, y).allSatisfy { $0.key == $1.key && jsonValuesEqual($0.value, $1.value) }
    default: return false
    }
}
