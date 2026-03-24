import Foundation
import CoreLocation

struct TransitDataIndex {
    let allStopsByID: [String: BusStop]
    let routeKeysByStopID: [String: [RouteKey]]
    let schedulesByRouteKeyAndStopID: [RouteKey: [String: RouteStopSchedule]]
    let routeKeysByRouteID: [String: [RouteKey]]

    init(staticData: GTFSStaticData) {
        var allStopsByID: [String: BusStop] = [:]
        var routeKeysByStopID: [String: Set<RouteKey>] = [:]
        var schedulesByRouteKeyAndStopID: [RouteKey: [String: RouteStopSchedule]] = [:]
        var routeKeysByRouteID: [String: Set<RouteKey>] = [:]

        for (routeKey, schedules) in staticData.routeStopSchedules {
            routeKeysByRouteID[routeKey.route, default: []].insert(routeKey)
            var scheduleMap: [String: RouteStopSchedule] = [:]
            for schedule in schedules {
                allStopsByID[schedule.stop.id] = schedule.stop
                routeKeysByStopID[schedule.stop.id, default: []].insert(routeKey)
                if scheduleMap[schedule.stop.id] == nil {
                    scheduleMap[schedule.stop.id] = schedule
                }
            }
            schedulesByRouteKeyAndStopID[routeKey] = scheduleMap
        }

        self.allStopsByID = allStopsByID
        self.routeKeysByStopID = routeKeysByStopID.mapValues {
            $0.sorted { lhs, rhs in
                if lhs.route != rhs.route {
                    return lhs.route.localizedStandardCompare(rhs.route) == .orderedAscending
                }
                return lhs.direction.localizedStandardCompare(rhs.direction) == .orderedAscending
            }
        }
        self.schedulesByRouteKeyAndStopID = schedulesByRouteKeyAndStopID
        self.routeKeysByRouteID = routeKeysByRouteID.mapValues {
            $0.sorted { lhs, rhs in
                if lhs.route != rhs.route {
                    return lhs.route.localizedStandardCompare(rhs.route) == .orderedAscending
                }
                return lhs.direction.localizedStandardCompare(rhs.direction) == .orderedAscending
            }
        }
    }

    func nearestStops(
        to location: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance,
        limit: Int
    ) -> [BusStop] {
        let candidates = allStopsByID.values
            .map { stop in
                (stop: stop, distance: TransitMath.planarDistanceMeters(from: location, to: stop.coord))
            }
            .sorted { lhs, rhs in
                if lhs.distance != rhs.distance {
                    return lhs.distance < rhs.distance
                }
                return lhs.stop.name.localizedStandardCompare(rhs.stop.name) == .orderedAscending
            }

        let nearby = candidates.filter { $0.distance <= radiusMeters }
        if !nearby.isEmpty {
            return Array(nearby.prefix(limit).map(\.stop))
        }

        return Array(candidates.prefix(limit).map(\.stop))
    }
}

struct NearbyETAComposer {
    private let maxCards = 20
    private let maxNearbyStops = 10
    private let maxScopedStops = 8
    private let nearbyStopRadius: CLLocationDistance = 450
    private let pastArrivalTolerance: TimeInterval = 120
    private let estimatedVehicleSpeedMetersPerSecond = 8.0

    func composeCards(
        staticData: GTFSStaticData,
        index: TransitDataIndex,
        snapshot: RealtimeSnapshot,
        userLocation: CLLocationCoordinate2D?,
        scope: NearbyETAScope,
        referenceDate: Date = Date()
    ) -> [NearbyETACard] {
        let liveArrivals = buildLiveArrivalLookup(
            staticData: staticData,
            index: index,
            snapshot: snapshot,
            referenceDate: referenceDate
        )
        let vehiclesByRouteKey = buildVehiclesByRouteKey(snapshot.vehicles)
        let candidates = candidatePairs(
            index: index,
            userLocation: userLocation,
            scope: scope
        )

        var cards: [NearbyETACard] = []
        var seenCardIDs: Set<String> = []
        cards.reserveCapacity(candidates.count)

        for candidate in candidates {
            guard let stop = index.allStopsByID[candidate.stopID] else { continue }
            let routeKey = candidate.routeKey
            let liveArrival = liveArrivals[routeKey]?[candidate.stopID]
            let scheduledSchedule = index.schedulesByRouteKeyAndStopID[routeKey]?[candidate.stopID]
            let scheduledArrival = TransitText.scheduledDate(
                from: scheduledSchedule?.scheduledArrival ?? scheduledSchedule?.scheduledDeparture,
                referenceDate: referenceDate
            )
            let estimatedArrival = liveArrival == nil
                ? estimateArrival(
                    stop: stop,
                    routeKey: routeKey,
                    vehiclesByRouteKey: vehiclesByRouteKey,
                    referenceDate: referenceDate
                )
                : nil

            let source: ArrivalSourceLabel
            let arrivalTime: Date?
            if let liveArrival {
                source = .live
                arrivalTime = liveArrival
            } else if let estimatedArrival {
                source = .estimated
                arrivalTime = estimatedArrival
            } else if let scheduledArrival, scheduledArrival >= referenceDate.addingTimeInterval(-pastArrivalTolerance) {
                source = .scheduled
                arrivalTime = scheduledArrival
            } else {
                continue
            }

            let etaMinutes = arrivalTime.map {
                max(0, Int(ceil($0.timeIntervalSince(referenceDate) / 60)))
            }
            let distanceMeters = userLocation.map {
                Int(round(TransitMath.planarDistanceMeters(from: $0, to: stop.coord)))
            }
            let routeName = staticData.routeNamesByRouteID[routeKey.route]
            let routeShortName = routeName?.shortName.trimmingCharacters(in: .whitespacesAndNewlines)
            let routeLongName = routeName?.longName.trimmingCharacters(in: .whitespacesAndNewlines)
            let cardID = "\(routeKey.route):\(routeKey.direction):\(candidate.stopID)"
            guard seenCardIDs.insert(cardID).inserted else { continue }

            cards.append(
                NearbyETACard(
                    id: cardID,
                    routeID: routeKey.route,
                    routeShortName: routeShortName?.isEmpty == false ? routeShortName! : routeKey.route,
                    routeLongName: routeLongName?.isEmpty == false ? routeLongName! : (routeShortName?.isEmpty == false ? routeShortName! : routeKey.route),
                    directionID: routeKey.direction,
                    directionText: TransitText.directionText(for: routeKey, labels: staticData.routeDirectionLabels),
                    stopID: candidate.stopID,
                    stopName: stop.name,
                    distanceMeters: distanceMeters,
                    etaMinutes: etaMinutes,
                    arrivalTime: arrivalTime,
                    source: source,
                    routeStyle: staticData.routeStylesByRouteID[routeKey.route]
                )
            )
        }

        cards.sort { lhs, rhs in
            let lhsETA = lhs.etaMinutes ?? Int.max
            let rhsETA = rhs.etaMinutes ?? Int.max
            if lhsETA != rhsETA {
                return lhsETA < rhsETA
            }

            let lhsDistance = lhs.distanceMeters ?? Int.max
            let rhsDistance = rhs.distanceMeters ?? Int.max
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }

            let routeComparison = lhs.routeShortName.localizedStandardCompare(rhs.routeShortName)
            if routeComparison != .orderedSame {
                return routeComparison == .orderedAscending
            }

            let stopComparison = lhs.stopName.localizedStandardCompare(rhs.stopName)
            if stopComparison != .orderedSame {
                return stopComparison == .orderedAscending
            }

            return lhs.directionText.localizedStandardCompare(rhs.directionText) == .orderedAscending
        }

        return Array(cards.prefix(maxCards))
    }

    private func candidatePairs(
        index: TransitDataIndex,
        userLocation: CLLocationCoordinate2D?,
        scope: NearbyETAScope
    ) -> [(routeKey: RouteKey, stopID: String)] {
        switch scope {
        case .nearby:
            guard let userLocation else { return [] }
            let stops = index.nearestStops(
                to: userLocation,
                radiusMeters: nearbyStopRadius,
                limit: maxNearbyStops
            )
            return buildPairs(for: stops, index: index)
        case .route(let routeID, let directionID):
            let routeKeys = index.routeKeysByRouteID[routeID, default: []].filter { key in
                guard let directionID else { return true }
                return key.direction == directionID
            }
            guard !routeKeys.isEmpty else { return [] }

            let stops = scopedStops(
                routeKeys: routeKeys,
                index: index,
                userLocation: userLocation
            )

            return buildPairs(for: stops, index: index).filter { pair in
                routeKeys.contains(pair.routeKey)
            }
        case .stop(let stopID):
            guard let stop = index.allStopsByID[stopID] else { return [] }
            return buildPairs(for: [stop], index: index)
        }
    }

    private func scopedStops(
        routeKeys: [RouteKey],
        index: TransitDataIndex,
        userLocation: CLLocationCoordinate2D?
    ) -> [BusStop] {
        var stopsByID: [String: BusStop] = [:]
        for routeKey in routeKeys {
            guard let schedules = index.schedulesByRouteKeyAndStopID[routeKey] else { continue }
            for schedule in schedules.values {
                stopsByID[schedule.stop.id] = schedule.stop
            }
        }

        let stops = Array(stopsByID.values)
        guard let userLocation else {
            return Array(
                stops.sorted { lhs, rhs in
                    lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                .prefix(maxScopedStops)
            )
        }

        return Array(
            stops.sorted { lhs, rhs in
                let lhsDistance = TransitMath.planarDistanceMeters(from: userLocation, to: lhs.coord)
                let rhsDistance = TransitMath.planarDistanceMeters(from: userLocation, to: rhs.coord)
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .prefix(maxScopedStops)
        )
    }

    private func buildPairs(
        for stops: [BusStop],
        index: TransitDataIndex
    ) -> [(routeKey: RouteKey, stopID: String)] {
        var pairs: [(routeKey: RouteKey, stopID: String)] = []
        pairs.reserveCapacity(stops.count * 3)

        for stop in stops {
            for routeKey in index.routeKeysByStopID[stop.id, default: []] {
                pairs.append((routeKey: routeKey, stopID: stop.id))
            }
        }

        return pairs
    }

    private func buildLiveArrivalLookup(
        staticData: GTFSStaticData,
        index: TransitDataIndex,
        snapshot: RealtimeSnapshot,
        referenceDate: Date
    ) -> [RouteKey: [String: Date]] {
        var lookup: [RouteKey: [String: Date]] = [:]

        for update in snapshot.tripUpdates {
            guard let routeID = update.routeID else { continue }
            let routeKey = RouteKey(
                route: routeID,
                direction: update.directionID.map(String.init) ?? "0"
            )

            for stopUpdate in update.stopTimeUpdates {
                let resolvedStopID: String?
                if let stopID = stopUpdate.stopID {
                    resolvedStopID = stopID
                } else if let sequence = stopUpdate.stopSequence {
                    resolvedStopID = staticData.routeStopSchedules[routeKey]?
                        .first(where: { $0.sequence == sequence })?
                        .stop.id
                } else {
                    resolvedStopID = nil
                }

                guard let stopID = resolvedStopID,
                      index.allStopsByID[stopID] != nil else {
                    continue
                }

                guard let arrival = stopUpdate.arrivalTime ?? stopUpdate.departureTime,
                      arrival >= referenceDate.addingTimeInterval(-pastArrivalTolerance) else {
                    continue
                }

                let existing = lookup[routeKey]?[stopID]
                if existing == nil || arrival < existing! {
                    lookup[routeKey, default: [:]][stopID] = arrival
                }
            }
        }

        return lookup
    }

    private func buildVehiclesByRouteKey(_ vehicles: [VehiclePosition]) -> [RouteKey: [VehiclePosition]] {
        var result: [RouteKey: [VehiclePosition]] = [:]
        for vehicle in vehicles {
            guard let route = vehicle.route else { continue }
            let routeKey = RouteKey(route: route, direction: vehicle.direction.map(String.init) ?? "0")
            result[routeKey, default: []].append(vehicle)
        }
        return result
    }

    private func estimateArrival(
        stop: BusStop,
        routeKey: RouteKey,
        vehiclesByRouteKey: [RouteKey: [VehiclePosition]],
        referenceDate: Date
    ) -> Date? {
        guard let nearestVehicle = vehiclesByRouteKey[routeKey]?.min(by: { lhs, rhs in
            TransitMath.planarDistanceMeters(from: lhs.coord, to: stop.coord) <
                TransitMath.planarDistanceMeters(from: rhs.coord, to: stop.coord)
        }) else {
            return nil
        }

        let distance = TransitMath.planarDistanceMeters(from: nearestVehicle.coord, to: stop.coord)
        let seconds = distance / estimatedVehicleSpeedMetersPerSecond
        return referenceDate.addingTimeInterval(seconds)
    }
}
