import XCTest
import MapKit
@testable import SwiftIntelligentUI

final class MapCameraGeometryTests: XCTestCase {
    func testFitKeepsSuppliedPointsInsideTheVisibleMapBelowControls() throws {
        let points = [CLLocationCoordinate2D(latitude: 30.238678, longitude: 120.173273),
                      CLLocationCoordinate2D(latitude: 30.237273, longitude: 120.172906),
                      CLLocationCoordinate2D(latitude: 30.252443, longitude: 120.13459),
                      CLLocationCoordinate2D(latitude: 30.251243, longitude: 120.143778)].map(MKMapPoint.init)
        let content = points.reduce(MKMapRect.null) { $0.union(MKMapRect(x: $1.x - 500, y: $1.y - 500, width: 1000, height: 1000)) }
        for size in [CGSize(width: 320, height: 200), CGSize(width: 320, height: 400), CGSize(width: 402, height: 780)] {
            let visible = try XCTUnwrap(MapCameraGeometry.visibleArea(size: size, top: 55, bottom: 35))
            let rect = try XCTUnwrap(MapCameraGeometry.fit(content, size: size, visible: visible))
            for point in points {
                let screen = CGPoint(x: (point.x - rect.origin.x) / rect.width * size.width,
                                     y: (point.y - rect.origin.y) / rect.height * size.height)
                XCTAssertTrue(visible.contains(screen), "\(screen) outside \(visible)")
            }
        }
    }
    func testZeroOrOccludedViewportWaitsForLayout() {
        XCTAssertNil(MapCameraGeometry.visibleArea(size: .zero, top: 84, bottom: 148))
        XCTAssertNil(MapCameraGeometry.visibleArea(size: CGSize(width: 104, height: 100), top: 84, bottom: 148))
    }
    func testHostOcclusionUsesAllEdgesAndRejectsUnusableViewports() throws {
        let size = CGSize(width: 402, height: 780)
        let visible = try XCTUnwrap(MapCameraGeometry.visibleArea(size: size, top: 96, bottom: 220, left: 20, right: 10))
        XCTAssertEqual(visible.minX, 60)
        XCTAssertEqual(visible.width, 292)
        XCTAssertEqual(visible.height, 432)
        XCTAssertNil(MapCameraGeometry.visibleArea(size: size, top: .nan, bottom: 0))
        XCTAssertNil(MapCameraGeometry.visibleArea(size: size, top: 400, bottom: 400))
    }

    func testSinglePointAutomaticFitDoesNotZoomCloserThanTheOfficialLimit() throws {
        // 53df45b src/lib/components/map/map.tsx: automatic fitBounds uses
        // maxZoom: 13. MapLibre's normalized world is 512 * 2^zoom pixels wide.
        let point = MapPoint(id: "A", label: "A", latitude: 30.238678, longitude: 120.173273, category: "", icon: "")
        let content = try XCTUnwrap(MapCameraGeometry.contentBounds(points: [point]))
        let minimumScale = MKMapRect.world.width / (512 * pow(2.0, 13.0))
        for size in [CGSize(width: 320, height: 200), CGSize(width: 900, height: 640)] {
            let visible = try XCTUnwrap(MapCameraGeometry.visibleArea(size: size, top: 70, bottom: 18))
            let fitted = try XCTUnwrap(MapCameraGeometry.fit(content, size: size, visible: visible))
            XCTAssertEqual(fitted.width / Double(size.width), minimumScale, accuracy: 0.000001,
                "A lone point must remain at a neighborhood-scale overview rather than filling the map with its tiny bounds")
            XCTAssertEqual(fitted.height / Double(size.height), minimumScale, accuracy: 0.000001)
        }
    }

    func testExplicitRecenterAllowsOneZoomLevelCloserWithoutExceedingFourteen() throws {
        // 53df45b src/lib/components/map/map.tsx: the recenter handler uses
        // maxZoom: 14, while the automatic fit uses 13.
        let point = MapPoint(id: "A", label: "A", latitude: 30.238678, longitude: 120.173273, category: "", icon: "")
        let content = try XCTUnwrap(MapCameraGeometry.contentBounds(points: [point]))
        let size = CGSize(width: 600, height: 400)
        let visible = try XCTUnwrap(MapCameraGeometry.visibleArea(size: size, top: 70, bottom: 18))
        let automatic = try XCTUnwrap(MapCameraGeometry.fit(content, size: size, visible: visible))
        let recentered = try XCTUnwrap(MapCameraGeometry.fit(content, size: size, visible: visible, maximumZoom: 14))
        let minimumScale = MKMapRect.world.width / (512 * pow(2.0, 14.0))
        XCTAssertEqual(recentered.width / Double(size.width), minimumScale, accuracy: 0.000001)
        XCTAssertEqual(recentered.height / Double(size.height), minimumScale, accuracy: 0.000001)
        XCTAssertEqual(automatic.width, recentered.width * 2, accuracy: 0.000001)
        XCTAssertEqual(automatic.height, recentered.height * 2, accuracy: 0.000001)
    }

    func testWideMarkerBoundsStillFitCompletelyAtEitherMaximumZoom() throws {
        let points = [
            MapPoint(id: "A", label: "A", latitude: 30, longitude: 120, category: "", icon: ""),
            MapPoint(id: "B", label: "B", latitude: 31, longitude: 121, category: "", icon: "")
        ]
        let content = try XCTUnwrap(MapCameraGeometry.contentBounds(points: points))
        let size = CGSize(width: 320, height: 280)
        let visible = try XCTUnwrap(MapCameraGeometry.visibleArea(size: size, top: 70, bottom: 18))
        let automatic = try XCTUnwrap(MapCameraGeometry.fit(content, size: size, visible: visible))
        let recentered = try XCTUnwrap(MapCameraGeometry.fit(content, size: size, visible: visible, maximumZoom: 14))
        XCTAssertGreaterThan(automatic.width / Double(size.width), MKMapRect.world.width / (512 * pow(2.0, 13.0)),
            "A zoom limit is a maximum closeness, not a forced zoom that crops a wide set of places")
        XCTAssertEqual(automatic.width, recentered.width, accuracy: 0.000001)
        XCTAssertEqual(automatic.height, recentered.height, accuracy: 0.000001)
        for fitted in [automatic, recentered] {
            for point in points {
                let location = MKMapPoint(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                let screen = CGPoint(x: (location.x - fitted.minX) / fitted.width * Double(size.width),
                                     y: (location.y - fitted.minY) / fitted.height * Double(size.height))
                XCTAssertTrue(visible.contains(screen), "Every supplied point must stay inside the unobscured map")
            }
        }
    }

    func testStreamingDefersFitAndManualCameraChangesSurviveMarkerUpdates() {
        // 53df45b src/lib/components/map/map.tsx fits after streaming, unless
        // the user has moved the camera; recenter remains an explicit action.
        let state = MapCameraState()
        state.overviewRect = MKMapRect(x: 10, y: 20, width: 400, height: 300)
        state.mode = .manual
        XCTAssertFalse(state.shouldFit(pointsChanged: true, explicitFit: false, streaming: true))
        XCTAssertFalse(state.shouldFit(pointsChanged: true, explicitFit: false, streaming: false))
        XCTAssertTrue(state.shouldFit(pointsChanged: true, explicitFit: true, streaming: false))
        state.mode = .overview
        XCTAssertFalse(state.shouldFit(pointsChanged: true, explicitFit: false, streaming: true))
        XCTAssertTrue(state.shouldFit(pointsChanged: true, explicitFit: false, streaming: false))
        state.wasStreaming = true
        XCTAssertTrue(state.shouldFit(pointsChanged: false, explicitFit: false, streaming: false), "Finishing the stream fits the accumulated markers")
        state.wasStreaming = false
        XCTAssertFalse(state.shouldFit(pointsChanged: false, explicitFit: false, streaming: false))
    }

    func testManualResizePreservesMapCenterAndScale() throws {
        let previous = MKMapRect(x: 100, y: 200, width: 1600, height: 1200)
        let resized = try XCTUnwrap(MapCameraGeometry.resized(previous,
            from: CGSize(width: 400, height: 300), to: CGSize(width: 700, height: 200)))
        XCTAssertEqual(resized.midX, previous.midX, accuracy: 0.000001)
        XCTAssertEqual(resized.midY, previous.midY, accuracy: 0.000001)
        XCTAssertEqual(resized.width / 700, previous.width / 400, accuracy: 0.000001)
        XCTAssertEqual(resized.height, 800, accuracy: 0.000001)
        XCTAssertNil(MapCameraGeometry.resized(previous, from: .zero, to: CGSize(width: 300, height: 400)))
    }

    func testOverviewUsesSuppliedMarkerBounds() throws {
        // 53df45b src/lib/components/map/map.tsx uses fitPoints (the visible
        // marker coordinates) for fitBounds; a road detour does not reframe it.
        let points = [
            MapPoint(id: "A", label: "A", latitude: 30, longitude: 120, category: "", icon: ""),
            MapPoint(id: "B", label: "B", latitude: 30.01, longitude: 120.01, category: "", icon: "")
        ]
        XCTAssertNil(MapCameraGeometry.contentBounds(points: []))
        let content = try XCTUnwrap(MapCameraGeometry.contentBounds(points: points))
        for point in points {
            XCTAssertTrue(content.contains(MKMapPoint(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))))
        }
        let size = CGSize(width: 600, height: 480)
        let visible = try XCTUnwrap(MapCameraGeometry.visibleArea(size: size, top: 96, bottom: 0))
        let fitted = try XCTUnwrap(MapCameraGeometry.fit(content, size: size, visible: visible))
        let projectedWidth = content.width / fitted.width * Double(size.width)
        let projectedHeight = content.height / fitted.height * Double(size.height)
        XCTAssertLessThanOrEqual(projectedWidth, Double(visible.width) + 0.000001)
        XCTAssertLessThanOrEqual(projectedHeight, Double(visible.height) + 0.000001)
    }

}
