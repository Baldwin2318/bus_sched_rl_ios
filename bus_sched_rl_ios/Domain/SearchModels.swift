import Foundation
import CoreLocation

struct RouteDirectionSearchEntry: Hashable {
    let directionId: String
    let directionText: String
}

struct RouteSearchEntry: Identifiable, Hashable {
    let routeId: String
    let routeShortName: String
    let routeLongName: String
    let routeColor: String?
    let directionOptions: [RouteDirectionSearchEntry]

    var id: String { routeId }
}

struct StopSearchEntry: Identifiable, Hashable {
    let stopId: String
    let stopName: String
    let coordinate: CLLocationCoordinate2D
    let nearbyRouteIds: [String]

    var id: String { stopId }

    static func == (lhs: StopSearchEntry, rhs: StopSearchEntry) -> Bool {
        lhs.stopId == rhs.stopId &&
        lhs.stopName == rhs.stopName &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.nearbyRouteIds == rhs.nearbyRouteIds
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(stopId)
        hasher.combine(stopName)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(nearbyRouteIds)
    }
}

struct RouteSearchMatch: Identifiable, Hashable {
    let route: RouteSearchEntry
    let directionId: String?
    let directionText: String?
    let distanceMeters: Int?

    var id: String { "\(route.routeId):\(directionId ?? "_")" }
}

struct StopSearchMatch: Identifiable, Hashable {
    let stop: StopSearchEntry
    let distanceMeters: Int?

    var id: String { stop.stopId }
}

enum SearchResult: Identifiable, Hashable {
    case route(RouteSearchMatch)
    case stop(StopSearchMatch)

    var id: String {
        switch self {
        case .route(let route):
            return "route:\(route.id)"
        case .stop(let stop):
            return "stop:\(stop.id)"
        }
    }
}
