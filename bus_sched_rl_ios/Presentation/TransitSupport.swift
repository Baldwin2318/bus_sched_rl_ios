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
}

enum TransitText {
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
