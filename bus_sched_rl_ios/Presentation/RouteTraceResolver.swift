import Foundation
import CoreLocation

struct TraceResolutionResult {
    let trace: [CLLocationCoordinate2D]
    let source: String
    let reason: String?
}

struct RouteTraceResolver {
    private let traceBuilder = TracePathBuilder()

    func resolveTrace(
        bus: VehiclePosition,
        routeShapes: [String: [String: [CLLocationCoordinate2D]]],
        routeShapeIDsByKey: [RouteKey: [String]],
        shapeCoordinatesByID: [String: [CLLocationCoordinate2D]]
    ) -> TraceResolutionResult {
        guard let route = bus.route, !route.isEmpty else {
            return TraceResolutionResult(trace: [], source: "none", reason: "missing_route")
        }

        let directionID = bus.direction.map(String.init) ?? "0"
        let key = RouteKey(route: route, direction: directionID)

        let primaryShape = routeShapes[route]?[directionID]
        var fallbackShapes: [[CLLocationCoordinate2D]] = []

        if let shapeIDs = routeShapeIDsByKey[key] {
            fallbackShapes += shapeIDs.compactMap { shapeCoordinatesByID[$0] }
        }

        // Fallback to any shape under this route if direction mapping is imperfect.
        fallbackShapes += routeShapes[route].map { Array($0.values) } ?? []

        let trace = traceBuilder.pathFromBusToTerminal(
            busCoordinate: bus.coord,
            primaryShape: primaryShape,
            fallbackShapes: fallbackShapes
        )

        if !trace.isEmpty {
            let source = primaryShape == nil ? "fallback" : "primary_or_fallback"
            return TraceResolutionResult(trace: trace, source: source, reason: nil)
        }

        return TraceResolutionResult(trace: [], source: "none", reason: "no_shape_match")
    }
}
