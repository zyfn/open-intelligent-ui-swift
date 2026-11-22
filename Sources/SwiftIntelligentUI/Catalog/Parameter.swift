import SwiftLang

enum Parameter {
    static let stringSchema: JSONValue = .object([.init(key: "type", value: .string("string"))])
    static let numberSchema: JSONValue = .object([.init(key: "type", value: .string("number"))])
    static let booleanSchema: JSONValue = .object([.init(key: "type", value: .string("boolean"))])
    static func objectSchema(_ fields: [(String, JSONValue)], required: [String]) -> JSONValue {
        .object([.init(key: "type", value: .string("object")),
                 .init(key: "properties", value: .object(fields.map { .init(key: OpenUIString($0.0), value: $0.1) })),
                 .init(key: "required", value: .array(required.map { .string(OpenUIString($0)) })),
                 .init(key: "additionalProperties", value: .boolean(false))])
    }
    static func arraySchema(_ item: JSONValue, minimum: Int = 0, maximum: Int = 200) -> JSONValue {
        .object([.init(key: "type", value: .string("array")), .init(key: "items", value: item),
                 .init(key: "minItems", value: .number(Double(minimum))), .init(key: "maxItems", value: .number(Double(maximum)))])
    }
    /// Upstream Color is a string, not an enumeration of theme tokens. Native
    /// rendering resolves tokens first and then checks supported CSS colors.
    static func color(_ name: String = "color", required: Bool = false) -> ParamDef {
        OpenUIParameter.string(name, required: required)
    }

    static func radius(_ name: String = "radius") -> ParamDef {
        ParamDef(name: name, required: false, schema: .object([
            .init(key: "anyOf", value: .array([
                .object([.init(key: "type", value: .string("string")),
                         .init(key: "enum", value: .array(["sm", "md", "lg", "xl", "full"].map { .string(OpenUIString($0)) }))]),
                .object([.init(key: "type", value: .string("number"))])
            ]))
        ]))
    }

    static func number(_ name: String, minimum: Double? = nil, maximum: Double? = nil) -> ParamDef {
        var fields = [JSONField(key: "type", value: .string("number"))]
        if let minimum { fields.append(.init(key: "minimum", value: .number(minimum))) }
        if let maximum { fields.append(.init(key: "maximum", value: .number(maximum))) }
        return ParamDef(name: name, required: false, schema: .object(fields))
    }

    static func length(_ name: String) -> ParamDef {
        ParamDef(name: name, required: false, schema: .object([
            .init(key: "type", value: .array([.string("number"), .string("string")]))
        ]))
    }

    static func boundBoolean(_ name: String) -> ParamDef {
        ParamDef(name: name, required: true, isBindable: true,
                 schema: .object([.init(key: "type", value: .string("boolean"))]))
    }
}
