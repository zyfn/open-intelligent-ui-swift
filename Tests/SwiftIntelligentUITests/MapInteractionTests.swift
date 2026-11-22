import XCTest
import SwiftLang
@testable import SwiftIntelligentUI

final class MapInteractionTests: XCTestCase {
    @MainActor func testLiteralSelectionSeedsLocalClicksWithoutRewritingTheArgument() throws {
        // 53df45b src/lib/components/map/map.tsx uses useStateField for the
        // optional selected literal; a pin click writes its label locally.
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        state.setSource(#"root=Map([MapMarker("A",30,120),MapMarker("B",31,121)],false,"A")"#)
        let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.components.registry, state: state)
        let points = MapPoint.decode(context.value("markers"))
        var selection = MapSelectionState()
        XCTAssertNil(context.binding("selected"))
        XCTAssertEqual(selection.requested(in: context), "A")
        XCTAssertTrue(selection.select("B", in: context, points: points))
        XCTAssertEqual(selection.requested(in: context), "B")
        XCTAssertEqual(context.string("selected"), "A", "A local click must not rewrite a literal argument")
        XCTAssertFalse(selection.select("missing", in: context, points: points))
        XCTAssertEqual(selection.requested(in: context), "B")
        selection.literalChanged()
        XCTAssertEqual(selection.requested(in: context), "A", "A changed external literal becomes the new seed")
    }

    @MainActor func testBoundSelectionRemainsAuthoritativeWhenNoVisiblePinMatches() throws {
        // 53df45b src/lib/components/map/map.tsx only compares labels for
        // highlighting. Filtering and recentering never call selection.setValue.
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        state.setSource("""
        root=Map([MapMarker("A",30,120,"one"),MapMarker("B",31,121,"two")],false,$selected)
        $selected="B"
        """)
        let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.components.registry, state: state)
        let points = MapPoint.decode(context.value("markers"))
        var selection = MapSelectionState()
        XCTAssertEqual(selection.requested(in: context), "B")
        XCTAssertTrue(selection.select("A", in: context, points: points))
        XCTAssertEqual(state.stateValue("$selected"), .string("A"))

        let visible = points.filter { $0.category == "two" }
        XCTAssertFalse(visible.contains { $0.label == selection.requested(in: context) })
        XCTAssertEqual(selection.requested(in: context), "A")
        XCTAssertEqual(state.stateValue("$selected"), .string("A"), "Hiding a pin must retain its bound label")
        XCTAssertFalse(selection.select("A", in: context, points: visible), "A hidden pin cannot issue a new click")
        XCTAssertEqual(state.stateValue("$selected"), .string("A"))

        state.setState("$selected", value: .string("missing"))
        XCTAssertEqual(selection.requested(in: context), "missing")
        XCTAssertFalse(points.contains { $0.label == selection.requested(in: context) })
        XCTAssertFalse(selection.select("missing", in: context, points: points))
        XCTAssertEqual(state.stateValue("$selected"), .string("missing"), "An unmatched binding is not cleanup work for the map")
    }

    @MainActor func testDuplicatePinsKeepIndependentIdentityButWriteTheSameLabel() throws {
        // 53df45b src/lib/components/map/map.tsx: placesOf retains duplicates;
        // pin handlers use place.label, never the suffixed rendering key.
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        state.setSource("""
        root=Map([MapMarker("同名地点",30,120),MapMarker("同名地点",31,121)],false,$selected)
        $selected=""
        """)
        let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.components.registry, state: state)
        let points = MapPoint.decode(context.value("markers"))
        XCTAssertEqual(points.map(\.label), ["同名地点", "同名地点"])
        XCTAssertEqual(Set(points.map(\.id)).count, 2)
        var selection = MapSelectionState()
        XCTAssertEqual(selection.requested(in: context), "", "A map never implicitly selects its first point")
        for point in points {
            state.setState("$selected", value: .string(""))
            XCTAssertTrue(selection.select(point.label, in: context, points: points))
            XCTAssertEqual(state.stateValue("$selected"), .string("同名地点"))
            XCTAssertEqual(points.filter { $0.label == selection.requested(in: context) }.count, 2)
        }
        let second = try XCTUnwrap(points.last)
        XCTAssertNotEqual(second.id, second.label)
        XCTAssertFalse(selection.select(second.id, in: context, points: points), "Rendering IDs must not leak into the Lang binding")
        XCTAssertEqual(state.stateValue("$selected"), .string("同名地点"))
    }

    @MainActor func testIncompleteMapCannotWriteSelectionAndReadinessRestoresInteraction() throws {
        let library = try OpenIntelligentUIComponents(), state = library.makeState()
        state.push("$selected=\"A\"\nroot=Map([MapMarker(\"A\",30,120),MapMarker(\"B\",31,121)],false,$selected")
        let pending = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.components.registry, state: state)
        let points = MapPoint.decode(pending.value("markers"))
        var selection = MapSelectionState()
        XCTAssertFalse(pending.canInteract)
        XCTAssertFalse(selection.select("B", in: pending, points: points))
        XCTAssertEqual(state.stateValue("$selected"), .string("A"))
        state.push(")")
        let ready = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.components.registry, state: state)
        XCTAssertTrue(ready.canInteract)
        XCTAssertTrue(selection.select("B", in: ready, points: points))
        XCTAssertEqual(state.stateValue("$selected"), .string("B"))
    }

    func testDuplicateSuffixesNeverOverwriteSuppliedLabelsOrEarlierRenderingIdentities() {
        // The pinned placesOf separates key from label. Native render IDs must
        // also avoid collisions with source labels that already contain suffixes.
        let first: [Value] = [marker("A", latitude: 30), marker("A", latitude: 31)]
        let prefix = MapPoint.decode(.array(first))
        let extended = MapPoint.decode(.array(first + [
            marker("A (2)", latitude: 32), marker("A", latitude: 33), marker("A (3)", latitude: 34)
        ]))
        XCTAssertEqual(extended.map(\.label), ["A", "A", "A (2)", "A", "A (3)"])
        XCTAssertEqual(extended.map(\.latitude), [30, 31, 32, 33, 34])
        XCTAssertEqual(Set(extended.map(\.id)).count, 5)
        XCTAssertEqual(Array(extended.prefix(2)).map(\.id), prefix.map(\.id), "Appending a suffixed source label must not recreate earlier pins")
        XCTAssertEqual(extended.map(\.order), [0, 1, 2, 3, 4])
    }

    func testFilteringAndStreamingKeepSourceOrdinalsAndCategoryOrder() {
        // 53df45b src/lib/components/map/map.tsx: markers.flat() keeps source
        // order; incomplete streaming markers are skipped without renumbering.
        let values: [Value] = [
            marker("A", latitude: 30, category: "  museums  "),
            .array([marker("invalid", latitude: 91), marker("B", latitude: 31, category: "gardens")]),
            marker("C", latitude: 32, category: "museums", partial: true),
            marker("D", latitude: 33, category: "   ")
        ]
        let streamed = MapPoint.decode(.array(values), streaming: true)
        XCTAssertEqual(streamed.map(\.label), ["A", "B", "D"])
        XCTAssertEqual(streamed.map(\.order), [0, 2, 4])
        XCTAssertEqual(MapPoint.categories(in: streamed), ["museums", "gardens"])
        let filtered = streamed.filter { $0.category == "gardens" }
        XCTAssertEqual(filtered.map { $0.order + 1 }, [3], "Category filters must not restart pin numbering")
        XCTAssertEqual(filtered.map(\.id), [streamed[1].id])

        let finished = MapPoint.decode(.array(values), streaming: false)
        XCTAssertEqual(finished.map(\.label), ["A", "B", "C", "D"])
        XCTAssertEqual(finished.map(\.order), [0, 2, 3, 4])
        XCTAssertEqual(MapPoint.categories(in: finished), ["museums", "gardens"])
        XCTAssertEqual(finished.filter { $0.label != "C" }.map(\.id), streamed.map(\.id))
    }

    private func marker(_ label: String, latitude: Double, category: String = "", partial: Bool = false) -> Value {
        .element(EvaluatedElement(typeName: "MapMarker", props: [
            ("label", .string(OpenUIString(label))), ("lat", .number(latitude)), ("lng", .number(120)),
            ("category", .string(OpenUIString(category)))
        ], partial: partial))
    }
}
