import Foundation

public struct OpenIntelligentUIManifest: Codable, Sendable {
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
    /// The current bundled language core is identified by SwiftLang's core-manifest.json.
    public let runtimeCommit: String
    public let components: [Component]
    public let functions: [String]
    public let actions: [String]
    public let requirements: [String]
}

extension OpenIntelligentUIComponents {
    public var manifest: OpenIntelligentUIManifest {
        let web: Set<String> = ["HtmlView", "YouTube", "Svg", "Circle", "Ellipse", "Rect", "Line", "Path", "Polyline", "Polygon", "G", "SvgText", "Math"]
        return OpenIntelligentUIManifest(version: "0.1.0-preview.33-map-official", profile: components.library.id ?? "openintelligentui",
            upstreamCommit: "16ef26475999e3a021a50b1607a03717c0721255", runtimeCommit: "f3dfa1d0b479c131b6d4268e81961186f22ff09c",
            components: specification.components.map { .init(name: $0.name, rendering: web.contains($0.name) ? "local-webkit-or-embedded-media" : $0.name == "Map" ? "mapkit" : "swiftui", contract: $0.description) },
            functions: specification.functions.map(\.name), actions: specification.actions.map(\.name),
            requirements: [
                "iOS 16+ / macOS 13+; system text, controls and dynamic appearance.",
                "SwiftLang is the shared platform adapter used by both UI libraries. The official language core is pinned for build-time generation; its current identity is recorded in SwiftLang's bundled core-manifest.json.",
                "upstreamCommit and runtimeCommit record the original component and Swift source imports. They do not identify the current SDK checkout or bundled language core.",
                "SearchImage is registered only with an explicit caller service.",
                "Content and citations present caller-supplied facts; this library does not retrieve or invent them.",
                "Map routes use ordered Apple MKDirections automobile routes for 2–25 visible markers. Inline and expanded views share one route lifecycle; complete road results replace the direct-connection overview. Loading, failed and unavailable routes keep that overview. This is not turn-by-turn navigation.",
                "Map owns category filtering, overview, label selection and native expansion using the pinned Map / MapMarker fields. Duplicate labels keep distinct rendered markers and share label selection. Filtering and recentering do not rewrite the selected value. Place search, business data, location permission and bookings remain host responsibilities.",
                "Map basemap and remote media depend on external network resources.",
                "HTML has no native bridge; inline scripts are isolated and network is restricted.",
                "Functions execute pinned upstream computation code in JavaScriptCore; JSON data values only.",
                "Positional contracts follow demo 53df45b4231aabab1a0e932733e117937ff2b41c. Layout/property behavior follows intelligent-ui-library 0.0.1 at openui c531b0dfe83dc828241f71dbe77e689ebdbf05f7; this is not a claim of complete browser CSS or pixel parity.",
                "Box supports numeric lengths, numeric strings, px, percent, Dynamic Type-scaled em/rem and vw/vh from the enclosing visible container. Percent uses parent constraints; unavailable viewport geometry stays unresolved. Invalid CSS width/height units and expressions are not simulated.",
                "Explicit Box.flex uses a zero basis before authored dimensions. Row wrap distributes flex per line; definite-height columns distribute it vertically. Direct Row photos use responsive media width and a 4:3 ratio, so ordinary image/text composition needs no private sizing recipe.",
                "Colors accept semantic tokens, HEX, RGB(A), HSL(A) and CSS named colors. Advanced CSS color spaces and relative/inherited color expressions are not supported; native palette and system typography remain host-configurable.",
                "Image and optional SearchImage expose the upstream framing fields to new generation; component definitions generate spec and prompt together. Removed components are not registered for generation or runtime reading.",
                "Image, Title, Text and Caption compose through Col, Row, Box or Grid; no special-purpose ImageText component is required.",
                "Component names, positional arguments and bindings are retained. Layout/color/spacing schemas remove private ranges and enums to follow the pinned upstream contract; components still handle invalid finite values according to their rendering rules.",
                "Generation validation uses the advertised writer profile; historical validation keeps the complete reader. Presentation warnings are non-blocking.",
                "This manifest describes implemented contracts, not exhaustive device or model acceptance."
            ])
    }
}
