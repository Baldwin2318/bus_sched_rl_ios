import Foundation
import CoreLocation

actor SearchSuggestionEngine {
    private let busSpeedMetersPerSecond = 8.0

    func buildSuggestions(
        vehicles: [VehiclePosition],
        nearbyRoutes: Set<RouteKey>,
        allRoutes: [String],
        routeStops: [RouteKey: [BusStop]],
        routeDirectionLabels: [RouteKey: String],
        userLocation: CLLocationCoordinate2D?
    ) -> [BusSuggestion] {
        nearbySuggestions(
            vehicles: vehicles,
            nearbyRoutes: nearbyRoutes,
            routeStops: routeStops,
            routeDirectionLabels: routeDirectionLabels,
            userLocation: userLocation,
            allRoutes: allRoutes,
        )
    }

    private func nearbySuggestions(
        vehicles: [VehiclePosition],
        nearbyRoutes: Set<RouteKey>,
        routeStops: [RouteKey: [BusStop]],
        routeDirectionLabels: [RouteKey: String],
        userLocation: CLLocationCoordinate2D?,
        allRoutes: [String]
    ) -> [BusSuggestion] {
        let now = Date()
        guard let userLocation else {
            return allRoutes.prefix(12).map {
                BusSuggestion(
                    id: "fallback-\($0)",
                    route: $0,
                    displayDirection: "Route",
                    directionID: nil,
                    metersAway: nil,
                    etaMinutes: nil,
                    estimatedArrivalAt: nil,
                    source: .scheduled,
                    nearestStopName: nil
                )
            }
        }

        var results: [BusSuggestion] = []
        var seen: Set<String> = []

        let liveCandidates = vehicles.compactMap { vehicle -> (vehicle: VehiclePosition, key: RouteKey)? in
            guard let route = vehicle.route else { return nil }
            let key = RouteKey(route: route, direction: vehicle.direction.map(String.init) ?? "0")
            return (vehicle, key)
        }

        var vehiclesByRoute: [RouteKey: [VehiclePosition]] = [:]
        for candidate in liveCandidates {
            vehiclesByRoute[candidate.key, default: []].append(candidate.vehicle)
        }

        for (vehicle, key) in liveCandidates {
            let id = "live-\(key.route)-\(key.direction)"
            guard seen.insert(id).inserted else { continue }
            let metrics = stopMetrics(for: key, userLocation: userLocation, vehicles: [vehicle], routeStops: routeStops)
            results.append(
                    BusSuggestion(
                        id: id,
                        route: key.route,
                        displayDirection: routeDirectionLabels[key] ?? fallbackDirectionText(key.direction),
                        directionID: key.direction,
                        metersAway: metrics?.meters,
                        etaMinutes: metrics?.eta,
                        estimatedArrivalAt: metrics?.eta.flatMap { eta in
                            Calendar.current.date(byAdding: .minute, value: eta, to: now)
                        },
                        source: metrics?.eta != nil ? .live : .scheduled,
                        nearestStopName: metrics?.stopName
                )
            )
        }

        for key in nearbyRoutes {
            let id = "near-\(key.route)-\(key.direction)"
            guard seen.insert(id).inserted else { continue }
            let routeVehicles = vehiclesByRoute[key] ?? []
            let metrics = stopMetrics(for: key, userLocation: userLocation, vehicles: routeVehicles, routeStops: routeStops)
            results.append(
                    BusSuggestion(
                        id: id,
                        route: key.route,
                        displayDirection: routeDirectionLabels[key] ?? displayDirection(routeVehicles: routeVehicles, fallbackDirectionID: key.direction),
                        directionID: key.direction,
                        metersAway: metrics?.meters,
                        etaMinutes: metrics?.eta,
                        estimatedArrivalAt: metrics?.eta.flatMap { eta in
                            Calendar.current.date(byAdding: .minute, value: eta, to: now)
                        },
                        source: metrics?.eta != nil ? .live : .scheduled,
                        nearestStopName: metrics?.stopName
                )
            )
        }

        let sorted = results.sorted { lhs, rhs in
            switch (lhs.etaMinutes, rhs.etaMinutes) {
            case let (l?, r?):
                if l != r { return l < r }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }

            switch (lhs.metersAway, rhs.metersAway) {
            case let (l?, r?):
                if l != r { return l < r }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }

            if lhs.route != rhs.route {
                return lhs.route.localizedStandardCompare(rhs.route) == .orderedAscending
            }
            return lhs.displayDirection.localizedStandardCompare(rhs.displayDirection) == .orderedAscending
        }

        return Array(sorted.prefix(24))
    }

    private func stopMetrics(
        for routeKey: RouteKey,
        userLocation: CLLocationCoordinate2D?,
        vehicles: [VehiclePosition],
        routeStops: [RouteKey: [BusStop]]
    ) -> (meters: Int, eta: Int?, stopName: String)? {
        guard let userLocation,
              let stops = routeStops[routeKey],
              !stops.isEmpty else { return nil }

        var nearestStop: BusStop?
        var minUserDistance = CLLocationDistance.greatestFiniteMagnitude

        for stop in stops {
            let distance = planarDistanceMeters(from: userLocation, to: stop.coord)
            if distance < minUserDistance {
                minUserDistance = distance
                nearestStop = stop
            }
        }

        guard let nearestStop else { return nil }

        let eta: Int?
        if let nearestVehicle = nearestVehicle(to: nearestStop, from: vehicles) {
            let seconds = planarDistanceMeters(from: nearestVehicle.coord, to: nearestStop.coord) / busSpeedMetersPerSecond
            eta = max(1, Int(round(seconds / 60)))
        } else {
            eta = nil
        }

        return (meters: Int(round(minUserDistance)), eta: eta, stopName: nearestStop.name)
    }

    private func nearestVehicle(to stop: BusStop, from vehicles: [VehiclePosition]) -> VehiclePosition? {
        guard !vehicles.isEmpty else { return nil }

        return vehicles.min { lhs, rhs in
            planarDistanceMeters(from: lhs.coord, to: stop.coord) < planarDistanceMeters(from: rhs.coord, to: stop.coord)
        }
    }

    private func planarDistanceMeters(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> CLLocationDistance {
        let latMeters = 111_132.92
        let avgLatitude = (lhs.latitude + rhs.latitude) * 0.5
        let lonMeters = max(1.0, 111_412.84 * cos(avgLatitude * .pi / 180))
        let dx = (rhs.longitude - lhs.longitude) * lonMeters
        let dy = (rhs.latitude - lhs.latitude) * latMeters
        return sqrt(dx * dx + dy * dy)
    }

    private func displayDirection(routeVehicles: [VehiclePosition], fallbackDirectionID: String) -> String {
        if let heading = routeVehicles.first?.heading {
            return cardinalDirectionFrench(for: heading)
        }
        return fallbackDirectionText(fallbackDirectionID)
    }

    private func fallbackDirectionText(_ directionID: String) -> String {
        switch directionID {
        case "0": return "Direction 0"
        case "1": return "Direction 1"
        default: return "Direction \(directionID)"
        }
    }

    private func cardinalDirectionFrench(for heading: Double) -> String {
        switch heading {
        case 45..<135:
            return "Est"
        case 135..<225:
            return "Sud"
        case 225..<315:
            return "Ouest"
        default:
            return "Nord"
        }
    }
}
