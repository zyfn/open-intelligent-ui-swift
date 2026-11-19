import XCTest
import SwiftUI
import MapKit
import SwiftLang
@testable import SwiftIntelligentUI

/// Exact upstream positional signatures: thesysdev/open-intelligent-ui
/// src/generated/spec.json at 53df45b4231aabab1a0e932733e117937ff2b41c.
/// This is a signature baseline, not a claim of CSS/React visual parity.
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
        XCTAssertEqual(definitions.count, 61, "The six native business extensions must stay separate")
    }

    func testSearchImageRemainsAbsentWithoutHostProvider() throws {
        let library = try OpenIntelligentUIComponents()
        XCTAssertNil(library.components.registry["SearchImage"])
        XCTAssertFalse(library.systemPrompt.contains("SearchImage("))
        XCTAssertEqual(library.components.library.components.count, 60)
    }

    func testNativeLengthsRespectContainerAndTypefaceInsteadOfScreen() {
        XCTAssertEqual(IntelligentUILength.read(.string("50%"))?.resolve(relativeTo: 280, em: 17), 140)
        XCTAssertEqual(IntelligentUILength.read(.string("1.5rem"))?.resolve(relativeTo: 280, em: 17), 25.5)
        XCTAssertEqual(IntelligentUILength.read(.string("35px"))?.resolve(relativeTo: nil, em: 17), 35)
        XCTAssertNil(IntelligentUILength.read(.string("50vw")))
        XCTAssertNil(IntelligentUILength.read(.string("calc(50% - 10px)")))
    }

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

    func testChartSyntaxNowMatchesPercentageOnlyFormat() throws {
        let library = try OpenIntelligentUIComponents()
        let chart = try XCTUnwrap(library.components.library.components.first { $0.name == "Chart" })
        XCTAssertNil(chart.params.first { $0.name == "currency" })
        XCTAssertEqual(chart.params.map(\.name), ["type", "data", "x", "series", "format", "stacked", "height"])
    }
}
