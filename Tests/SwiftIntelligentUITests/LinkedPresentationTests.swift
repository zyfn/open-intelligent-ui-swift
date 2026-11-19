import XCTest
import SwiftUI
import SwiftLang
@testable import SwiftIntelligentUI

final class LinkedPresentationTests: XCTestCase {
    @MainActor func testReaderComponentSignaturesMatchThePublicContract() throws {
        let library = try OpenIntelligentUIComponents()
        let expected: [String: [String]] = [
            "Map": ["markers", "route", "selected", "height"],
            "MapMarker": ["label", "lat", "lng", "category", "icon"],
            "Carousel": ["children", "itemWidth", "gap"],
            "Chart": ["type", "data", "x", "series", "format", "stacked", "height"],
            "Image": ["src", "alt", "aspectRatio", "radius", "fit"],
            "Form": ["children"],
            "Input": ["value", "label", "type", "placeholder", "rules"],
            "TextArea": ["value", "label", "placeholder", "rows", "rules"],
            "Select": ["value", "options", "label", "placeholder", "rules"],
            "ListItem": ["title", "description", "marker", "children"]
        ]
        for (name, parameters) in expected {
            let component = try XCTUnwrap(library.readerComponents.library.components.first { $0.name == name }, name)
            XCTAssertEqual(component.params.map(\.name), parameters, name)
        }
    }

    @MainActor func testMapUsesMarkerLabelsAndOfficialSelection() throws {
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        let source = #"""
        root=Map([MapMarker("南宋德寿宫遗址博物馆",30.238678,120.173273,"博物馆","🏛️"),MapMarker("胡雪岩旧居（胡雪岩故居）",30.237273,120.172906,"历史建筑","🏛️")],false,$selected,400)
        $selected="胡雪岩旧居（胡雪岩故居）"
        """#
        state.setSource(source)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.components.registry, state: state)
        let points = MapPoint.decode(context.value("markers"))
        XCTAssertEqual(points.map(\.id), ["南宋德寿宫遗址博物馆", "胡雪岩旧居（胡雪岩故居）"])
        XCTAssertEqual(points.map(\.icon), ["🏛️", "🏛️"])
        XCTAssertEqual(ValueReading.boundString(context, "selected"), "胡雪岩旧居（胡雪岩故居）")
        XCTAssertNil(PropValue.value(try XCTUnwrap(state.root), "content"))
        XCTAssertNil(context.binding("visibleIds"))
    }

    @MainActor func testMapInvalidSelectionReturnsToOverviewWithoutSelectingAnUnchosenPlace() throws {
        #if os(macOS)
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        state.setSource(#"""
        root=Col([Map([MapMarker("南宋德寿宫遗址博物馆",30.238678,120.173273),MapMarker("胡雪岩旧居（胡雪岩故居）",30.237273,120.172906)],false,$selected,300),Text($selected)])
        $selected="已失效的地点"
        """#)
        let renderer = ImageRenderer(content: OpenIntelligentUIContentView(state: state, library: library).frame(width: 360, height: 500))
        XCTAssertNotNil(renderer.nsImage)
        XCTAssertEqual(state.stateValue("$selected"), .string(""))
        #endif
    }

    @MainActor func testMapWithoutPlaceFactsIsRejectedInsteadOfAcceptedAsEmptyMap() throws {
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        let source = "root=Map([])"
        state.setSource(source)
        XCTAssertTrue(library.validationIssues(in: state, source: source).contains { $0.contains("Map.markers: at least one valid supplied place marker") })
    }

    @MainActor func testMapDuplicateLabelsAreDiagnosedInsteadOfSilentlyDropped() throws {
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        let source = #"root=Map([MapMarker("同名地点",30.1,120.1),MapMarker("同名地点",30.2,120.2)])"#
        state.setSource(source)
        XCTAssertEqual(MapPoint.duplicateLabels(PropValue.value(try XCTUnwrap(state.root), "markers")), ["同名地点"])
        XCTAssertTrue(library.validationIssues(in: state, source: source).contains { $0.contains("duplicate labels cannot be selected independently") })
    }

    @MainActor func testDynamicListUsesRuntimePositionalIdentityWithoutCustomID() throws {
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        state.setSource(#"""
        root=Col([List($day=="sat" ? saturday : sunday)])
        $day="sat"
        $title="德寿宫"
        $visited=false
        saturday=[ListItem($title,"周六","09:30",[Checkbox($visited,"去过"),Disclosure("资料",[Text("周六详情")])])]
        sunday=[ListItem("孤山馆区","周日","09:30",[Disclosure("资料",[Text("周日详情")])])]
        """#)
        func identity() throws -> String {
            let list = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
            return try XCTUnwrap(OpenUIComponentContext(element: list, registry: library.components.registry, state: state).children("items").first).id
        }
        let saturdayID = try identity()
        state.setState("$title", value: .string("德寿宫资料更新"))
        state.setState("$visited", value: .boolean(true))
        XCTAssertEqual(try identity(), saturdayID)
        state.setState("$day", value: .string("sun"))
        XCTAssertEqual(try identity(), saturdayID)
        XCTAssertEqual(state.stateValue("$visited"), .boolean(true))
        XCTAssertTrue(library.validationIssues(in: try XCTUnwrap(state.root)).isEmpty)
    }

    @MainActor func testListItemAdditionalIDIsRejectedAndOfficialCallRemainsValid() throws {
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        state.setSource(#"root=List([ListItem("A","","",[],"custom")])"#)
        XCTAssertFalse(state.errors.isEmpty)
        state.setSource(#"root=List([ListItem("旧调用","说明","09:30",[Text("详情")])])"#)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertTrue(library.validationIssues(in: try XCTUnwrap(state.root)).isEmpty)
    }

    @MainActor func testGenerationMapExampleUsesBuiltInPresentationWithoutExtraLangControls() throws {
        let library = try OpenIntelligentUIComponents(excludingComponents: ["ImageText", "YouTube", "Timer"])
        let example = try XCTUnwrap(library.selectedGenerationExamples.first { $0.contains("MapMarker(") })
        let start = try XCTUnwrap(example.range(of: "root = Col("))
        let state = library.makeState()
        state.setSource(String(example[start.lowerBound...]))
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let children = PropValue.children(try XCTUnwrap(state.root))
        let mapElement = try XCTUnwrap(children.first { $0.typeName == "Map" })
        let map = OpenUIComponentContext(element: mapElement, registry: library.components.registry, state: state)
        XCTAssertEqual(MapPoint.decode(map.value("markers")).map(\.label), ["南宋德寿宫遗址博物馆", "胡雪岩旧居（胡雪岩故居）"])
        XCTAssertEqual(ValueReading.boundString(map, "selected"), "")
        XCTAssertNil(PropValue.value(mapElement, "content"))
        XCTAssertEqual(children.map(\.typeName), ["Map"], "The SDK supplies cards and controls inside the map")
        XCTAssertTrue(library.validationIssues(in: state, source: String(example[start.lowerBound...])).isEmpty)
    }

    func testCarouselUsesPreferredWidthAndAccessibilityWidth() {
        XCTAssertEqual(CarouselMetrics.width(preferred: 240, available: 320, accessibility: false), 240)
        XCTAssertEqual(CarouselMetrics.width(preferred: 288, available: 240, accessibility: false), 204)
        XCTAssertEqual(CarouselMetrics.width(preferred: 288, available: 100, accessibility: false), 85)
        XCTAssertEqual(CarouselMetrics.width(preferred: 288, available: 360, accessibility: true), 360)
    }

    func testCarouselPositionTracksOffsetsAndRuntimeIdentity() {
        XCTAssertEqual(CarouselMetrics.index(offset: 496, itemWidth: 240, gap: 16, count: 3), 2)
        XCTAssertEqual(CarouselMetrics.index(offset: -20, itemWidth: 240, gap: 16, count: 3), 0)
        XCTAssertEqual(CarouselMetrics.currentIndex(current: 0, previousIDs: ["a", "b"], newIDs: ["x", "a", "b"]), 1)
        XCTAssertEqual(CarouselMetrics.currentIndex(current: 1, previousIDs: ["a", "b"], newIDs: ["x", "a", "b"]), 2)
        XCTAssertEqual(CarouselMetrics.currentIndex(current: 1, previousIDs: ["a", "b"], newIDs: ["x", "y"]), 1)
        XCTAssertEqual(CarouselMetrics.currentIndex(current: 2, previousIDs: ["a", "b"], newIDs: []), 0)
    }
}
