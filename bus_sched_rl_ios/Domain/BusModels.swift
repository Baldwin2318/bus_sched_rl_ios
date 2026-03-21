import Foundation
import CoreLocation

struct RouteKey: Hashable {
    let route: String
    let direction: String
}

struct GTFSFeedInfo: Codable, Hashable {
    let feedVersion: String?
    let feedStartDate: Date?
    let feedEndDate: Date?
}

struct GTFSCacheMetadata: Equatable {
    let lastUpdatedAt: Date?
    let etag: String?
    let lastModified: String?
    let feedInfo: GTFSFeedInfo?

    static let empty = GTFSCacheMetadata(
        lastUpdatedAt: nil,
        etag: nil,
        lastModified: nil,
        feedInfo: nil
    )
}

struct BusStop: Hashable {
    let id: String
    let name: String
    let coord: CLLocationCoordinate2D

    static func == (lhs: BusStop, rhs: BusStop) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.coord.latitude == rhs.coord.latitude &&
        lhs.coord.longitude == rhs.coord.longitude
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(coord.latitude)
        hasher.combine(coord.longitude)
    }
}

struct RouteStopSchedule: Hashable {
    let stop: BusStop
    let sequence: Int
    let scheduledArrival: String?
    let scheduledDeparture: String?
}

struct VehiclePosition: Identifiable, Equatable {
    let id: String
    let tripID: String?
    let route: String?
    let direction: Int?
    let heading: Double
    let coord: CLLocationCoordinate2D

    static func == (lhs: VehiclePosition, rhs: VehiclePosition) -> Bool {
        lhs.id == rhs.id &&
        lhs.tripID == rhs.tripID &&
        lhs.route == rhs.route &&
        lhs.direction == rhs.direction &&
        lhs.heading == rhs.heading &&
        lhs.coord.latitude == rhs.coord.latitude &&
        lhs.coord.longitude == rhs.coord.longitude
    }

    func interpolated(to target: VehiclePosition, fraction: Double) -> VehiclePosition {
        let progress = min(max(fraction, 0), 1)
        let lat = coord.latitude + (target.coord.latitude - coord.latitude) * progress
        let lon = coord.longitude + (target.coord.longitude - coord.longitude) * progress
        return VehiclePosition(
            id: id,
            tripID: target.tripID ?? tripID,
            route: target.route ?? route,
            direction: target.direction ?? direction,
            heading: target.heading,
            coord: CLLocationCoordinate2D(latitude: lat, longitude: lon)
        )
    }
}

struct TripStopTimeUpdate: Hashable {
    let stopID: String?
    let stopSequence: Int?
    let arrivalTime: Date?
    let departureTime: Date?
}

struct TripUpdatePayload: Hashable {
    let tripID: String
    let routeID: String?
    let directionID: Int?
    let vehicleID: String?
    let timestamp: Date?
    let stopTimeUpdates: [TripStopTimeUpdate]
}

struct RealtimeSnapshot {
    let vehicles: [VehiclePosition]
    let tripUpdates: [TripUpdatePayload]
}

enum BusMapPhase: Equatable {
    case idle
    case loading(String)
    case ready
    case error(String)
}
