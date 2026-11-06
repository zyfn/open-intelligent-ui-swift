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
    func testCenterSelectionUsesUncoveredAreaWithoutChangingZoom() throws {
        let size = CGSize(width: 320, height: 400)
        let visible = try XCTUnwrap(MapCameraGeometry.visibleArea(size: size, top: 84, bottom: 148))
        let original = MKMapRect(x: 100, y: 200, width: 20000, height: 25000)
        let point = MKMapPoint(x: 300000, y: 400000)
        let centered = try XCTUnwrap(MapCameraGeometry.centered(original, point: point, size: size, visible: visible))
        XCTAssertEqual(centered.width, original.width)
        XCTAssertEqual(centered.height, original.height)
        XCTAssertEqual((point.x - centered.origin.x) / centered.width * size.width, visible.midX, accuracy: 0.001)
        XCTAssertEqual((point.y - centered.origin.y) / centered.height * size.height, visible.midY, accuracy: 0.001)
    }
    func testZeroOrOccludedViewportWaitsForLayout() {
        XCTAssertNil(MapCameraGeometry.visibleArea(size: .zero, top: 84, bottom: 148))
        XCTAssertNil(MapCameraGeometry.visibleArea(size: CGSize(width: 104, height: 100), top: 84, bottom: 148))
    }
}
