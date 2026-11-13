import Foundation

public struct IntelligentUIManifest: Codable, Sendable {
    public struct Component: Codable, Sendable {
        public let name: String
        public let rendering: String
        public let contract: String
    }
    public let version: String
    public let profile: String
    public let upstreamCommit: String
    public let runtimeCommit: String
    public let components: [Component]
    public let functions: [String]
    public let actions: [String]
    public let requirements: [String]
}

extension IntelligentUILibrary {
    public var manifest: IntelligentUIManifest {
        let web: Set<String> = ["HtmlView", "YouTube", "Svg", "Circle", "Ellipse", "Rect", "Line", "Path", "Polyline", "Polygon", "G", "SvgText", "Math"]
        return IntelligentUIManifest(version: "0.1.0-preview.28-design-system", profile: components.library.id ?? "swift-intelligent-ui.v0.1",
            upstreamCommit: "16ef26475999e3a021a50b1607a03717c0721255", runtimeCommit: "b8ea283916b9630ce8590338c8f8dc5b71fd75e4",
            components: specification.components.map { .init(name: $0.name, rendering: web.contains($0.name) ? "local-webkit-or-embedded-media" : $0.name == "Map" ? "mapkit" : "swiftui", contract: $0.description) },
            functions: specification.functions.map(\.name), actions: specification.actions.map(\.name),
            requirements: [
                "iOS 16+ / macOS 13+; system text, controls and dynamic appearance.",
                "OpenUI Swift is pinned to the remote 0.1.1-rc.20 revision; makeState uses the upstream default runtime configuration.",
                "SearchImage is registered only with an explicit caller service.",
                "Content and citations present caller-supplied facts; this library does not retrieve or invent them.",
                "TransportCard displays supplied local clock/date/zone and fare text; no inferred elapsed duration, through-ticket or total price.",
                "Map route connects supplied coordinates; it does not compute road directions.",
                "Map basemap and remote media depend on external network resources.",
                "HTML has no native bridge; inline scripts are isolated and network is restricted.",
                "Functions execute pinned upstream computation code in JavaScriptCore; JSON data values only.",
                "Point dimensions replace CSS lengths; semantic colors replace arbitrary CSS colors.",
                "New Image outputs use src/alt only; layout owns framing. Numeric optional fields in runtime schemas remain reader compatibility.",
                "This manifest describes implemented contracts, not exhaustive device or model acceptance."
            ])
    }
}
