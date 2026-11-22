import Combine
import Foundation
import MapKit

/// A road request follows marker order. Labels and selection do not change it.
struct MapRouteRequest: Hashable {
    struct Coordinate: Hashable {
        let latitude: Double
        let longitude: Double
        var location: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    let coordinates: [Coordinate]
    let enabled: Bool
    init(points: [MapPoint], enabled: Bool) {
        self.coordinates = enabled ? points.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) } : []
        self.enabled = enabled
    }
}

enum MapRoutePhase: Equatable { case idle, loading, roads, direct }

struct MapRouteLeg {
    let polyline: MKPolyline

    static func directConnections(_ coordinates: [MapRouteRequest.Coordinate]) -> [Self] {
        guard coordinates.count > 1 else { return [] }
        return (0..<(coordinates.count - 1)).map { index in
            let pair = [coordinates[index].location, coordinates[index + 1].location]
            return Self(polyline: MKPolyline(coordinates: pair, count: pair.count))
        }
    }
}

/// The small cancellable operation used by this component's route task. Tests
/// supply an offline operation; this is not a public routing-provider API.
@MainActor struct MapRouteOperation {
    let calculate: @MainActor () async throws -> MKPolyline?
    let cancel: @MainActor () -> Void

    static func driving(from: MapRouteRequest.Coordinate, to: MapRouteRequest.Coordinate) -> Self {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from.location))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to.location))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        return Self(calculate: { try await directions.calculate().routes.first?.polyline },
                    cancel: { directions.cancel() })
    }
}

/// One owner per Map, shared by its inline and expanded surfaces. A component
/// lifecycle task triggers load; the model owns the work across cover/sheet
/// transitions. MKMapView updates merely draw the current legs.
@MainActor final class MapRouteModel: ObservableObject {
    // The official demo's route endpoint accepts at most 25 stops. MapKit
    // calculates adjacent legs; publish them only when the whole route succeeds.
    static let maximumPointCount = 25
    private static let cacheCapacity = 8
    typealias OperationFactory = @MainActor (MapRouteRequest.Coordinate, MapRouteRequest.Coordinate) -> MapRouteOperation

    private struct Snapshot {
        var request: MapRouteRequest?
        var phase: MapRoutePhase = .idle
        var legs: [MapRouteLeg] = []
        var overlayRevision = 0
    }
    @Published private var snapshot = Snapshot()
    var phase: MapRoutePhase { snapshot.phase }
    var legs: [MapRouteLeg] { snapshot.legs }
    var overlayRevision: Int { snapshot.overlayRevision }
    func matches(_ request: MapRouteRequest) -> Bool { snapshot.request == request }

    private let debounceNanoseconds: UInt64
    private let timeoutNanoseconds: UInt64
    private let operation: OperationFactory
    private var generation = UUID()
    private var currentRequest: MapRouteRequest?
    private var work: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var cache: [[MapRouteRequest.Coordinate]: [MapRouteLeg]] = [:]
    private var cacheOrder: [[MapRouteRequest.Coordinate]] = []

    init(debounceNanoseconds: UInt64 = 700_000_000,
         timeoutNanoseconds: UInt64 = 10_000_000_000, operation: OperationFactory? = nil) {
        self.debounceNanoseconds = debounceNanoseconds
        self.timeoutNanoseconds = timeoutNanoseconds
        self.operation = operation ?? { MapRouteOperation.driving(from: $0, to: $1) }
    }

    deinit {
        // Task handles are Sendable. The task's cancellation handler schedules
        // MKDirections.cancel on MainActor; deinit does not call isolated APIs.
        work?.cancel()
        deadline?.cancel()
    }

    func load(_ request: MapRouteRequest) {
        // Re-entering from an inline/expanded presentation preserves both
        // in-flight and settled state. Changed points or route enablement start
        // a new request; opening the map does not issue duplicate directions.
        guard currentRequest != request else { return }
        generation = UUID()
        let revision = generation
        work?.cancel(); work = nil
        deadline?.cancel(); deadline = nil
        currentRequest = request
        guard request.enabled, request.coordinates.count > 1 else {
            publish(.idle, legs: [])
            return
        }
        let direct = MapRouteLeg.directConnections(request.coordinates)
        guard request.coordinates.count <= Self.maximumPointCount else {
            publish(.direct, legs: direct)
            return
        }
        if let cached = cache[request.coordinates] {
            touch(request.coordinates)
            publish(.roads, legs: cached)
            return
        }
        publish(.loading, legs: direct)
        let delay = debounceNanoseconds
        let timeout = timeoutNanoseconds
        let makeOperation = operation
        work = Task { [weak self] in
            // Do not bind self strongly across either await: destroying the
            // Map must release its model and cancel the current directions.
            defer {
                if self?.generation == revision {
                    self?.deadline?.cancel(); self?.deadline = nil
                    self?.work = nil
                }
            }
            do { try await Task.sleep(nanoseconds: delay) }
            catch { return }
            guard self?.generation == revision, !Task.isCancelled else { return }
            self?.deadline = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: timeout) }
                catch { return }
                guard self?.generation == revision, !Task.isCancelled else { return }
                // One deadline covers the complete itinerary, as the official
                // route fetch does. A late MapKit result cannot replace fallback.
                self?.generation = UUID()
                self?.work?.cancel(); self?.work = nil
                self?.deadline = nil
                self?.publish(.direct, legs: direct)
            }
            var result: [MapRouteLeg] = []
            for index in direct.indices {
                guard self?.generation == revision, !Task.isCancelled else { return }
                let pending = makeOperation(request.coordinates[index], request.coordinates[index + 1])
                do {
                    let polyline = try await withTaskCancellationHandler(operation: {
                        try await pending.calculate()
                    }, onCancel: {
                        Task { @MainActor in pending.cancel() }
                    })
                    guard self?.generation == revision, !Task.isCancelled else { return }
                    guard let polyline, polyline.pointCount > 1 else {
                        self?.publish(.direct, legs: direct)
                        return
                    }
                    result.append(MapRouteLeg(polyline: polyline))
                } catch {
                    guard self?.generation == revision, !Task.isCancelled else { return }
                    self?.publish(.direct, legs: direct)
                    return
                }
            }
            guard self?.generation == revision, !Task.isCancelled else { return }
            self?.cache[request.coordinates] = result
            self?.touch(request.coordinates)
            while let owner = self, owner.cacheOrder.count > Self.cacheCapacity {
                owner.cache.removeValue(forKey: owner.cacheOrder.removeFirst())
            }
            self?.publish(.roads, legs: result)
        }
    }

    private func touch(_ key: [MapRouteRequest.Coordinate]) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }

    private func publish(_ phase: MapRoutePhase, legs: [MapRouteLeg]) {
        snapshot = Snapshot(request: currentRequest, phase: phase, legs: legs,
                            overlayRevision: snapshot.overlayRevision &+ 1)
    }
}
