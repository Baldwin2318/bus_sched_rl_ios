import XCTest
import CoreLocation
@testable import bus_sched_rl_ios

final class VehicleRenderIndexTests: XCTestCase {
    func testIndexResolvesUniqueTripAndRouteState() {
        let now = Date()
        let vehicle = VehiclePosition(
            id: "vehicle-1",
            tripID: "trip-1",
            route: "55",
            direction: 0,
            heading: 90,
            coord: CLLocationCoordinate2D(latitude: 45.5, longitude: -73.6),
            lastUpdatedAt: now
        )
        let state = VehicleRenderState.updated(
            existing: nil,
            with: vehicle,
            receivedAt: now,
            expectedPollInterval: 30
        )
        let index = VehicleRenderIndex(statesByVehicleID: ["vehicle-1": state])
        let card = NearbyETACard(
            id: "55:0:stop-1",
            routeID: "55",
            routeShortName: "55",
            routeLongName: "Mock Route",
            directionID: "0",
            directionText: "Nord",
            stopID: "stop-1",
            stopName: "Main Stop",
            tripID: "trip-1",
            liveVehicleID: nil,
            distanceMeters: nil,
            etaMinutes: 5,
            arrivalTime: now,
            source: .live,
            routeStyle: nil
        )

        XCTAssertEqual(index.state(for: card)?.current.id, "vehicle-1")
    }
}
