import XCTest
import OpenUILang
import OpenUISwiftUI
@testable import SwiftIntelligentUI

final class LinkedPresentationTests: XCTestCase {
    @MainActor func testFallbackCardsPreserveFactsAndIdentityWithRegisteredComponents() throws {
        let library = try IntelligentUILibrary()
        let original = MapPoint(id: "deshou", label: "南宋德寿宫遗址博物馆", latitude: 30.238678, longitude: 120.173273, category: "人文地点", icon: "landmark", badge: "")
        let renamed = MapPoint(id: original.id, label: "地点资料更新", latitude: original.latitude, longitude: original.longitude, category: original.category, icon: original.icon, badge: "")
        let other = MapPoint(id: "huxueyan", label: original.label, latitude: 30.237273, longitude: 120.172906, category: "", icon: "landmark", badge: "")
        let cards = MapFallback.cards(points: [original, other])
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards.first?.id, MapFallback.cards(points: [renamed]).first?.id)
        XCTAssertNotEqual(cards[0].id, cards[1].id)
        for child in cards {
            guard case .element(let card) = child.value else { return XCTFail("Expected registered card") }
            XCTAssertEqual(card.typeName, "Card")
            XCTAssertTrue(library.validationIssues(in: card).isEmpty)
            let summary = try XCTUnwrap(PropValue.children(card).first)
            XCTAssertEqual(summary.typeName, "ImageText")
            let content = summary.props.first(where: { $0.0 == "content" })?.1
            XCTAssertEqual(ValueReading.field(content, "title"), .string(OpenUIString(original.label)))
            XCTAssertNil(ValueReading.field(content, "image"))
            XCTAssertEqual(ValueReading.string(ValueReading.field(content, "subtitle")), child.id == cards[0].id ? original.category : "")
        }
    }

    @MainActor func testMapWithoutPlaceFactsIsRejectedInsteadOfAcceptedAsEmptyMap() throws {
        let library = try IntelligentUILibrary(), state = library.makeState()
        let source = "root=Map([])"
        state.setSource(source)
        XCTAssertTrue(library.validationIssues(in: state, source: source).contains { $0.contains("Map.markers: at least one valid supplied place marker") })
    }

    @MainActor func testMapFallbackUsesRealMarkerIdentityWithoutRewritingExternalSelection() throws {
        let library = try IntelligentUILibrary(), state = library.makeState()
        let source = #"""
        root=Map([MapMarker("南宋德寿宫遗址博物馆",30.238678,120.173273,"博物馆","landmark","deshou"),MapMarker("胡雪岩旧居（胡雪岩故居）",30.237273,120.172906,"历史建筑","landmark","huxueyan")],false,$selected,420,[])
        $selected="missing"
        """#
        state.setSource(source)
        XCTAssertTrue(library.validationIssues(in: state, source: source).isEmpty)
        let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.components.registry, state: state)
        let points = MapPoint.decode(context.value("markers"))
        XCTAssertEqual(points.first?.label, "南宋德寿宫遗址博物馆")
        XCTAssertEqual(points.first?.category, "博物馆")
        XCTAssertTrue(context.children("content").isEmpty)
        XCTAssertEqual(MapSelection.resolve(ids: points.map(\.id), requested: ValueReading.boundString(context, "selected")), "deshou")
        XCTAssertEqual(state.stateValue("$selected"), .string("missing"))
        XCTAssertEqual(MapSelection.resolve(ids: points.map(\.id), requested: "huxueyan"), "huxueyan")
        XCTAssertEqual(MapSelection.resolve(ids: points.map(\.id), requested: nil), "deshou")
        XCTAssertEqual(MapSelection.resolve(ids: [], requested: nil), "")
    }

    @MainActor func testDynamicListKeysFollowLogicalEntitiesNotTitlesOrPositions() throws {
        let library = try IntelligentUILibrary(), state = library.makeState()
        state.setSource(#"""
        root=Col([List($day=="sat" ? saturday : sunday)])
        $day="sat"
        $title="德寿宫"
        $visited=false
        saturday=[ListItem($title,"周六","09:30",[Checkbox($visited,"去过"),Disclosure("资料",[Text("周六详情")])],"deshou")]
        sunday=[ListItem("孤山馆区","周日","09:30",[Disclosure("资料",[Text("周日详情")])],"gushan")]
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
        XCTAssertNotEqual(try identity(), saturdayID)
        XCTAssertEqual(state.stateValue("$visited"), .boolean(true))
        XCTAssertTrue(library.validationIssues(in: try XCTUnwrap(state.root)).isEmpty)
    }

    @MainActor func testDuplicateListKeysAreDiagnosedAndLegacyFourArgumentsRemainValid() throws {
        let library = try IntelligentUILibrary(), state = library.makeState()
        state.setSource(#"root=List([ListItem("A","","",[],"same"),ListItem("B","","",[],"same")])"#)
        XCTAssertTrue(library.validationIssues(in: try XCTUnwrap(state.root)).contains { $0.contains("duplicate logical id") })
        state.setSource(#"root=List([ListItem("旧调用","说明","09:30",[Text("详情")])])"#)
        XCTAssertTrue(state.errors.isEmpty)
        XCTAssertTrue(library.validationIssues(in: try XCTUnwrap(state.root)).isEmpty)
    }

    @MainActor func testGenerationMapExampleUsesMatchingPlaceIdentitiesAndInformation() throws {
        let library = try IntelligentUILibrary(excludingComponents: ["ImageText", "YouTube", "Timer"])
        let example = try XCTUnwrap(library.selectedGenerationExamples.first { $0.contains("MapMarker(") })
        let start = try XCTUnwrap(example.range(of: "root = Col("))
        let state = library.makeState()
        state.setSource(String(example[start.lowerBound...]))
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let mapElement = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first(where: { $0.typeName == "Map" }))
        let map = OpenUIComponentContext(element: mapElement, registry: library.components.registry, state: state)
        let points = MapPoint.decode(map.value("markers"))
        XCTAssertEqual(points.map(\.id), ["deshou", "huxueyan"])
        XCTAssertEqual(state.stateValue("$visible"), .null)
        let carouselElement = try XCTUnwrap(PropValue.children(mapElement, "content").first)
        let carousel = OpenUIComponentContext(element: carouselElement, registry: library.components.registry, state: state)
        XCTAssertEqual(ValueReading.array(carousel.value("itemIds")).map { ValueReading.string($0) }, points.map(\.id))
        let cards = PropValue.children(carouselElement)
        let rows = cards.compactMap { PropValue.children($0).first }
        XCTAssertEqual(rows.map(\.typeName), ["Row", "Row"])
        let titles = try rows.map { row in
            let children = PropValue.children(row)
            let image = try XCTUnwrap(children.first)
            XCTAssertEqual(image.typeName, "Image")
            XCTAssertFalse((PropValue.string(image, "src") ?? "").isEmpty)
            XCTAssertNil(PropValue.value(image, "aspectRatio"))
            let column = try XCTUnwrap(children.last)
            let title = try XCTUnwrap(PropValue.children(column).first)
            XCTAssertEqual(title.typeName, "Title")
            return PropValue.string(title, "text") ?? ""
        }
        XCTAssertEqual(titles, points.map(\.label))
        XCTAssertEqual(points.first?.latitude, 30.238678)
        XCTAssertEqual(points.first?.longitude, 120.173273)
        state.setState("$selected", value: .string("huxueyan"))
        XCTAssertEqual(ValueReading.boundString(map, "selected"), "huxueyan")
        XCTAssertEqual(ValueReading.boundString(carousel, "selected"), "huxueyan")
        try XCTUnwrap(map.binding("visibleIds")).wrappedValue = .array([.string("huxueyan")])
        let outside = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first(where: { $0.typeName == "Carousel" }))
        XCTAssertEqual(PropValue.children(outside).count, 1)
        XCTAssertEqual(ValueReading.array(PropValue.value(outside, "itemIds")), [.string("huxueyan")])
        XCTAssertTrue(library.validationIssues(in: state, source: String(example[start.lowerBound...])).isEmpty)
    }

    @MainActor func testMapFilterProjectionKeepsCardIdsAndSelectionTogether() throws {
        let library = try IntelligentUILibrary(), state = library.makeState()
        state.setSource(#"""
        root=Map([MapMarker("A",30,120,null,null,"a"),MapMarker("B",31,121,null,null,"b")],false,$selected,360,[Carousel([Card([Text("A")]),Card([Text("B")])],288,3,$selected,["a","b"])],true,$visible,["a","b"])
        $selected="b"
        $visible=["a","b"]
        """#)
        let map = try XCTUnwrap(state.root)
        let input = PropValue.value(map, "content")
        let projected = try XCTUnwrap(MapContentProjection.filtered(input, visible: ["b"], known: ["a", "b"], selected: "b"))
        guard case .element(let carousel) = try XCTUnwrap(projected.first) else { return XCTFail("Expected carousel") }
        XCTAssertEqual(PropValue.children(carousel).count, 1)
        XCTAssertEqual(ValueReading.array(PropValue.value(carousel, "itemIds")), [.string("b")])
        XCTAssertEqual(PropValue.children(try XCTUnwrap(PropValue.children(map, "content").first)).count, 2)
        XCTAssertNil(MapContentProjection.filtered(input, visible: ["b"], known: ["a", "b"], selected: "a"))
        state.setState("$visible", value: .array([.string("unknown")]))
        XCTAssertTrue(library.validationIssues(in: state, source: "").contains { $0.contains("Map.visibleIds") })
    }

    func testCarouselIdentitiesAreExplicitAndUnambiguous() {
        XCTAssertEqual(CarouselSelection.ids(count: 2, supplied: nil), ["0", "1"])
        XCTAssertEqual(CarouselSelection.ids(count: 2, supplied: .array([.string("a"), .string("b")])), ["a", "b"])
        XCTAssertNil(CarouselSelection.ids(count: 2, supplied: .array([.string("a"), .string("a")])))
        XCTAssertNil(CarouselSelection.ids(count: 2, supplied: .array([.string("a")])))
    }

    @MainActor func testMapAndCardCarouselShareStableSelection() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource(#"""
        root = Map([MapMarker("同名",37.33,-122.01,null,"camera","a","1"),MapMarker("同名",37.32,-122.03,null,"headphones","b","2")],false,$selected,540,[Carousel([ProductCard({id:"a",title:"相机",images:[],priceText:"¥100"},"compact"),ProductCard({id:"b",title:"耳机",images:[],priceText:"¥50"},"compact")],300,3,$selected,["a","b"])],true)
        $selected = "a"
        """#)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertTrue(library.undeclaredFieldIssues(in: try XCTUnwrap(state.root)).isEmpty)
        let root = try XCTUnwrap(state.root)
        let map = OpenUIComponentContext(element: root, registry: library.components.registry, state: state)
        let points = MapPoint.decode(map.value("markers"))
        XCTAssertEqual(points.map(\.id), ["a", "b"])
        XCTAssertEqual(points.map(\.badge), ["1", "2"])
        let carouselElement = try XCTUnwrap(PropValue.children(root, "content").first)
        let carousel = OpenUIComponentContext(element: carouselElement, registry: library.components.registry, state: state)
        try XCTUnwrap(map.binding("selected")).wrappedValue = .string("b")
        XCTAssertEqual(carousel.binding("selected")?.wrappedValue, .string("b"))
        XCTAssertEqual(ValueReading.boundString(carousel, "selected"), "b")
        XCTAssertEqual(ValueReading.boundString(map, "selected"), "b")
        try XCTUnwrap(carousel.binding("selected")).wrappedValue = .string("a")
        XCTAssertEqual(map.binding("selected")?.wrappedValue, .string("a"))
        XCTAssertEqual(ValueReading.boundString(map, "selected"), "a")
    }

    @MainActor func testLegacyMapSignaturesKeepLabelSelection() throws {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource(#"""
        root = Map([MapMarker("A",37,-122),MapMarker("B",38,-121)],true,$selected,260)
        $selected = "B"
        """#)
        XCTAssertTrue(state.errors.isEmpty)
        let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.components.registry, state: state)
        XCTAssertEqual(MapPoint.decode(context.value("markers")).map(\.id), ["A", "B"])
        XCTAssertEqual(context.binding("selected")?.wrappedValue, .string("B"))
        XCTAssertTrue(context.children("content").isEmpty)
    }
}
