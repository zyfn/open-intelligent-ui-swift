import OpenUILang
import OpenSwiftUI

/// The writer is a projection of the existing reader definition. This changes
/// neither the language nor the native builder, and old messages keep the full
/// reader. These restrictions were already stated in the SDK's generation rules.
enum WriterContract {
    static func project(_ component: OpenUIComponent) -> OpenUIComponent {
        var definition = component.definition
        switch definition.name {
        case "Image":
            definition.params = definition.params.filter { ["src", "alt"].contains($0.name) }
        case "SearchImage":
            definition.params = definition.params.filter { $0.name == "query" }
        case "ProductCard", "TransportCard":
            definition.params = definition.params.map { original in
                var parameter = original
                parameter.schema = original.schema.map(withoutLegacyPrice)
                return parameter
            }
        default:
            break
        }
        return component.replacingDefinition(definition)
    }

    private static func withoutLegacyPrice(_ schema: JSONValue) -> JSONValue {
        switch schema {
        case .object(let fields):
            return .object(fields.map { field in
                if field.key == OpenUIString("properties"), case .object(let properties) = field.value {
                    return .init(key: field.key, value: .object(properties.filter {
                        $0.key != OpenUIString("priceText")
                    }.map { .init(key: $0.key, value: withoutLegacyPrice($0.value)) }))
                }
                if field.key == OpenUIString("required"), case .array(let required) = field.value {
                    return .init(key: field.key, value: .array(required.filter {
                        $0 != .string("priceText")
                    }))
                }
                return .init(key: field.key, value: withoutLegacyPrice(field.value))
            })
        case .array(let values):
            return .array(values.map(withoutLegacyPrice))
        default:
            return schema
        }
    }
}

