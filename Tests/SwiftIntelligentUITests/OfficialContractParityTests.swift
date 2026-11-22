import XCTest
import SwiftUI
import MapKit
import SwiftLang
@testable import SwiftIntelligentUI
#if os(macOS)
import AppKit
#endif

/// Exact upstream positional signatures: thesysdev/open-intelligent-ui
/// src/generated/spec.json at 53df45b4231aabab1a0e932733e117937ff2b41c.
/// Map and MapMarker also pin their complete nested schema below.
/// These are input-contract baselines, not a claim of CSS/React visual parity.
final class OfficialContractParityTests: XCTestCase {
    private let upstream: [String: [String]] = [
        "Col": ["children", "gap", "align"],
        "Row": ["children", "gap", "align", "justify", "wrap"],
        "Box": ["children", "direction", "gap", "padding", "background", "radius", "border", "width", "height", "flex", "align", "justify", "wrap"],
        "Grid": ["children", "columns", "minChildWidth", "gap"],
        "Card": ["children", "variant", "gap", "padding"],
        "Carousel": ["children", "itemWidth", "gap"],
        "Popover": ["trigger", "content"],
        "Divider": [],
        "Spacer": [],
        "Title": ["text", "size", "color"],
        "Text": ["text", "size", "color", "weight", "italic", "lineThrough", "tabularNums", "maxLines"],
        "Caption": ["text", "color"],
        "Label": ["text"],
        "Badge": ["text", "color", "icon"],
        "Link": ["text", "url"],
        "List": ["items", "marker", "timeline"],
        "ListItem": ["title", "description", "marker", "children"],
        "Markdown": ["text"],
        "Quote": ["text", "cite"],
        "Code": ["code", "language"],
        "Math": ["tex", "inline"],
        "Button": ["label", "action", "variant", "color", "size", "icon", "disabled", "block"],
        "IconButton": ["icon", "action", "label", "variant"],
        "Pressable": ["children", "action", "selected", "padding", "background", "radius"],
        "Input": ["value", "label", "type", "placeholder", "rules"],
        "TextArea": ["value", "label", "placeholder", "rows", "rules"],
        "Select": ["value", "options", "label", "placeholder", "rules"],
        "SegmentedControl": ["value", "options", "block"],
        "Slider": ["value", "min", "max", "step", "label", "unit", "marks"],
        "Checkbox": ["checked", "label", "lineThrough", "rules"],
        "RadioGroup": ["value", "options", "label", "variant", "rules"],
        "DatePicker": ["value", "label", "min", "max", "rules"],
        "Timer": ["seconds", "label"],
        "Form": ["children"],
        "Image": ["src", "alt", "aspectRatio", "radius", "fit"],
        "Icon": ["name", "size", "color"],
        "Table": ["columns", "rows"],
        "Chart": ["type", "data", "x", "series", "format", "stacked", "height"],
        "YouTube": ["video", "title"],
        "Flashcard": ["front", "back", "hint"],
        "Celebration": ["when"],
        "Svg": ["children", "viewBox", "label", "width", "height"],
        "Circle": ["cx", "cy", "r", "fill", "stroke", "strokeWidth", "opacity"],
        "Ellipse": ["cx", "cy", "rx", "ry", "fill", "stroke", "strokeWidth", "opacity"],
        "Rect": ["x", "y", "width", "height", "fill", "stroke", "strokeWidth", "opacity", "rx"],
        "Line": ["x1", "y1", "x2", "y2", "stroke", "strokeWidth", "opacity"],
        "Path": ["d", "fill", "stroke", "strokeWidth", "opacity"],
        "Polyline": ["points", "fill", "stroke", "strokeWidth", "opacity"],
        "Polygon": ["points", "fill", "stroke", "strokeWidth", "opacity"],
        "SvgText": ["text", "x", "y", "size", "fill", "anchor", "weight"],
        "G": ["children", "transform", "opacity"],
        "HtmlView": ["html", "height", "title"],
        "SearchImage": ["query", "aspectRatio", "radius", "fit"],
        "Map": ["markers", "route", "selected", "height"],
        "MapMarker": ["label", "lat", "lng", "category", "icon"]
    ]

    @MainActor func testEveryOfficialComponentHasTheSamePositionalArguments() throws {
        let images = OpenIntelligentUIImageSearch { _ in
            .init(url: "https://example.invalid/photo.jpg", alt: "fixture")
        }
        let library = try OpenIntelligentUIComponents(imageSearch: images)
        let definitions = Dictionary(uniqueKeysWithValues: library.components.library.components.map {
            ($0.name, $0.params.map(\.name))
        })
        XCTAssertEqual(upstream.count, 55)
        for (name, expected) in upstream {
            XCTAssertEqual(definitions[name], expected, "Upstream positional contract differs for \(name)")
        }
        XCTAssertEqual(definitions.count, 60)
        XCTAssertEqual(Set(definitions.keys).subtracting(upstream.keys),
                       ["ProductCard", "JourneyLine", "Citation", "Disclosure", "Progress"],
                       "The five generation extensions must stay separate from the official base")
        XCTAssertEqual(library.readerSpecification.components.count, 60)
        XCTAssertEqual(Set(library.readerSpecification.components.map(\.name)), Set(definitions.keys))
    }

    func testSearchImageRemainsAbsentWithoutHostProvider() throws {
        let library = try OpenIntelligentUIComponents()
        XCTAssertNil(library.components.registry["SearchImage"])
        XCTAssertFalse(library.systemPrompt.contains("SearchImage("))
        XCTAssertEqual(library.components.library.components.count, 59)
        XCTAssertEqual(library.readerSpecification.components.count, 60)
    }

    func testMapDefinitionsMatchTheCompleteOfficialNestedSchema() throws {
        // 53df45b src/lib/components/map/map.tsx and src/generated/spec.json.
        // The demo extends its library with Map/MapMarker; these exact schemas
        // do not add a marker count, unique-label rule or numeric ranges.
        let expectedJSON = #"""
        {
          "Map": {
            "type": "object",
            "properties": {
              "markers": {"type": "array", "items": {"$ref": "#/$defs/MapMarker"}},
              "route": {"type": "boolean"},
              "selected": {"type": "string"},
              "height": {"type": "number"}
            },
            "required": ["markers"],
            "additionalProperties": false,
            "description": "Street map fitted to its markers. route draws the road path in marker order; selected holds the clicked marker's label."
          },
          "MapMarker": {
            "type": "object",
            "properties": {
              "label": {"type": "string"},
              "lat": {"type": "number"},
              "lng": {"type": "number"},
              "category": {"type": "string"},
              "icon": {"type": "string"}
            },
            "required": ["label", "lat", "lng"],
            "additionalProperties": false,
            "description": "A place on a Map; icon is one emoji, else the pin shows its number."
          }
        }
        """#
        let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(expectedJSON.utf8)) as? [String: Any])
        let library = try OpenIntelligentUIComponents()
        for specification in [library.specification, library.readerSpecification] {
            let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(specification.jsonString().utf8)) as? [String: Any])
            let schema = try XCTUnwrap(exported["schema"] as? [String: Any])
            let definitions = try XCTUnwrap(schema["$defs"] as? [String: Any])
            for name in ["Map", "MapMarker"] {
                let actual = try XCTUnwrap(definitions[name] as? [String: Any])
                let baseline = try XCTUnwrap(expected[name] as? [String: Any])
                XCTAssertEqual(actual as NSDictionary, baseline as NSDictionary, "Full upstream schema differs for \(name)")
            }
            XCTAssertEqual(specification.components.first { $0.name == "Map" }?.signature,
                           "Map(markers: MapMarker[], route?: boolean, selected?: $binding<string>, height?: number)")
            XCTAssertEqual(specification.components.first { $0.name == "MapMarker" }?.signature,
                           "MapMarker(label: string, lat: number, lng: number, category?: string, icon?: string)")
        }
        for components in [library.components.library.components, library.readerComponents.library.components] {
            let map = try XCTUnwrap(components.first { $0.name == "Map" })
            let marker = try XCTUnwrap(components.first { $0.name == "MapMarker" })
            XCTAssertEqual(map.params.filter(\.required).map(\.name), ["markers"])
            XCTAssertEqual(marker.params.filter(\.required).map(\.name), ["label", "lat", "lng"])
            XCTAssertEqual(map.params.filter(\.isBindable).map(\.name), ["selected"])
            XCTAssertTrue(marker.params.allSatisfy { !$0.isBindable })
            XCTAssertTrue((map.params + marker.params).allSatisfy { !$0.hasDefault })
        }
    }

    @MainActor func testMapNumericInputsStaySchemaValidWhileRenderingRejectsInvalidCoordinates() throws {
        // 53df45b src/lib/components/map/map.tsx uses plain z.number fields;
        // map-utils.ts coordinate() applies geographic limits when decoding.
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        let source = #"root=Map([MapMarker("Outside geographic bounds",91,181)],false,null,-10)"#
        state.setSource(source)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertEqual(library.validationIssues(in: state, source: source, profile: .historical), [])
        XCTAssertEqual(library.validationIssues(in: state, source: source, profile: .generation), [])
        let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.components.registry, state: state)
        XCTAssertTrue(MapPoint.decode(context.value("markers")).isEmpty)
        XCTAssertEqual(MapMetrics.height(context.number("height"), viewportWidth: 1000), 200)
    }

    func testLayoutAndPhotoNumbersMatchTheOfficialSchemaWithoutPrivateRanges() throws {
        // The pinned demo's generated spec uses { type: "number" } for
        // these fields. Clamping belongs to the component implementation.
        let library = try OpenIntelligentUIComponents()
        let fields = ["Col": ["gap"], "Row": ["gap"],
                      "Box": ["gap", "padding", "flex"],
                      "Grid": ["columns", "minChildWidth", "gap"],
                      "Card": ["gap", "padding"],
                      "Carousel": ["itemWidth", "gap"],
                      "Image": ["aspectRatio"]]
        let number: JSONValue = .object([.init(key: "type", value: .string("number"))])
        for (component, names) in fields {
            let definition = try XCTUnwrap(library.components.library.components.first { $0.name == component })
            for name in names {
                let parameter = try XCTUnwrap(definition.params.first { $0.name == name })
                XCTAssertEqual(parameter.schema, number, "\(component).\(name)")
            }
        }
    }

    func testViewportOnlyAcceptsVisibleFiniteGeometry() {
        XCTAssertEqual(IntelligentUIViewportGeometry.valid(CGSize(width: 420, height: 720)), CGSize(width: 420, height: 720))
        XCTAssertNil(IntelligentUIViewportGeometry.valid(.zero))
        XCTAssertNil(IntelligentUIViewportGeometry.valid(CGSize(width: .infinity, height: 720)))
        XCTAssertNil(IntelligentUIViewportGeometry.valid(CGSize(width: 420, height: -1)))
    }

    func testNativeLengthsRespectContainerAndTypefaceInsteadOfScreen() {
        XCTAssertEqual(IntelligentUILength.read(.string("50%"))?.resolve(relativeTo: 280, em: 17), 140)
        XCTAssertEqual(IntelligentUILength.read(.string("1.5rem"))?.resolve(relativeTo: 280, em: 17), 25.5)
        XCTAssertEqual(IntelligentUILength.read(.string("35px"))?.resolve(relativeTo: nil, em: 17), 35)
        let viewport = CGSize(width: 420, height: 720)
        XCTAssertEqual(IntelligentUILength.read(.string("50vw"))?.resolve(relativeTo: 280, em: 17, viewport: viewport), 210)
        XCTAssertEqual(IntelligentUILength.read(.string("50vh"))?.resolve(relativeTo: 280, em: 17, viewport: viewport), 360)
        XCTAssertNil(IntelligentUILength.read(.string("50vw"))?.resolve(relativeTo: 280, em: 17))
        XCTAssertEqual(IntelligentUILength.read(.string("96")), .points(96))
        XCTAssertEqual(IntelligentUILength.read(.number(-10)), .points(0))
        XCTAssertEqual(IntelligentUILength.read(.number(20_000)), .points(20_000))
        XCTAssertNil(IntelligentUILength.read(.string("12pt")))
        XCTAssertNil(IntelligentUILength.read(.string("-10px")))
        XCTAssertNil(IntelligentUILength.read(.string("1fr")), "fr is not a valid CSS width/height used value")
        XCTAssertNil(IntelligentUILength.read(.string("calc(50% - 10px)")))
    }

    #if os(macOS)
    @MainActor func testRootPercentageHeightUsesTheActualFiniteHostProposal() throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        defer { state.reset() }
        state.setSource(##"root=Box([],"col",0,0,"#ff0000",null,false,80,"50%")"##)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let renderer = ImageRenderer(content: OpenIntelligentUIContentView(state: state, library: library)
            .frame(width: 200, height: 200, alignment: .topLeading))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        let paintedRows = (0..<bitmap.pixelsHigh).filter { y in
            (0..<bitmap.pixelsWide).contains { x in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                return color.alphaComponent > 0.9 && color.redComponent > 0.9
                    && color.greenComponent < 0.1 && color.blueComponent < 0.1
            }
        }
        XCTAssertEqual(paintedRows.count, 100, "The root's 50% is relative to the 200-point host, not its own content height")
    }
    #endif

    @MainActor func testFormValidatesRequiredAndCorrectedInputs() throws {
        let rules: Value = .object([
            .init(key: "required", value: .boolean(true)),
            .init(key: "email", value: .boolean(true))
        ])
        let parsed = IntelligentUIRules.parse(rules)
        XCTAssertNotNil(validate(.string(""), rules: parsed))
        XCTAssertNotNil(validate(.string("not-an-email"), rules: parsed))
        XCTAssertNil(validate(.string("hello@example.com"), rules: parsed))

        let form = IntelligentUIFormValidationStore()
        form.register("email") { "Email required" }
        XCTAssertFalse(form.submit())
        XCTAssertNotNil(form.errors["email"])
        form.register("email") { nil }
        XCTAssertTrue(form.submit())
        XCTAssertTrue(form.errors.isEmpty)
    }

    @MainActor func testNativeIconContractAcceptsUnlistedLucideNames() throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource(#"root = Col([Icon("coffee"), Icon("an-unlisted-lucide-name")])"#)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertEqual(IconCatalog.symbol("coffee"), "cup.and.saucer")
        XCTAssertEqual(IconCatalog.symbol("an-unlisted-lucide-name"), "questionmark.circle")
    }

    func testChartSyntaxNowMatchesPercentageOnlyFormat() throws {
        let library = try OpenIntelligentUIComponents()
        let chart = try XCTUnwrap(library.components.library.components.first { $0.name == "Chart" })
        XCTAssertNil(chart.params.first { $0.name == "currency" })
        XCTAssertEqual(chart.params.map(\.name), ["type", "data", "x", "series", "format", "stacked", "height"])
    }
}
