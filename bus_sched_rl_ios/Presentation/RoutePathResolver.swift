import Foundation
import CoreLocation

enum RoutePathSource: Equatable {
    case realtimeDetour
    case staticShape
    case directFallback
}

struct RoutePathResolution: Equatable {
    let coordinates: [CLLocationCoordinate2D]
    let source: RoutePathSource

    static func == (lhs: RoutePathResolution, rhs: RoutePathResolution) -> Bool {
        lhs.source == rhs.source &&
            lhs.coordinates.count == rhs.coordinates.count &&
            zip(lhs.coordinates, rhs.coordinates).allSatisfy { lhsCoordinate, rhsCoordinate in
                abs(lhsCoordinate.latitude - rhsCoordinate.latitude) < 0.000001 &&
                    abs(lhsCoordinate.longitude - rhsCoordinate.longitude) < 0.000001
            }
    }
}

struct RoutePathResolver {
    static func resolve(
        card: NearbyETACard,
        staticData: GTFSStaticData?,
        snapshot: RealtimeSnapshot,
        vehicleCoordinate: CLLocationCoordinate2D,
        stopCoordinate: CLLocationCoordinate2D
    ) -> RoutePathResolution {
        if let shapePoints = shapePoints(card: card, staticData: staticData, snapshot: snapshot),
           let segment = segment(
                shapePoints: shapePoints,
                vehicleCoordinate: vehicleCoordinate,
                stopCoordinate: stopCoordinate
           ) {
            let source: RoutePathSource = {
                if let shapeIDOverride = snapshot.tripUpdates.first(where: { $0.tripID == card.tripID })?.shapeIDOverride,
                   snapshot.shapePointsByShapeID[shapeIDOverride] != nil {
                    return .realtimeDetour
                }
                return .staticShape
            }()
            return RoutePathResolution(coordinates: segment, source: source)
        }

        return RoutePathResolution(
            coordinates: [vehicleCoordinate, stopCoordinate],
            source: .directFallback
        )
    }

    static func shapePoints(
        card: NearbyETACard,
        staticData: GTFSStaticData?,
        snapshot: RealtimeSnapshot
    ) -> [CLLocationCoordinate2D]? {
        if let tripID = card.tripID,
           let tripUpdate = snapshot.tripUpdates.first(where: { $0.tripID == tripID }),
           let shapeIDOverride = tripUpdate.shapeIDOverride {
            if let realtimeShapePoints = snapshot.shapePointsByShapeID[shapeIDOverride],
               realtimeShapePoints.count >= 2 {
                return realtimeShapePoints
            }
            if let staticShapePoints = staticData?.shapePointsByShapeID[shapeIDOverride],
               staticShapePoints.count >= 2 {
                return staticShapePoints
            }
        }

        guard let staticData else { return nil }
        let routeKey = RouteKey(route: card.routeID, direction: card.directionID)
        let shapeID = card.tripID.flatMap { staticData.shapeIDByTripID[$0] } ??
            staticData.routeShapeIDByRouteKey[routeKey]
        guard let shapeID else { return nil }
        return staticData.shapePointsByShapeID[shapeID]
    }

    private static func segment(
        shapePoints: [CLLocationCoordinate2D],
        vehicleCoordinate: CLLocationCoordinate2D,
        stopCoordinate: CLLocationCoordinate2D
    ) -> [CLLocationCoordinate2D]? {
        guard shapePoints.count >= 2,
              let vehicleIndex = nearestShapePointIndex(to: vehicleCoordinate, in: shapePoints),
              let stopIndex = nearestShapePointIndex(to: stopCoordinate, in: shapePoints) else {
            return nil
        }

        if vehicleIndex <= stopIndex {
            return Array(shapePoints[vehicleIndex...stopIndex])
        }
        return Array(shapePoints[stopIndex...vehicleIndex].reversed())
    }

    private static func nearestShapePointIndex(
        to coordinate: CLLocationCoordinate2D,
        in points: [CLLocationCoordinate2D]
    ) -> Int? {
        points.indices.min {
            TransitMath.planarDistanceMeters(from: points[$0], to: coordinate) <
                TransitMath.planarDistanceMeters(from: points[$1], to: coordinate)
        }
    }
}
