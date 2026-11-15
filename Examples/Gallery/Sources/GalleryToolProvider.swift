import Foundation
import SwiftLang

/// Deterministic local transport for the query-chain diagnostic. No Agent,
/// credentials, remote requests or commerce operation is connected here.
actor GalleryToolProvider: ToolProvider {
    private var sequence = 0
    func callTool(name: OpenUIString, arguments: OpenUIObject) async throws -> Value {
        try await Task.sleep(nanoseconds: 180_000_000)
        switch name {
        case "gallery.seed":
            sequence += 1
            return .object([ObjectField(key: "value", value: .number(Double(sequence)))])
        case "gallery.details":
            let value = arguments["value"] ?? .null
            return .object([
                ObjectField(key: "value", value: value),
                ObjectField(key: "label", value: .string(OpenUIString("本地链路结果 " + toString(value).displayString)))
            ])
        default:
            throw ToolNotFoundError(toolName: name, availableTools: ["gallery.seed", "gallery.details"])
        }
    }
}
