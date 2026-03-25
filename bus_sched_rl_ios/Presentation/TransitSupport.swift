import Foundation
import CoreLocation

enum TransitMath {
    static func planarDistanceMeters(
        from lhs: CLLocationCoordinate2D,
        to rhs: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let latMeters = 111_132.92
        let avgLatitude = (lhs.latitude + rhs.latitude) * 0.5
        let lonMeters = max(1.0, 111_412.84 * cos(avgLatitude * .pi / 180))
        let dx = (rhs.longitude - lhs.longitude) * lonMeters
        let dy = (rhs.latitude - lhs.latitude) * latMeters
        return sqrt(dx * dx + dy * dy)
    }

    static func interpolateCoordinate(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        progress: Double
    ) -> CLLocationCoordinate2D {
        let clampedProgress = min(1, max(0, progress))
        return CLLocationCoordinate2D(
            latitude: start.latitude + ((end.latitude - start.latitude) * clampedProgress),
            longitude: start.longitude + ((end.longitude - start.longitude) * clampedProgress)
        )
    }

    static func interpolateHeadingDegrees(
        from start: Double,
        to end: Double,
        progress: Double
    ) -> Double {
        let clampedProgress = min(1, max(0, progress))
        let normalizedStart = normalizeHeadingDegrees(start)
        let normalizedEnd = normalizeHeadingDegrees(end)
        let delta = shortestHeadingDelta(from: normalizedStart, to: normalizedEnd)
        return normalizeHeadingDegrees(normalizedStart + (delta * clampedProgress))
    }

    static func nearestPoint(
        on polyline: [CLLocationCoordinate2D],
        to coordinate: CLLocationCoordinate2D,
        maximumDistanceMeters: CLLocationDistance
    ) -> CLLocationCoordinate2D? {
        guard polyline.count >= 2 else { return nil }

        var bestPoint: CLLocationCoordinate2D?
        var bestDistance = CLLocationDistance.greatestFiniteMagnitude

        for index in 0..<(polyline.count - 1) {
            let projectedPoint = projectPoint(
                coordinate,
                ontoSegmentFrom: polyline[index],
                to: polyline[index + 1]
            )
            let distance = planarDistanceMeters(from: coordinate, to: projectedPoint)
            if distance < bestDistance {
                bestDistance = distance
                bestPoint = projectedPoint
            }
        }

        guard let bestPoint, bestDistance <= maximumDistanceMeters else {
            return nil
        }
        return bestPoint
    }

    private static func projectPoint(
        _ point: CLLocationCoordinate2D,
        ontoSegmentFrom start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        let latMeters = 111_132.92
        let avgLatitude = (start.latitude + end.latitude + point.latitude) / 3
        let lonMeters = max(1.0, 111_412.84 * cos(avgLatitude * .pi / 180))

        let startPoint = CGPoint(x: start.longitude * lonMeters, y: start.latitude * latMeters)
        let endPoint = CGPoint(x: end.longitude * lonMeters, y: end.latitude * latMeters)
        let targetPoint = CGPoint(x: point.longitude * lonMeters, y: point.latitude * latMeters)

        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let lengthSquared = (dx * dx) + (dy * dy)
        guard lengthSquared > 0 else { return start }

        let rawProjection = ((targetPoint.x - startPoint.x) * dx + (targetPoint.y - startPoint.y) * dy) / lengthSquared
        let clampedProjection = min(1, max(0, rawProjection))

        let projectedX = startPoint.x + (dx * clampedProjection)
        let projectedY = startPoint.y + (dy * clampedProjection)

        return CLLocationCoordinate2D(
            latitude: CLLocationDegrees(projectedY / latMeters),
            longitude: CLLocationDegrees(projectedX / lonMeters)
        )
    }

    private static func normalizeHeadingDegrees(_ heading: Double) -> Double {
        let normalized = heading.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }

    private static func shortestHeadingDelta(from start: Double, to end: Double) -> Double {
        let delta = (end - start).truncatingRemainder(dividingBy: 360)
        if delta > 180 {
            return delta - 360
        }
        if delta < -180 {
            return delta + 360
        }
        return delta
    }
}

enum TransitText {
    static func delayText(seconds: Int) -> String {
        let absoluteMinutes = max(1, Int(round(Double(abs(seconds)) / 60)))
        if seconds > 0 {
            return "\(absoluteMinutes) min late"
        }
        if seconds < 0 {
            return "\(absoluteMinutes) min early"
        }
        return "On time"
    }

    static func fallbackDirectionText(_ directionID: String) -> String {
        switch directionID {
        case "0":
            return "Direction 0"
        case "1":
            return "Direction 1"
        default:
            return "Direction \(directionID)"
        }
    }

    static func directionText(
        for routeKey: RouteKey,
        labels: [RouteKey: String]
    ) -> String {
        let explicitLabel = labels[routeKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicitLabel.isEmpty {
            return explicitLabel
        }
        return fallbackDirectionText(routeKey.direction)
    }

    static func scheduledDate(from raw: String?, referenceDate: Date) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: referenceDate)
        components.hour = hour % 24
        components.minute = minute
        components.second = 0

        guard var date = Calendar.current.date(from: components) else { return nil }
        let dayOffset = hour / 24
        if dayOffset > 0, let rolled = Calendar.current.date(byAdding: .day, value: dayOffset, to: date) {
            date = rolled
        }
        return date
    }
}
