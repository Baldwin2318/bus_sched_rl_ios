import Foundation

struct VehicleRenderIndex {
    private let statesByVehicleID: [String: VehicleRenderState]
    private let stateByTripID: [String: VehicleRenderState]
    private let stateByRouteKey: [RouteKey: VehicleRenderState]

    init(statesByVehicleID: [String: VehicleRenderState]) {
        self.statesByVehicleID = statesByVehicleID

        var tripBuckets: [String: [VehicleRenderState]] = [:]
        var routeBuckets: [RouteKey: [VehicleRenderState]] = [:]

        for state in statesByVehicleID.values {
            if let tripID = state.current.tripID {
                tripBuckets[tripID, default: []].append(state)
            }
            if let route = state.current.route {
                let routeKey = RouteKey(
                    route: route,
                    direction: state.current.direction.map(String.init) ?? "0"
                )
                routeBuckets[routeKey, default: []].append(state)
            }
        }

        self.stateByTripID = tripBuckets.reduce(into: [:]) { partialResult, entry in
            if entry.value.count == 1, let state = entry.value.first {
                partialResult[entry.key] = state
            }
        }
        self.stateByRouteKey = routeBuckets.reduce(into: [:]) { partialResult, entry in
            if entry.value.count == 1, let state = entry.value.first {
                partialResult[entry.key] = state
            }
        }
    }

    func state(for card: NearbyETACard) -> VehicleRenderState? {
        guard card.source == .live else { return nil }

        if let liveVehicleID = card.liveVehicleID,
           let state = statesByVehicleID[liveVehicleID] {
            return state
        }

        if let tripID = card.tripID,
           let state = stateByTripID[tripID] {
            return state
        }

        return stateByRouteKey[RouteKey(route: card.routeID, direction: card.directionID)]
    }
}
