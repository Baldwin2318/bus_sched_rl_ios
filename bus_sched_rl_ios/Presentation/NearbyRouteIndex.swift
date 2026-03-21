import Foundation
import CoreLocation

actor NearbyRouteIndex {
    private var sampledPoints: [(routeKey: RouteKey, lat: Double, lon: Double)] = []

    func rebuild(from routeShapes: [String: [String: [CLLocationCoordinate2D]]]) {
        var next: [(RouteKey, Double, Double)] = []
        next.reserveCapacity(40000)

        for (route, directions) in routeShapes {
            for (direction, points) in directions {
                guard !points.isEmpty else { continue }
                let step = max(points.count / 160, 1)
                var index = 0
                while index < points.count {
                    let point = points[index]
                    next.append((RouteKey(route: route, direction: direction), point.latitude, point.longitude))
                    index += step
                }
                if let last = points.last {
                    next.append((RouteKey(route: route, direction: direction), last.latitude, last.longitude))
                }
            }
        }

        sampledPoints = next
    }

    func routeKeys(near location: CLLocationCoordinate2D?, maxDistance: CLLocationDistance) -> Set<RouteKey> {
        guard let location else { return [] }
        let maxDistanceSquared = maxDistance * maxDistance
        let latMeters = 111_132.92
        let lonMeters = max(1.0, 111_412.84 * cos(location.latitude * .pi / 180))
        var result: Set<RouteKey> = []
        for sampled in sampledPoints {
            let dx = (sampled.lon - location.longitude) * lonMeters
            let dy = (sampled.lat - location.latitude) * latMeters
            if (dx * dx + dy * dy) <= maxDistanceSquared {
                result.insert(sampled.routeKey)
            }
        }
        return result
    }
}
