import XCTest
import SwiftUI
import OpenUILang
import OpenUICore
@testable import OpenIntelligentSwiftUI

final class TransportCardTests: XCTestCase {
    @MainActor private func decode(_ body: String) throws -> (IntelligentUILibrary, OpenUIState, TransportData?) {
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        state.setSource("root = TransportCard(\(body))")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let root = try XCTUnwrap(state.root)
        let context = OpenUIComponentContext(element: root, registry: library.components.registry, state: state)
        return (library, state, TransportData(context.value("journey")))
    }
    @MainActor func testDirectJourneyKeepsExactFieldsAndUnknownsAbsent() throws {
        let (_, _, result) = try decode(#"{id:"f",legs:[{mode:"flight",from:"出发地机场",to:"目的地机场",fromCity:"出发市",toCity:"目的市",departureTime:"07:25",arrivalTime:"09:25",fromTerminal:"T1",toTerminal:"T3",carrier:"演示航司",serviceNumber:"DEMO1"}],priceText:"¥580 起",bookingURL:"/book?journey=f"}"#)
        let journey = try XCTUnwrap(result)
        XCTAssertEqual(journey.legs.count, 1)
        XCTAssertEqual(journey.legs.first?.fromCity, "出发市")
        XCTAssertEqual(journey.legs.first?.toCity, "目的市")
        XCTAssertEqual(journey.priceText, "¥580 起")
        XCTAssertEqual(journey.bookingURL, "/book?journey=f")
        XCTAssertEqual(journey.legs.first?.toTerminal, "T3")
        XCTAssertNil(journey.durationText, "Do not infer elapsed duration from local clocks")
        XCTAssertNil(journey.legs.first?.arrivalDayOffset)
    }
    @MainActor func testMissingDurationCarrierAndPriceKeepsCardHeight() throws {
        #if os(macOS)
        func height(_ body: String) throws -> CGFloat {
            let (library, state, _) = try decode(body)
            let renderer = ImageRenderer(content: IntelligentUIView(state: state, library: library).frame(width: 360))
            return try XCTUnwrap(renderer.nsImage).size.height
        }
        let full = #"{id:"full",legs:[{mode:"train",from:"A站",to:"B站",fromCity:"A市",toCity:"B市",departureDate:"2026-11-12",departureTime:"09:00",arrivalTime:"11:00",durationText:"2小时",carrier:"国铁",serviceNumber:"G1"}],durationText:"2小时",price:60,currency:"CNY",bookingURL:"/book"}"#
        let minimal = #"{id:"minimal",legs:[{mode:"train",from:"A站",to:"B站",fromCity:"A市",toCity:"B市",departureDate:"2026-11-12",departureTime:"09:00",arrivalTime:"11:00"}]}"#
        XCTAssertEqual(try height(full), try height(minimal), accuracy: 0.5)
        #endif
    }

    @MainActor func testTransferAndSeparateTicketsRetainEachLeg() throws {
        let (_, _, result) = try decode(#"{id:"m",legs:[{id:"a",mode:"train",from:"A站",to:"B站",departureTime:"21:00",arrivalTime:"22:00",departureDate:"2026-11-12",arrivalDate:"2026-11-12",bookingURL:"/book/train"},{id:"b",mode:"flight",from:"B机场",to:"C机场",departureTime:"08:00",arrivalTime:"11:00",departureDate:"2026-11-13",arrivalDate:"2026-11-13",departureZone:"UTC+8",arrivalZone:"UTC+8",bookingURL:"/book/flight"}],connections:[{afterLeg:0,changeStation:true,durationText:"10小时",notice:"自行换站"}],separateTickets:true}"#)
        let journey = try XCTUnwrap(result)
        XCTAssertEqual(journey.modeLabel, "联程")
        XCTAssertTrue(journey.separateTickets)
        XCTAssertEqual(journey.legs.map(\.bookingURL), ["/book/train", "/book/flight"])
        XCTAssertTrue(try XCTUnwrap(journey.connections.first).changeStation)
        XCTAssertEqual(journey.connections.first?.durationText, "10小时")
        XCTAssertEqual(journey.routeLabel, "1次中转")
        XCTAssertNil(journey.priceText, "Separate prices must not be summed into an invented fare")
        XCTAssertNil(journey.primaryBookingURL)
        XCTAssertEqual(journey.legs[0].temporalText, "2026-11-12")
        XCTAssertEqual(journey.legs[1].temporalText, "2026-11-13 · UTC+8")
    }
    @MainActor func testMultipleLegsDoNotInventConnectionsWithoutSourceFacts() throws {
        let (_, _, result) = try decode(#"{id:"source",legs:[{mode:"train",from:"A站",to:"B站",serviceNumber:"T1"},{mode:"train",from:"B站",to:"A站",serviceNumber:"T2"}],price:106,currency:"CNY",priceNote:"成人销售价；计价范围待核实"}"#)
        let journey = try XCTUnwrap(result)
        XCTAssertEqual(journey.routeLabel, "2段行程")
        XCTAssertFalse(journey.hasCompleteConnections)
        XCTAssertTrue(journey.connections.isEmpty)
        XCTAssertEqual(journey.price.text, "¥106")
        XCTAssertEqual(journey.legs.map(\.serviceNumber), ["T1", "T2"])
        let (_, _, partial) = try decode(#"{id:"partial",legs:[{mode:"train",from:"A",to:"B"},{mode:"bus",from:"B",to:"C"},{mode:"flight",from:"C",to:"D"}],connections:[{afterLeg:0}]}"#)
        XCTAssertEqual(partial?.routeLabel, "3段行程")
        XCTAssertEqual(partial?.modeLabel, "交通")
    }

    @MainActor func testIndependentJourneysExampleKeepsDirectionsAndParentQuoteSeparate() throws {
        let library = try IntelligentUILibrary(excludingComponents: ["ImageText", "YouTube", "Timer"])
        let example = try XCTUnwrap(library.selectedGenerationExamples.first { $0.contains("Independent outbound/return") })
        let start = try XCTUnwrap(example.range(of: "root = Col("))
        let source = String(example[start.lowerBound...])
        let state = library.makeState(); state.setSource(source)
        XCTAssertEqual(library.validationIssues(in: state, source: source), [])
        let root = try XCTUnwrap(state.root)
        let children: [EvaluatedElement] = OpenUIRenderChild.children(of: PropValue.value(root, "children") ?? .null).compactMap { child in
            if case .element(let element) = child.value { return element }
            return nil
        }
        let cards = children.filter { $0.typeName == "TransportCard" }
        XCTAssertEqual(cards.count, 2)
        let journeys = try cards.map { try XCTUnwrap(TransportData(PropValue.value($0, "journey"))) }
        XCTAssertEqual(journeys.map(\.id), ["outbound", "return"])
        XCTAssertEqual(journeys.map { $0.legs.count }, [1, 1])
        XCTAssertEqual(journeys.map(\.routeLabel), ["直达", "直达"])
        XCTAssertTrue(journeys.allSatisfy { $0.price.text == nil && $0.connections.isEmpty })
        XCTAssertTrue(journeys[0].priceNote?.contains("106") == true)
        XCTAssertEqual(journeys[0].primaryBookingURL, "https://example.com/source?journeyType=round&opaque=keep%3D%3D")
        XCTAssertNil(journeys[1].priceNote)
        XCTAssertNil(journeys[1].primaryBookingURL)
    }
    func testCalendarDayLabelsDoNotComputeFlightDuration() {
        XCTAssertEqual(TransportData.dayOffset(from: "2026-12-31", to: "2027-01-01"), 1)
        XCTAssertEqual(TransportData.dayOffset(from: "2026-11-12", to: "2026-11-11"), -1)
        XCTAssertEqual(TransportData.offsetText(1), "+1天")
        XCTAssertEqual(TransportData.offsetText(-1), "-1天")
        XCTAssertNil(TransportData.offsetText(0))
        XCTAssertNil(TransportData.dayOffset(from: nil, to: "2026-11-12"))
    }
    @MainActor func testInvalidTimeDateOffsetOrConnectionAreRejected() throws {
        let invalid = [
            #"{id:"bad",legs:[{mode:"flight",from:"A",to:"B",departureTime:"25:00"}]}"#,
            #"{id:"bad",legs:[{mode:"train",from:"A",to:"B",departureDate:"2026-02-30"}]}"#,
            #"{id:"bad",legs:[{mode:"train",from:"A",to:"B",departureDate:"2026-11-12",arrivalDate:"2026-11-13",arrivalDayOffset:0}]}"#,
            #"{id:"bad",legs:[{mode:"bus",from:"A",to:"B"}],connections:[{afterLeg:0}]}"#,
            #"{id:"bad",legs:[]}"#
        ]
        for body in invalid {
            let (library, state, result) = try decode(body)
            XCTAssertNil(result, body)
            XCTAssertFalse(library.validationIssues(in: try XCTUnwrap(state.root)).isEmpty, body)
        }
    }
    @MainActor func testBookingEventsPreserveJourneyAndSegmentURLs() async throws {
        let (library, state, result) = try decode(#"{id:"t",legs:[{mode:"train",from:"A",to:"B",bookingURL:"/segment?seat=2"}],bookingURL:"/journey?fare=raw"}"#)
        let journey = try XCTUnwrap(result)
        let context = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: library.components.registry, state: state)
        var events: [ActionEvent] = []
        state.onAction = { events.append($0) }
        for url in [journey.bookingURL, journey.legs.first?.bookingURL].compactMap({ $0 }) { _ = await context.perform(OpenUIActions.openURL(url)) }
        XCTAssertEqual(events.map { $0.params.first { $0.0 == "url" }?.1 }, [.string("/journey?fare=raw"), .string("/segment?seat=2")])
        XCTAssertEqual(journey.primaryBookingURL, "/journey?fare=raw")
        let (_, _, single) = try decode(#"{id:"single",legs:[{mode:"train",from:"A",to:"B",bookingURL:"/single-leg",durationText:"1小时"}]}"#)
        XCTAssertEqual(single?.primaryBookingURL, "/single-leg")
        XCTAssertEqual(single?.displayDurationText, "1小时")
    }
}
