import Foundation
import CoreLocation

struct TracePathBuilder {
    func pathFromBusToTerminal(
        busCoordinate: CLLocationCoordinate2D,
        primaryShape: [CLLocationCoordinate2D]?,
        fallbackShapes: [[CLLocationCoordinate2D]]
    ) -> [CLLocationCoordinate2D] {
        if let primaryShape, !primaryShape.isEmpty {
            return suffixPath(from: busCoordinate, in: primaryShape)
        }

        let candidates = fallbackShapes.filter { !$0.isEmpty }
        guard !candidates.isEmpty else { return [] }

        let busPoint = CLLocation(latitude: busCoordinate.latitude, longitude: busCoordinate.longitude)
        var bestPath: [CLLocationCoordinate2D] = []
        var minDistance = CLLocationDistance.greatestFiniteMagnitude

        for candidate in candidates {
            guard let index = nearestIndex(to: busCoordinate, in: candidate) else { continue }
            let point = CLLocation(latitude: candidate[index].latitude, longitude: candidate[index].longitude)
            let distance = busPoint.distance(from: point)
            if distance < minDistance {
                minDistance = distance
                bestPath = Array(candidate[index...])
            }
        }

        return bestPath
    }

    private func suffixPath(from coordinate: CLLocationCoordinate2D, in shape: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard let index = nearestIndex(to: coordinate, in: shape) else { return [] }
        return Array(shape[index...])
    }

    private func nearestIndex(to coordinate: CLLocationCoordinate2D, in shape: [CLLocationCoordinate2D]) -> Int? {
        guard !shape.isEmpty else { return nil }
        let busPoint = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        var nearestIndex = 0
        var minDistance = CLLocationDistance.greatestFiniteMagnitude
        for (index, point) in shape.enumerated() {
            let loc = CLLocation(latitude: point.latitude, longitude: point.longitude)
            let distance = busPoint.distance(from: loc)
            if distance < minDistance {
                minDistance = distance
                nearestIndex = index
            }
        }
        return nearestIndex
    }
}
