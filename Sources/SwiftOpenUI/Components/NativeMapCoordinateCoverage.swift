import CoreGraphics
import Foundation

/// Offline coverage for coordinate conversion. This does not infer the map
/// provider or change the host's basemap coordinate policy.
enum NativeMapCoordinateCoverage {
    private struct Coverage: Decodable {
        let type: String
        let coordinates: [[[[Double]]]]
    }

    private struct Region {
        let shape: CGPath
        let bounds: CGRect
    }

    private static let regions: [Region] = {
        guard let url = Bundle.module.url(forResource: "map-coordinate-coverage", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let coverage = try? JSONDecoder().decode(Coverage.self, from: data),
              coverage.type == "MultiPolygon" else { return [] }

        return coverage.coordinates.compactMap { polygon in
            let path = CGMutablePath()
            for ring in polygon {
                guard ring.count >= 4, ring.allSatisfy({ $0.count == 2 }) else { return nil }
                path.addLines(between: ring.map { CGPoint(x: $0[0], y: $0[1]) })
                path.closeSubpath()
            }
            guard !path.isEmpty else { return nil }
            return Region(shape: path, bounds: path.boundingBoxOfPath)
        }
    }()

    static func contains(latitude: Double, longitude: Double) -> Bool {
        let point = CGPoint(x: longitude, y: latitude)
        return regions.contains { region in
            region.bounds.contains(point) && region.shape.contains(point, using: .evenOdd)
        }
    }
}
