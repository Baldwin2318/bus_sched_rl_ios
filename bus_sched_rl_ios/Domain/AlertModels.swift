import Foundation

enum AlertSeverity: String, Codable, Hashable {
    case info
    case warning
    case severe

    var title: String {
        switch self {
        case .info:
            return "Info"
        case .warning:
            return "Warning"
        case .severe:
            return "Severe"
        }
    }
}

struct AlertScopeSelector: Codable, Hashable {
    let routeID: String?
    let directionID: String?
    let stopID: String?
    let tripID: String?

    var isGlobal: Bool {
        routeID == nil && directionID == nil && stopID == nil && tripID == nil
    }

    func matches(card: NearbyETACard) -> Bool {
        if let routeID, routeID != card.routeID {
            return false
        }
        if let directionID, directionID != card.directionID {
            return false
        }
        if let stopID, stopID != card.stopID {
            return false
        }
        if let tripID, tripID != card.tripID {
            return false
        }
        return true
    }
}

struct ServiceAlert: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let message: String?
    let severity: AlertSeverity
    let url: URL?
    let activePeriods: [DateInterval]
    let scopes: [AlertScopeSelector]

    var isGlobal: Bool {
        scopes.isEmpty || scopes.contains(where: \.isGlobal)
    }

    var scopeSummary: String {
        if isGlobal {
            return "System"
        }

        let hasRoute = scopes.contains { $0.routeID != nil }
        let hasStop = scopes.contains { $0.stopID != nil }
        let hasTrip = scopes.contains { $0.tripID != nil }

        if hasRoute && hasStop {
            return "Route and stop"
        }
        if hasRoute {
            return "Route"
        }
        if hasStop {
            return "Stop"
        }
        if hasTrip {
            return "Trip"
        }
        return "Service"
    }

    func isActive(at date: Date) -> Bool {
        guard !activePeriods.isEmpty else { return true }
        return activePeriods.contains { $0.contains(date) }
    }

    func matches(card: NearbyETACard, at date: Date = Date()) -> Bool {
        guard isActive(at: date) else { return false }
        if isGlobal {
            return true
        }
        return scopes.contains { $0.matches(card: card) }
    }
}
