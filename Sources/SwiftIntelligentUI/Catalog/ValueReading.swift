import SwiftLang

enum ValueReading {
    @MainActor static func boundString(_ context: OpenUIComponentContext, _ name: String) -> String? {
        if let binding = context.binding(name) { return string(binding.wrappedValue) }
        return context.string(name)
    }
    static func field(_ value: Value?, _ key: String) -> Value? {
        if case .object(let fields) = value { return fields[OpenUIString(key)] }
        if case .element(let element) = value { return element.props.last { $0.0 == key }?.1 }
        return nil
    }
    static func string(_ value: Value?) -> String {
        switch value {
        case .string(let s): return s.displayString
        case .number(let n) where n.isFinite: return jsNumberString(n)
        case .boolean(let b): return b ? "true" : "false"
        default: return ""
        }
    }
    static func array(_ value: Value?) -> [Value] {
        if case .array(let a) = value { return a.values }; return []
    }
    static func number(_ value: Value?) -> Double? {
        if case .number(let n) = value, n.isFinite { return n }; return nil
    }
}

extension Parameter {
    static func array(_ name: String, items: JSONValue = .object([]), required: Bool = true) -> ParamDef {
        ParamDef(name: name, required: required, schema: .object([
            .init(key: "type", value: .string("array")), .init(key: "items", value: items)
        ]))
    }
    static func textOrChildren(_ name: String, required: Bool = true) -> ParamDef {
        ParamDef(name: name, required: required, schema: .object([
            .init(key: "anyOf", value: .array([
                .object([.init(key: "type", value: .string("string"))]),
                .object([.init(key: "type", value: .string("array")), .init(key: "items", value: .object([]))])
            ]))
        ]))
    }
}
