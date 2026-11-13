import XCTest
import MapKit
@testable import SwiftIntelligentUI

final class MapCameraGeometryTests: XCTestCase {
    func testFitKeepsSuppliedPointsInsideAreaAboveCardsAndBelowControls() throws {
        let points = [CLLocationCoordinate2D(latitude: 30.238678, longitude: 120.173273),
                      CLLocationCoordinate2D(latitude: 30.237273, longitude: 120.172906),
                      CLLocationCoordinate2D(latitude: 30.252443, longitude: 120.13459),
                      CLLocationCoordinate2D(latitude: 30.251243, longitude: 120.143778)].map(MKMapPoint.init)
        let content = points.reduce(MKMapRect.null) { $0.union(MKMapRect(x: $1.x - 500, y: $1.y - 500, width: 1000, height: 1000)) }
        for size in [CGSize(width: 320, height: 360), CGSize(width: 320, height: 400), CGSize(width: 402, height: 780)] {
            let visible = try XCTUnwrap(MapCameraGeometry.visibleArea(size: size, top: 84, bottom: 148))
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
    func testFocusUsesUniformScaleAndCentersSelectionInVisibleArea() throws {
        let size = CGSize(width: 402, height: 780)
        let visible = try XCTUnwrap(MapCameraGeometry.visibleArea(size: size, top: 96, bottom: 180))
        let point = MKMapPoint(CLLocationCoordinate2D(latitude: 30.251243, longitude: 120.143778))
        let content = MKMapRect(x: point.x - 500, y: point.y - 500, width: 1000, height: 1000)
        let overview = try XCTUnwrap(MapCameraGeometry.fit(content, size: size, visible: visible))
        let focused = try XCTUnwrap(MapCameraGeometry.focus(point, overview: overview, size: size, visible: visible))
        XCTAssertEqual(focused.width, overview.width / 2, accuracy: 0.001)
        XCTAssertEqual(focused.height, overview.height / 2, accuracy: 0.001)
        let screen = CGPoint(x: (point.x - focused.origin.x) / focused.width * size.width,
                             y: (point.y - focused.origin.y) / focused.height * size.height)
        XCTAssertEqual(screen.x, visible.midX, accuracy: 0.001)
        XCTAssertEqual(screen.y, visible.midY, accuracy: 0.001)
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

}
