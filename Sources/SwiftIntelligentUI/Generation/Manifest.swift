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
        return IntelligentUIManifest(version: "0.1.1-rc.21", profile: components.library.id ?? "swift-intelligent-ui.v0.1",
            upstreamCommit: "16ef26475999e3a021a50b1607a03717c0721255", runtimeCommit: "f3dfa1d0b479c131b6d4268e81961186f22ff09c",
            components: specification.components.map { .init(name: $0.name, rendering: web.contains($0.name) ? "local-webkit-or-embedded-media" : $0.name == "Map" ? "mapkit" : "swiftui", contract: $0.description) },
            functions: specification.functions.map(\.name), actions: specification.actions.map(\.name),
            requirements: [
                "iOS 16+ / macOS 13+; system text, controls and dynamic appearance.",
                "OpenUI Swift is included as workspace targets under OpenUI; runtimeCommit records imported source provenance. The official core is pinned for build-time generation; no external fork package is resolved.",
                "SearchImage is registered only with an explicit caller service.",
                "Content and citations present caller-supplied facts; this library does not retrieve or invent them.",
                "TransportCard displays supplied local clock/date/zone and fare text; no inferred elapsed duration, through-ticket or total price.",
                "Map route connects supplied coordinates; it does not compute road directions.",
                "Map basemap and remote media depend on external network resources.",
                "HTML has no native bridge; inline scripts are isolated and network is restricted.",
                "Functions execute pinned upstream computation code in JavaScriptCore; JSON data values only.",
                "Point dimensions replace CSS lengths; semantic colors replace arbitrary CSS colors.",
                "New Image outputs use src/alt only; writer definitions generate the spec and prompt together. Legacy presentation and priceText fields remain in the historical reader.",
                "Existing component names, positional parameters, bindings and reader schemas are retained. Visual defaults and invalid-value feedback are refined without a new language.",
                "Generation validation uses the advertised writer profile; historical validation keeps the complete reader. Presentation warnings are non-blocking.",
                "This manifest describes implemented contracts, not exhaustive device or model acceptance."
            ])
    }
}
