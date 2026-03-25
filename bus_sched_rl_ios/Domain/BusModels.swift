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

struct GTFSRouteStyle: Codable, Hashable {
    let routeColorHex: String?
    let routeTextColorHex: String?
}

struct GTFSRouteName: Codable, Hashable {
    let shortName: String
    let longName: String
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

struct GTFSStaticData {
    let routeStops: [RouteKey: [BusStop]]
    let routeStopSchedules: [RouteKey: [RouteStopSchedule]]
    let routeDirectionLabels: [RouteKey: String]
    let routeNamesByRouteID: [String: GTFSRouteName]
    let routeStylesByRouteID: [String: GTFSRouteStyle]
    let routeShapeIDByRouteKey: [RouteKey: String]
    let shapeIDByTripID: [String: String]
    let shapePointsByShapeID: [String: [CLLocationCoordinate2D]]
    let feedInfo: GTFSFeedInfo?

    init(
        routeStops: [RouteKey: [BusStop]],
        routeStopSchedules: [RouteKey: [RouteStopSchedule]],
        routeDirectionLabels: [RouteKey: String],
        routeNamesByRouteID: [String: GTFSRouteName],
        routeStylesByRouteID: [String: GTFSRouteStyle],
        routeShapeIDByRouteKey: [RouteKey: String] = [:],
        shapeIDByTripID: [String: String] = [:],
        shapePointsByShapeID: [String: [CLLocationCoordinate2D]] = [:],
        feedInfo: GTFSFeedInfo?
    ) {
        self.routeStops = routeStops
        self.routeStopSchedules = routeStopSchedules
        self.routeDirectionLabels = routeDirectionLabels
        self.routeNamesByRouteID = routeNamesByRouteID
        self.routeStylesByRouteID = routeStylesByRouteID
        self.routeShapeIDByRouteKey = routeShapeIDByRouteKey
        self.shapeIDByTripID = shapeIDByTripID
        self.shapePointsByShapeID = shapePointsByShapeID
        self.feedInfo = feedInfo
    }

    var availableRoutes: [String] {
        let routeIDs = Set(routeStops.keys.map(\.route))
            .union(routeStopSchedules.keys.map(\.route))
            .union(routeDirectionLabels.keys.map(\.route))
            .union(routeNamesByRouteID.keys)
            .union(routeStylesByRouteID.keys)
        return routeIDs.sorted()
    }
}

enum VehicleStopStatus: String, Equatable {
    case incomingAt
    case stoppedAt
    case inTransitTo

    var title: String {
        switch self {
        case .incomingAt:
            return "Approaching stop"
        case .stoppedAt:
            return "At stop"
        case .inTransitTo:
            return "In transit"
        }
    }
}

enum VehicleCongestionLevel: String, Equatable {
    case runningSmoothly
    case stopAndGo
    case congestion
    case severeCongestion

    var title: String {
        switch self {
        case .runningSmoothly:
            return "Traffic flowing"
        case .stopAndGo:
            return "Stop-and-go traffic"
        case .congestion:
            return "Congestion"
        case .severeCongestion:
            return "Severe congestion"
        }
    }
}

enum VehicleOccupancyStatus: String, Equatable {
    case empty
    case manySeatsAvailable
    case fewSeatsAvailable
    case standingRoomOnly
    case crushedStandingRoomOnly
    case full
    case notAcceptingPassengers
    case noDataAvailable
    case notBoardable

    var title: String {
        switch self {
        case .empty:
            return "Empty"
        case .manySeatsAvailable:
            return "Many seats available"
        case .fewSeatsAvailable:
            return "Few seats available"
        case .standingRoomOnly:
            return "Standing room only"
        case .crushedStandingRoomOnly:
            return "Crowded standing room only"
        case .full:
            return "Full"
        case .notAcceptingPassengers:
            return "Not accepting passengers"
        case .noDataAvailable:
            return "Occupancy unavailable"
        case .notBoardable:
            return "Not boardable"
        }
    }
}

struct VehiclePosition: Identifiable, Equatable {
    let id: String
    let tripID: String?
    let route: String?
    let direction: Int?
    let stopID: String?
    let currentStatus: VehicleStopStatus?
    let congestionLevel: VehicleCongestionLevel?
    let occupancyStatus: VehicleOccupancyStatus?
    let occupancyPercentage: Int?
    let heading: Double
    let coord: CLLocationCoordinate2D
    let lastUpdatedAt: Date?

    init(
        id: String,
        tripID: String?,
        route: String?,
        direction: Int?,
        stopID: String? = nil,
        currentStatus: VehicleStopStatus? = nil,
        congestionLevel: VehicleCongestionLevel? = nil,
        occupancyStatus: VehicleOccupancyStatus? = nil,
        occupancyPercentage: Int? = nil,
        heading: Double,
        coord: CLLocationCoordinate2D,
        lastUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.tripID = tripID
        self.route = route
        self.direction = direction
        self.stopID = stopID
        self.currentStatus = currentStatus
        self.congestionLevel = congestionLevel
        self.occupancyStatus = occupancyStatus
        self.occupancyPercentage = occupancyPercentage
        self.heading = heading
        self.coord = coord
        self.lastUpdatedAt = lastUpdatedAt
    }

    static func == (lhs: VehiclePosition, rhs: VehiclePosition) -> Bool {
        lhs.id == rhs.id &&
            lhs.tripID == rhs.tripID &&
            lhs.route == rhs.route &&
            lhs.direction == rhs.direction &&
            lhs.stopID == rhs.stopID &&
            lhs.currentStatus == rhs.currentStatus &&
            lhs.congestionLevel == rhs.congestionLevel &&
            lhs.occupancyStatus == rhs.occupancyStatus &&
            lhs.occupancyPercentage == rhs.occupancyPercentage &&
            lhs.heading == rhs.heading &&
            lhs.coord.latitude == rhs.coord.latitude &&
            lhs.coord.longitude == rhs.coord.longitude &&
            lhs.lastUpdatedAt == rhs.lastUpdatedAt
    }
}

struct TripStopTimeUpdate: Hashable {
    let stopID: String?
    let stopSequence: Int?
    let arrivalTime: Date?
    let departureTime: Date?
    let assignedStopID: String?
    let delaySeconds: Int?

    init(
        stopID: String?,
        stopSequence: Int?,
        arrivalTime: Date?,
        departureTime: Date?,
        assignedStopID: String? = nil,
        delaySeconds: Int? = nil
    ) {
        self.stopID = stopID
        self.stopSequence = stopSequence
        self.arrivalTime = arrivalTime
        self.departureTime = departureTime
        self.assignedStopID = assignedStopID
        self.delaySeconds = delaySeconds
    }
}

struct TripUpdatePayload: Hashable {
    let tripID: String
    let routeID: String?
    let directionID: Int?
    let vehicleID: String?
    let timestamp: Date?
    let delaySeconds: Int?
    let stopTimeUpdates: [TripStopTimeUpdate]

    init(
        tripID: String,
        routeID: String?,
        directionID: Int?,
        vehicleID: String?,
        timestamp: Date?,
        delaySeconds: Int? = nil,
        stopTimeUpdates: [TripStopTimeUpdate]
    ) {
        self.tripID = tripID
        self.routeID = routeID
        self.directionID = directionID
        self.vehicleID = vehicleID
        self.timestamp = timestamp
        self.delaySeconds = delaySeconds
        self.stopTimeUpdates = stopTimeUpdates
    }
}

struct RealtimeSnapshot {
    let vehicles: [VehiclePosition]
    let tripUpdates: [TripUpdatePayload]
    let alerts: [ServiceAlert]

    init(
        vehicles: [VehiclePosition],
        tripUpdates: [TripUpdatePayload],
        alerts: [ServiceAlert] = []
    ) {
        self.vehicles = vehicles
        self.tripUpdates = tripUpdates
        self.alerts = alerts
    }
}

enum ArrivalSourceLabel: String, Equatable {
    case live = "Live"
    case estimated = "Estimated"
    case scheduled = "Scheduled"
}

struct NearbyETACard: Identifiable, Hashable {
    let id: String
    let routeID: String
    let routeShortName: String
    let routeLongName: String
    let directionID: String
    let directionText: String
    let stopID: String
    let stopName: String
    let tripID: String?
    let liveVehicleID: String?
    let distanceMeters: Int?
    let etaMinutes: Int?
    let arrivalTime: Date?
    let source: ArrivalSourceLabel
    let routeStyle: GTFSRouteStyle?

    var accessibilityLabel: String {
        var parts = ["Route \(routeShortName)", directionText, "Stop \(stopName)"]
        if let etaMinutes {
            parts.append("ETA \(etaMinutes) minutes")
        } else if let arrivalTime {
            parts.append("Arrives at \(arrivalTime.formatted(date: .omitted, time: .shortened))")
        }
        parts.append(source.rawValue)
        return parts.joined(separator: ", ")
    }
}

enum NearbyETAScope: Equatable {
    case nearby
    case route(routeID: String, directionID: String?)
    case stop(stopID: String)
}

enum NearbyETAPhase: Equatable {
    case idle
    case loading
    case ready
    case error(String)
}
