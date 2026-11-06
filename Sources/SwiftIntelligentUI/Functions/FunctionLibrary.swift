import Foundation
import JavaScriptCore
import OpenUILang

/// Only fixed, bundled computation code executes here. Lang stays in OpenUI Swift.
final class FunctionLibrary: @unchecked Sendable {
    enum Failure: Error { case missingResource, invalidResource, unsupportedValue, oversizedValue }
    private let context: JSContext
    private let lock = NSRecursiveLock()
    private let fixedNow: Date?

    init(fixedNow: Date? = nil) throws {
        guard let context = JSContext(), let url = Bundle.module.url(forResource: "functions", withExtension: "js") else { throw Failure.missingResource }
        self.context = context; self.fixedNow = fixedNow
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        guard context.exception == nil, context.objectForKeyedSubscript("iuiCall")?.isObject == true else { throw Failure.invalidResource }
    }

    func definitions() throws -> [DefinedFunction] {
        guard let url = Bundle.module.url(forResource: "functions", withExtension: "json") else { throw Failure.missingResource }
        let json = try parseJSONPreservingOrder(String(contentsOf: url, encoding: .utf8))
        let registered = Set(context.objectForKeyedSubscript("iuiFunctionNames")?.toArray() as? [String] ?? [])
        let fields = json.objectFields ?? []
        guard registered == Set(fields.map { $0.0 }) else { throw Failure.invalidResource }
        return try fields.map { name, entry in
            guard let parameters = entry.field("params"), let properties = parameters.field("properties")?.objectFields else { throw Failure.invalidResource }
            let required = parameters.field("required")?.arrayItems?.compactMap(\.stringValue) ?? []
            var description = name == "Allocate"
                ? "Splits the total in proportion to weights at decimals precision (default 2). The parts sum to the total rounded to that precision, not an unrounded input. Uses largest remainders with stable tie order."
                : entry.field("description")?.stringValue ?? ""
            if name == "FormatDate" { description += " Named date/time styles use English; no locale argument is supported. Use iso for a language-neutral date in non-English UI." }
            if name == "Plural" { description += " Default pluralization is English. For Chinese units use concatenation or explicitly pass the same unit as plural, e.g. @Plural(2, \"人\", \"人\")." }
            return DefinedFunction(name: name,
                                   description: description + " Uses JSON data values; native component/action values are not accepted.",
                                   params: properties.map { ParamDef(name: $0.0, required: required.contains($0.0), schema: $0.1) },
                                   returns: entry.field("returns")) { [self] args in try call(name, args) }
        }
    }

    func call(_ name: String, _ args: [String: Value]) throws -> Value {
        let fields = try args.filter { $0.value != .undefined }.map { JSONField(key: OpenUIString($0.key), value: try Self.json($0.value)) }
        let encoded = JSONValue.object(fields).jsonString()
        guard encoded.utf8.count <= 2_000_000 else { throw Failure.oversizedValue }
        lock.lock(); defer { lock.unlock() }
        context.exception = nil
        let result = context.objectForKeyedSubscript("iuiCall")?.call(withArguments: [name, encoded, fixedNow.map { $0.timeIntervalSince1970 * 1000 } as Any? ?? NSNull()])
        guard context.exception == nil, let output = result?.toString(), output.utf8.count <= 4_000_000 else { throw Failure.invalidResource }
        return Self.value(try parseJSONPreservingOrder(output))
    }

    private static func json(_ value: Value, depth: Int = 0) throws -> JSONValue {
        guard depth < 64 else { throw Failure.oversizedValue }
        switch value {
        case .string(let text): return .string(text)
        case .number(let number): return number.isFinite ? .number(number) : .null
        case .boolean(let flag): return .boolean(flag)
        case .null, .undefined: return .null
        case .array(let array): return .array(try array.map { try json($0, depth: depth + 1) })
        case .object(let object): return .object(try object.fields.filter { $0.value != .undefined }.map { .init(key: $0.key, value: try json($0.value, depth: depth + 1)) })
        default: throw Failure.unsupportedValue
        }
    }
    private static func value(_ json: JSONValue) -> Value {
        switch json {
        case .string(let s): return .string(s)
        case .number(let n): return .number(n)
        case .boolean(let b): return .boolean(b)
        case .null: return .null
        case .array(let a): return .array(OpenUIArray(a.map(value)))
        case .object(let o): return .object(OpenUIObject(o.map { ObjectField(key: $0.key, value: value($0.value)) }))
        }
    }
}
