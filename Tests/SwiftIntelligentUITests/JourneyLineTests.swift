import XCTest
import SwiftLang
@testable import SwiftIntelligentUI

final class JourneyLineTests: XCTestCase {
    @MainActor func testJourneyLineIsAvailableAndRemovedComponentsStayAbsent() throws {
        let library = try OpenIntelligentUIComponents()
        XCTAssertNotNil(library.components.registry["JourneyLine"])
        XCTAssertNil(library.components.registry["TransportCard"])
        XCTAssertNil(library.readerComponents.registry["TransportCard"])
        let spec = try XCTUnwrap(library.components.toSpec().components.first { $0.name == "JourneyLine" })
        XCTAssertTrue(spec.signature.contains("JourneyLine"))
    }

    @MainActor func testJourneyLineComposesWithOrdinaryEndpointContent() throws {
        let library = try OpenIntelligentUIComponents()
        let source = #"root = Row([Col([Title("08:30"), Text("北京南站")]), JourneyLine("train"), Col([Title("13:15"), Text("上海虹桥站")])])"#
        let state = library.makeState()
        state.setSource(source)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertEqual(library.validationIssues(in: state, source: source), [])
        XCTAssertEqual(state.root?.typeName, "Row")
    }

    func testTransportModesHaveExplicitSymbols() {
        XCTAssertEqual(JourneyLineComponent.symbol(for: "flight"), "airplane")
        XCTAssertEqual(JourneyLineComponent.symbol(for: "train"), "tram.fill")
        XCTAssertEqual(JourneyLineComponent.symbol(for: "bus"), "bus.fill")
        XCTAssertEqual(JourneyLineComponent.symbol(for: "taxi"), "car.fill")
        XCTAssertEqual(JourneyLineComponent.symbol(for: "ferry"), "ferry.fill")
        XCTAssertNil(JourneyLineComponent.symbol(for: "unknown"))
    }
}
