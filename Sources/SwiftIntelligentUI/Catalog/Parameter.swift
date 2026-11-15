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
    static let colors = ["ink", "muted", "faint", "surface", "info", "success", "warning", "danger", "purple", "pink", "chart1", "chart2", "chart3", "chart4", "chart5", "chart6"]

    static func radius(_ name: String = "radius") -> ParamDef {
        ParamDef(name: name, required: false, schema: .object([
            .init(key: "anyOf", value: .array([
                .object([.init(key: "type", value: .string("string")),
                         .init(key: "enum", value: .array(["sm", "md", "lg", "xl", "full"].map { .string(OpenUIString($0)) }))]),
                .object([.init(key: "type", value: .string("number")), .init(key: "minimum", value: .number(0))])
            ]))
        ]))
    }

    static func number(_ name: String, minimum: Double? = nil, maximum: Double? = nil) -> ParamDef {
        var fields = [JSONField(key: "type", value: .string("number"))]
        if let minimum { fields.append(.init(key: "minimum", value: .number(minimum))) }
        if let maximum { fields.append(.init(key: "maximum", value: .number(maximum))) }
        return ParamDef(name: name, required: false, schema: .object(fields))
    }

    static func boundBoolean(_ name: String) -> ParamDef {
        ParamDef(name: name, required: true, isBindable: true,
                 schema: .object([.init(key: "type", value: .string("boolean"))]))
    }
}
