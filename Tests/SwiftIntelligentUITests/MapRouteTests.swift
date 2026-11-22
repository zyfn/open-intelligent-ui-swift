import Combine
import MapKit
import XCTest
@testable import SwiftIntelligentUI

@MainActor final class MapRouteTests: XCTestCase {
    func testRequestIdentityTracksMarkerCoordinatesAndOrder() {
        let original = points([0, 1])
        let renamed = original.map { MapPoint(id: "Renamed " + $0.id, label: "Renamed " + $0.label,
            latitude: $0.latitude, longitude: $0.longitude, category: "Other", icon: "🏛️") }
        XCTAssertEqual(MapRouteRequest(points: original, enabled: true), MapRouteRequest(points: renamed, enabled: true))
        XCTAssertNotEqual(MapRouteRequest(points: original, enabled: true), MapRouteRequest(points: original, enabled: false))
        XCTAssertNotEqual(MapRouteRequest(points: original, enabled: true), MapRouteRequest(points: Array(original.reversed()), enabled: true))
    }

    func testDisabledSinglePointAndOversizedRoutesNeverStartDirections() async {
        let model = MapRouteModel(debounceNanoseconds: 0) { _, _ in
            XCTFail("This state must not make a directions request")
            return MapRouteOperation(calculate: { nil }, cancel: {})
        }
        model.load(MapRouteRequest(points: points([0, 1]), enabled: false))
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.legs.isEmpty)
        model.load(MapRouteRequest(points: points([0]), enabled: true))
        XCTAssertEqual(model.phase, .idle)
        // 53df45b src/app/api/street-route/route.ts caps the entire route at 25 stops.
        model.load(MapRouteRequest(points: points(Array(0..<26)), enabled: true))
        XCTAssertEqual(model.phase, .direct)
        XCTAssertEqual(model.legs.count, 25)
        assertDirectConnections(model, for: points(Array(0..<26)))
    }

    func testOneFailedLegFallsBackForTheWholeRouteWithoutPublishingPartialRoads() async throws {
        let source = OfflineDirections()
        let model = MapRouteModel(debounceNanoseconds: 0, operation: source.operation)
        let request = MapRouteRequest(points: points([0, 1, 2]), enabled: true)
        model.load(request)
        defer { source.finishAll() }
        await fulfillment(of: [source.whenStarted(1)], timeout: 2)
        XCTAssertTrue(model.matches(request))
        XCTAssertEqual(model.phase, .loading)
        XCTAssertEqual(model.legs.count, 2)
        assertDirectConnections(model, for: points([0, 1, 2]))
        try XCTUnwrap(source.pending.first).finish(.success(polyline()))
        await fulfillment(of: [source.whenStarted(2)], timeout: 2)
        XCTAssertEqual(model.phase, .loading)
        // The official route hook returns one completed road geometry or null;
        // successful intermediate legs must not create a mixed route state.
        assertDirectConnections(model, for: points([0, 1, 2]))
        try XCTUnwrap(source.pending.last).finish(.failure(URLError(.notConnectedToInternet)))
        await settled(model)
        XCTAssertEqual(model.phase, .direct)
        XCTAssertEqual(model.legs.count, 2)
        assertDirectConnections(model, for: points([0, 1, 2]))
        model.load(request)
        XCTAssertEqual(source.pending.count, 2, "Opening another presentation must not retry a failed request")
    }

    func testAllLegsPublishTogetherAfterTheLastRoadArrives() async throws {
        let source = OfflineDirections()
        let model = MapRouteModel(debounceNanoseconds: 0, operation: source.operation)
        model.load(MapRouteRequest(points: points([0, 1, 2]), enabled: true))
        defer { source.finishAll() }
        await fulfillment(of: [source.whenStarted(1)], timeout: 2)
        let revision = model.overlayRevision
        let firstRoad = polyline(), secondRoad = polyline()
        try XCTUnwrap(source.pending.first).finish(.success(firstRoad))
        await fulfillment(of: [source.whenStarted(2)], timeout: 2)
        XCTAssertEqual(model.phase, .loading)
        XCTAssertEqual(model.overlayRevision, revision)
        try XCTUnwrap(source.pending.last).finish(.success(secondRoad))
        await settled(model)
        XCTAssertEqual(model.phase, .roads)
        XCTAssertEqual(model.legs.count, 2)
        XCTAssertTrue(model.legs.first?.polyline === firstRoad)
        XCTAssertTrue(model.legs.last?.polyline === secondRoad)
        XCTAssertEqual(model.overlayRevision, revision + 1)
    }

    func testOfflineFallbackIsNotCachedWhenRouteIsDisabledAndEnabledAgain() async {
        var calls = 0
        let road = polyline()
        let model = MapRouteModel(debounceNanoseconds: 0) { _, _ in
            calls += 1
            let attempt = calls
            return MapRouteOperation(calculate: {
                if attempt == 1 { throw URLError(.notConnectedToInternet) }
                return road
            }, cancel: {})
        }
        model.load(MapRouteRequest(points: points([0, 1]), enabled: true))
        await settled(model)
        XCTAssertEqual(model.phase, .direct)
        assertDirectConnections(model, for: points([0, 1]))
        model.load(MapRouteRequest(points: points([0, 1]), enabled: false))
        model.load(MapRouteRequest(points: points([0, 1]), enabled: true))
        await settled(model)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(model.phase, .roads)
        XCTAssertEqual(model.legs.count, 1)
        XCTAssertTrue(model.legs.first?.polyline === road)
    }

    func testTwentyFiveSuppliedStopsCanProduceACompleteRoute() async {
        var calls = 0
        let road = polyline()
        let model = MapRouteModel(debounceNanoseconds: 0) { _, _ in
            calls += 1
            return MapRouteOperation(calculate: { road }, cancel: {})
        }
        model.load(MapRouteRequest(points: points(Array(0..<25)), enabled: true))
        await settled(model)
        XCTAssertEqual(calls, 24)
        XCTAssertEqual(model.phase, .roads)
        XCTAssertEqual(model.legs.count, 24)
    }

    func testCompletedRoadCacheIsSharedAndBoundedToEightItineraries() async {
        var calls = 0
        let road = polyline()
        let model = MapRouteModel(debounceNanoseconds: 0) { _, _ in
            calls += 1
            return MapRouteOperation(calculate: { road }, cancel: {})
        }
        let first = MapRouteRequest(points: points([0, 1]), enabled: true)
        model.load(first)
        await settled(model)
        model.load(first)
        XCTAssertEqual(calls, 1, "Another surface consuming this Map must reuse its completed route")
        for index in 1...8 {
            model.load(MapRouteRequest(points: points([index * 2, index * 2 + 1]), enabled: true))
            await settled(model)
        }
        XCTAssertEqual(calls, 9)
        model.load(MapRouteRequest(points: points([14, 15]), enabled: true))
        XCTAssertEqual(calls, 9)
        model.load(first)
        await settled(model)
        XCTAssertEqual(calls, 10, "The ninth distinct success evicts the oldest of eight entries")
    }

    func testReplacingPointsCancelsDirectionsAndRejectsLateOldResults() async throws {
        let source = OfflineDirections(resumesOnCancel: false)
        let model = MapRouteModel(debounceNanoseconds: 0, operation: source.operation)
        let oldRequest = MapRouteRequest(points: points([0, 1]), enabled: true)
        let newRequest = MapRouteRequest(points: points([3, 4]), enabled: true)
        model.load(oldRequest)
        defer { source.finishAll() }
        await fulfillment(of: [source.whenStarted(1)], timeout: 2)
        let old = try XCTUnwrap(source.pending.first)
        model.load(newRequest)
        await fulfillment(of: [source.whenStarted(2)], timeout: 2)
        XCTAssertTrue(old.wasCancelled)
        try XCTUnwrap(source.pending.last).finish(.success(polyline()))
        await settled(model)
        let revision = model.overlayRevision
        XCTAssertEqual(model.phase, .roads)
        XCTAssertTrue(model.matches(newRequest))
        old.finish(.success(polyline()))
        await fulfillment(of: [old.returned], timeout: 2)
        await Task.yield()
        XCTAssertEqual(model.overlayRevision, revision)
        XCTAssertTrue(model.matches(newRequest), "Even a client ignoring cancellation must not replace the current route")
    }

    func testDisablingRouteDuringDebounceNeverDispatchesDirections() async {
        var calls = 0
        let model = MapRouteModel(debounceNanoseconds: 30_000_000_000) { _, _ in
            calls += 1
            return MapRouteOperation(calculate: { nil }, cancel: {})
        }
        model.load(MapRouteRequest(points: points([0, 1]), enabled: true))
        XCTAssertEqual(model.phase, .loading)
        model.load(MapRouteRequest(points: points([0, 1]), enabled: false))
        await Task.yield()
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(model.phase, .idle)
    }

    func testPresentationTaskCancellationAndRepeatedTriggersKeepOneRequest() async throws {
        let source = OfflineDirections()
        let model = MapRouteModel(debounceNanoseconds: 0, operation: source.operation)
        let request = MapRouteRequest(points: points([0, 1]), enabled: true)
        let trigger = Task { model.load(request) }
        await trigger.value
        defer { source.finishAll() }
        await fulfillment(of: [source.whenStarted(1)], timeout: 2)
        let pending = try XCTUnwrap(source.pending.first)
        // Cover/sheet transitions may cancel a scene task. The Map's retained
        // model owns the request, so a second presentation only reuses it.
        trigger.cancel()
        model.load(request)
        XCTAssertEqual(model.phase, .loading)
        pending.finish(.success(polyline()))
        await settled(model)
        XCTAssertFalse(pending.wasCancelled)
        XCTAssertEqual(source.pending.count, 1)
        XCTAssertEqual(model.phase, .roads)
        let revision = model.overlayRevision
        model.load(request)
        XCTAssertEqual(model.overlayRevision, revision)
        XCTAssertEqual(source.pending.count, 1)
    }

    func testReleasingMapModelCancelsItsActiveDirections() async throws {
        let source = OfflineDirections()
        var model: MapRouteModel? = MapRouteModel(debounceNanoseconds: 0, operation: source.operation)
        weak var released = model
        model?.load(MapRouteRequest(points: points([0, 1]), enabled: true))
        defer { source.finishAll() }
        await fulfillment(of: [source.whenStarted(1)], timeout: 2)
        let pending = try XCTUnwrap(source.pending.first)
        model = nil
        XCTAssertNil(released, "The route job must not retain its Map model across an await")
        await fulfillment(of: [pending.cancelled], timeout: 2)
        XCTAssertTrue(pending.wasCancelled)
    }

    func testItineraryDeadlineCancelsDirectionsAndRejectsLateResults() async throws {
        let source = OfflineDirections(resumesOnCancel: false)
        let model = MapRouteModel(debounceNanoseconds: 0, timeoutNanoseconds: 25_000_000,
                                  operation: source.operation)
        let request = MapRouteRequest(points: points([0, 1]), enabled: true)
        model.load(request)
        defer { source.finishAll() }
        await fulfillment(of: [source.whenStarted(1)], timeout: 2)
        let pending = try XCTUnwrap(source.pending.first)
        await fulfillment(of: [pending.cancelled], timeout: 2)
        XCTAssertEqual(model.phase, .direct)
        XCTAssertTrue(model.matches(request))
        assertDirectConnections(model, for: points([0, 1]))
        let revision = model.overlayRevision
        pending.finish(.success(polyline()))
        await fulfillment(of: [pending.returned], timeout: 2)
        await Task.yield()
        XCTAssertEqual(model.phase, .direct)
        XCTAssertEqual(model.overlayRevision, revision)
    }

    private func assertDirectConnections(_ model: MapRouteModel, for stops: [MapPoint],
                                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(model.legs.count, max(0, stops.count - 1), file: file, line: line)
        for (index, leg) in model.legs.enumerated() where index + 1 < stops.count {
            XCTAssertEqual(leg.polyline.pointCount, 2, file: file, line: line)
            guard leg.polyline.pointCount == 2 else { continue }
            for endpoint in 0...1 {
                let coordinate = leg.polyline.points()[endpoint].coordinate
                XCTAssertEqual(coordinate.latitude, stops[index + endpoint].latitude,
                               accuracy: 0.000001, file: file, line: line)
                XCTAssertEqual(coordinate.longitude, stops[index + endpoint].longitude,
                               accuracy: 0.000001, file: file, line: line)
            }
        }
    }

    private func settled(_ model: MapRouteModel) async {
        guard model.phase == .loading else { return }
        let finished = expectation(description: "route settled")
        var fulfilled = false
        let observation = model.objectWillChange.sink {
            Task { @MainActor in
                if model.phase != .loading, !fulfilled { fulfilled = true; finished.fulfill() }
            }
        }
        await fulfillment(of: [finished], timeout: 2)
        observation.cancel()
    }

    private func points(_ indexes: [Int]) -> [MapPoint] {
        indexes.map { MapPoint(id: "Place \($0)", label: "Place \($0)",
            latitude: 30 + Double($0) / 100, longitude: 120 + Double($0) / 100,
            category: "", icon: "") }
    }

    private func polyline() -> MKPolyline {
        let coordinates = [CLLocationCoordinate2D(latitude: 30, longitude: 120),
                           CLLocationCoordinate2D(latitude: 30.01, longitude: 120.01)]
        return MKPolyline(coordinates: coordinates, count: coordinates.count)
    }
}

@MainActor private final class OfflineDirections {
    final class Pending {
        private var continuation: CheckedContinuation<MKPolyline?, Error>?
        private var result: Result<MKPolyline?, Error>?
        private let resumesOnCancel: Bool
        private(set) var wasCancelled = false
        let cancelled = XCTestExpectation(description: "directions cancelled")
        let returned = XCTestExpectation(description: "directions returned")

        init(resumesOnCancel: Bool) { self.resumesOnCancel = resumesOnCancel }
        func value() async throws -> MKPolyline? {
            defer { returned.fulfill() }
            if let result { return try result.get() }
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        func finish(_ result: Result<MKPolyline?, Error>) {
            guard self.result == nil else { return }
            self.result = result
            continuation?.resume(with: result)
            continuation = nil
        }
        func cancel() {
            guard !wasCancelled else { return }
            wasCancelled = true
            cancelled.fulfill()
            if resumesOnCancel { finish(.failure(CancellationError())) }
        }
    }

    private let resumesOnCancel: Bool
    private var startExpectations: [(Int, XCTestExpectation)] = []
    private(set) var pending: [Pending] = []

    init(resumesOnCancel: Bool = true) { self.resumesOnCancel = resumesOnCancel }
    func operation(from: MapRouteRequest.Coordinate, to: MapRouteRequest.Coordinate) -> MapRouteOperation {
        let item = Pending(resumesOnCancel: resumesOnCancel)
        pending.append(item)
        for (count, expectation) in startExpectations where pending.count >= count { expectation.fulfill() }
        startExpectations.removeAll { pending.count >= $0.0 }
        return MapRouteOperation(calculate: { try await item.value() }, cancel: { item.cancel() })
    }
    func whenStarted(_ count: Int) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "directions request \(count) started")
        if pending.count >= count { expectation.fulfill() }
        else { startExpectations.append((count, expectation)) }
        return expectation
    }
    func finishAll() {
        pending.forEach { $0.finish(.failure(CancellationError())) }
    }
}
