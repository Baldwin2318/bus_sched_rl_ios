import XCTest
import CoreLocation
@testable import bus_sched_rl_ios

final class RouteTraceResolverTests: XCTestCase {
    func testResolverUsesShapeIDFallbackWhenPrimaryRouteShapeIsMissing() {
        let resolver = RouteTraceResolver()
        let bus = VehiclePosition(
            id: "1",
            tripID: nil,
            route: "165",
            direction: 9,
            heading: 0,
            coord: CLLocationCoordinate2D(latitude: 45.5, longitude: -73.6)
        )

        let shape = [
            CLLocationCoordinate2D(latitude: 45.5, longitude: -73.6),
            CLLocationCoordinate2D(latitude: 45.51, longitude: -73.59)
        ]

        let result = resolver.resolveTrace(
            bus: bus,
            routeShapes: [:],
            routeShapeIDsByKey: [RouteKey(route: "165", direction: "9"): ["S1"]],
            shapeCoordinatesByID: ["S1": shape]
        )

        XCTAssertFalse(result.trace.isEmpty)
        XCTAssertEqual(result.trace.last?.latitude, 45.51, accuracy: 0.0001)
    }
}
