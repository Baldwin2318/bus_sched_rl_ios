import Foundation
import CoreLocation

struct RouteKey: Hashable {
    let route: String
    let direction: String
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

struct VehiclePosition: Identifiable, Equatable {
    let id: String
    let route: String?
    let direction: Int?
    let heading: Double
    let coord: CLLocationCoordinate2D

    static func == (lhs: VehiclePosition, rhs: VehiclePosition) -> Bool {
        lhs.id == rhs.id &&
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
            route: target.route ?? route,
            direction: target.direction ?? direction,
            heading: target.heading,
            coord: CLLocationCoordinate2D(latitude: lat, longitude: lon)
        )
    }
}

enum BusMapPhase: Equatable {
    case idle
    case loading(String)
    case ready
    case error(String)
}
