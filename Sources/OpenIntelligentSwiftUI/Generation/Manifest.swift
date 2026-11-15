import Foundation

public struct IntelligentUIManifest: Codable, Sendable {
    public struct Component: Codable, Sendable {
        public let name: String
        public let rendering: String
        public let contract: String
    }
    /// Intelligent UI contract version, independent of the SDK Git revision and lang-core version.
    public let version: String
    public let profile: String
    /// Original upstream component/function source import revision.
    public let upstreamCommit: String
    /// Original OpenUI Swift source import revision, retained as historical metadata.
    /// The current bundled language core is identified by OpenUILang's core-manifest.json.
    public let runtimeCommit: String
    public let components: [Component]
    public let functions: [String]
    public let actions: [String]
    public let requirements: [String]
}

extension IntelligentUILibrary {
    public var manifest: IntelligentUIManifest {
        let web: Set<String> = ["HtmlView", "YouTube", "Svg", "Circle", "Ellipse", "Rect", "Line", "Path", "Polyline", "Polygon", "G", "SvgText", "Math"]
        return IntelligentUIManifest(version: "0.1.0-preview.29-design-revamp", profile: components.library.id ?? "swift-intelligent-ui.v0.1",
            upstreamCommit: "16ef26475999e3a021a50b1607a03717c0721255", runtimeCommit: "f3dfa1d0b479c131b6d4268e81961186f22ff09c",
            components: specification.components.map { .init(name: $0.name, rendering: web.contains($0.name) ? "local-webkit-or-embedded-media" : $0.name == "Map" ? "mapkit" : "swiftui", contract: $0.description) },
            functions: specification.functions.map(\.name), actions: specification.actions.map(\.name),
            requirements: [
                "iOS 16+ / macOS 13+; system text, controls and dynamic appearance.",
                "OpenUILang and OpenUICore are targets in the root Swift package, shared by both UI libraries. The official language core is pinned for build-time generation; its current identity is recorded in OpenUILang's bundled core-manifest.json.",
                "upstreamCommit and runtimeCommit record the original component and Swift source imports. They do not identify the current SDK checkout or bundled language core.",
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
