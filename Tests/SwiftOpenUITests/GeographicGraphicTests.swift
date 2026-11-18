import SwiftLang
import XCTest
@testable import SwiftOpenUI

final class GeographicGraphicTests: XCTestCase {
  @MainActor func testDefaultLibraryOwnsExistingHostContractsAndContainerSlots() throws {
    let library = try OpenUIComponents.library()
    let fixture = try XCTUnwrap(Bundle.module.url(forResource: "test-library-spec", withExtension: "json",
                                                  subdirectory: "Fixtures/AgentCasesContract"))
    let previous = try LibrarySpec(jsonString: String(contentsOf: fixture, encoding: .utf8))
    for name in ["Map", "MapPoint", "SVG", "Card", "TabItem", "AccordionItem"] {
      let old = try XCTUnwrap(previous.components.first { $0.name == name }?.signature)
      let expected = ["Card", "TabItem", "AccordionItem"].contains(name)
        ? old.replacingOccurrences(of: " | SVG)[]", with: " | SVG | JourneyLine)[]") : old
      XCTAssertEqual(library.toSpec().components.first { $0.name == name }?.signature, expected, name)
    }
    let state = OpenUIState(schema: library.library.toSchema())
    for source in [
      "root=Card([Map([MapPoint(\"A\",30,120)])])",
      "root=Tabs([TabItem(\"a\",\"A\",[SVG(\"<svg viewBox='0 0 2 1'/>\")])])",
      "root=Accordion([AccordionItem(\"a\",\"A\",[Map([MapPoint(\"A\",30,120)])])])"
    ] { state.setSource(source); XCTAssertTrue(state.errors.isEmpty, "\(source): \(state.errors)") }
  }
  func testSVGRequiresFinitePositiveViewBoxAndRejectsActiveOrExternalContent() {
    XCTAssertEqual(NativeSVGDocument.parse("<svg viewBox='0 0 200 100'><path d='M0 0 L10 10'/></svg>")?.ratio, 2)
    for source in ["<svg/>", "<svg viewBox='0 0 0 1'/>", "<svg viewBox='0 0 NaN 1'/>",
      "<svg viewBox='0 0 1 1'><script>alert(1)</script></svg>",
      "<svg viewBox='0 0 1 1' onload='x()'/>",
      "<svg viewBox='0 0 1 1'><image href='https://example.com/a.png'/></svg>",
      "<!DOCTYPE svg [<!ENTITY x 'a'>]><svg viewBox='0 0 1 1'/>",
      "<svg viewBox='0 0 1 1'><foreignObject/></svg>",
      "<svg viewBox='0 0 1 1'><animateMotion dur='1s'/></svg>",
      "<svg viewBox='0 0 1e308 1e-308'/>",
      "<svg viewBox='0 0 1e-308 1e308'/>",
      "<svg viewBox='0 0 1 1' preserveAspectRatio='none'/>"] {
      XCTAssertNil(NativeSVGDocument.parse(source), source)
    }
    XCTAssertNil(NativeSVGDocument.parse(String(repeating: "x", count: 1_000_001)))
  }
  @MainActor func testMapKeepsPlaceIdentityWhenOptionalMetadataArrives() throws {
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    func decode(_ source: String) -> [NativeMapPlace] {
      state.setSource(source)
      return NativeMapPlace.decode(PropValue.value(state.root!, "points"), crs: "wgs84")
    }
    let first = decode("root=Map([MapPoint(\"A\",30,120)])")
    let next = decode("root=Map([MapPoint(\"B\",31,121),MapPoint(\"A\",30,120,null,null,\"Details\")])")
    XCTAssertEqual(first[0].id, next[1].id)
    XCTAssertEqual(first[0].number, 1)
    XCTAssertEqual(next[1].number, 2)
    let filtered = decode("root=Map([MapPoint(\"A\",30,120),MapPoint(\"A\",30,120),MapPoint(\"Bad\",91,120),MapPoint(\"B\",31,121)])")
    XCTAssertEqual(filtered.map(\.title), ["A", "B"])
    XCTAssertEqual(filtered.map(\.number), [1, 2])
    XCTAssertTrue(NativeMapPlace.decode(PropValue.value(state.root!, "points"), crs: "unknown").isEmpty)
  }
  @MainActor func testMapPreservesSourceCoordinatesUnlessTheHostSelectsATarget() throws {
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    let gcjLatitude = 39.910226
    let gcjLongitude = 116.403714
    let wgsLatitude = 39.908823
    let wgsLongitude = 116.397470

    func coordinate(_ program: String, presentation: OpenUIPresentation) throws -> NativeMapPlace {
      state.setSource(program)
      XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
      let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.registry,
                                           state: state, presentation: presentation)
      return try XCTUnwrap(NativeMapPlace.decode(context).first)
    }

    let unqualified = "root=Map([MapPoint(\"A\",\(gcjLatitude),\(gcjLongitude))])"
    var presentation = OpenUIPresentation()
    let mainland = try coordinate(unqualified, presentation: presentation).coordinate
    XCTAssertEqual(mainland.latitude, gcjLatitude)
    XCTAssertEqual(mainland.longitude, gcjLongitude)

    let explicitWGS = "root=Map([MapPoint(\"A\",\(wgsLatitude),\(wgsLongitude))], \"wgs84\")"
    let originalWGS = try coordinate(explicitWGS, presentation: presentation).coordinate
    XCTAssertEqual(originalWGS.latitude, wgsLatitude)
    XCTAssertEqual(originalWGS.longitude, wgsLongitude)

    presentation.mapBasemapCRS = .gcj02
    let projected = try coordinate(explicitWGS, presentation: presentation).coordinate
    XCTAssertEqual(projected.latitude, gcjLatitude, accuracy: 0.00001)
    XCTAssertEqual(projected.longitude, gcjLongitude, accuracy: 0.00001)

    presentation.mapBasemapCRS = .wgs84
    let converted = try coordinate(unqualified, presentation: presentation).coordinate
    XCTAssertEqual(converted.latitude, wgsLatitude, accuracy: 0.00001)
    XCTAssertEqual(converted.longitude, wgsLongitude, accuracy: 0.00001)
    let unchanged = try coordinate(explicitWGS, presentation: presentation).coordinate
    XCTAssertEqual(unchanged.latitude, wgsLatitude)
    XCTAssertEqual(unchanged.longitude, wgsLongitude)
  }

  @MainActor func testStreamingPointsAppearWhenTheirCoordinatesCloseAndConversionWaitsForCRS() throws {
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    var convert = OpenUIPresentation()
    convert.mapBasemapCRS = .gcj02
    let prepared = NativeMapPlaceCache()

    func places(_ presentation: OpenUIPresentation = .init()) throws -> [NativeMapPlace] {
      let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.registry,
                                           state: state, presentation: presentation)
      return prepared.places(for: context)
    }

    state.push(#"root=Map([MapPoint("北门",39.908823,116.397470,"/north"#)
    let early = try places()
    XCTAssertEqual(early.map(\.title), ["北门"])
    XCTAssertEqual(early.first?.coordinate.longitude, 116.397470)
    XCTAssertNil(early.first?.image)
    XCTAssertNil(early.first?.url)
    XCTAssertTrue(try places(convert).isEmpty)

    state.push(#".jpg","https://map.example/no"#)
    let withPhoto = try XCTUnwrap(places().first)
    XCTAssertEqual(withPhoto.id, early.first?.id)
    XCTAssertEqual(withPhoto.image, "/north.jpg")
    XCTAssertNil(withPhoto.url, "The detail link is still incomplete")
    state.push(#"rth"),MapPoint("南门",31,12"#)
    let first = try places()
    XCTAssertEqual(first.map(\.title), ["北门"], "The second longitude is still open")
    XCTAssertEqual(first.first?.id, early.first?.id)
    XCTAssertEqual(first.first?.image, "/north.jpg")
    XCTAssertEqual(first.first?.url, "https://map.example/north")

    state.push(#"1)],"wg"#)
    let both = try places()
    XCTAssertEqual(both.map(\.title), ["北门", "南门"])
    XCTAssertEqual(both.last?.coordinate.longitude, 121)
    XCTAssertFalse(try XCTUnwrap(state.root).sourceReadiness["crs"].complete)
    XCTAssertTrue(try places(convert).isEmpty)

    state.push(#"s84")"#)
    state.complete()
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    XCTAssertEqual(try places().map(\.id), both.map(\.id))
    XCTAssertEqual(try XCTUnwrap(places(convert).first).coordinate.latitude, 39.910226, accuracy: 0.00001)
  }

  func testCoordinateConversionDoesNotShiftNeighborsInsideTheOldRectangle() {
    let points: [(String, Double, Double)] = [
      ("Seoul", 37.5665, 126.9780),
      ("Hanoi", 21.0285, 105.8542),
      ("Ulaanbaatar", 47.9185, 106.9177),
    ]
    let directions: [(OpenUIMapCoordinateSystem, OpenUIMapCoordinateSystem)] = [(.wgs84, .gcj02), (.gcj02, .wgs84)]
    for (city, latitude, longitude) in points {
      for (source, target) in directions {
        let point = NativeMapCoordinates.convert(latitude: latitude, longitude: longitude, from: source, to: target)
        XCTAssertEqual(point.latitude, latitude, city)
        XCTAssertEqual(point.longitude, longitude, city)
      }
    }
  }

  func testCoordinateConversionLeavesWGS84AndOutsideChinaAlone() {
    let wgs = NativeMapCoordinates.convert(latitude: 30.25, longitude: 120.15, from: .wgs84, to: .wgs84)
    XCTAssertEqual(wgs.latitude, 30.25)
    let paris = NativeMapCoordinates.convert(latitude: 48.85, longitude: 2.35, from: .gcj02, to: .wgs84)
    XCTAssertEqual(paris.longitude, 2.35)
    let converted = NativeMapCoordinates.convert(latitude: 39.910226, longitude: 116.403714, from: .gcj02, to: .wgs84)
    XCTAssertEqual(converted.latitude, 39.908823, accuracy: 0.00001)
    XCTAssertEqual(converted.longitude, 116.397470, accuracy: 0.00001)
    let haikou = NativeMapCoordinates.convert(latitude: 20.044, longitude: 110.1983, from: .wgs84, to: .gcj02)
    XCTAssertNotEqual(haikou.longitude, 110.1983, "Conversion still handles the separate Hainan polygon")
    XCTAssertNil(NativeMapValue.url("https://user:secret@example.com", baseURL: nil))
    XCTAssertNil(NativeMapValue.url("javascript:alert(1)", baseURL: nil))
  }
}
