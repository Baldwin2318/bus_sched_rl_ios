import XCTest
import CoreLocation
@testable import bus_sched_rl_ios

final class ArrivalDetailModelTests: XCTestCase {
    func testArrivalDetailModelSurfacesVehicleAndDelayFields() {
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
            liveVehicleID: "vehicle-1",
            distanceMeters: 240,
            etaMinutes: 6,
            arrivalTime: Date(),
            source: .live,
            routeStyle: nil
        )
        let vehicle = VehiclePosition(
            id: "vehicle-1",
            tripID: "trip-1",
            route: "55",
            direction: 0,
            stopID: "stop-1",
            currentStatus: .incomingAt,
            congestionLevel: .stopAndGo,
            occupancyStatus: .standingRoomOnly,
            occupancyPercentage: 84,
            heading: 45,
            coord: CLLocationCoordinate2D(latitude: 45.5, longitude: -73.6),
            lastUpdatedAt: Date()
        )
        let tripUpdate = TripUpdatePayload(
            tripID: "trip-1",
            routeID: "55",
            directionID: 0,
            vehicleID: "vehicle-1",
            timestamp: Date(),
            delaySeconds: 300,
            stopTimeUpdates: [
                TripStopTimeUpdate(
                    stopID: "stop-1",
                    stopSequence: 1,
                    arrivalTime: Date(),
                    departureTime: nil,
                    assignedStopID: "stop-2",
                    delaySeconds: 300
                )
            ]
        )

        let model = ArrivalDetailModel(
            card: card,
            vehicle: vehicle,
            tripUpdate: tripUpdate,
            assignedStopName: "Temporary Stop"
        )

        XCTAssertEqual(model.statusText, "Approaching stop")
        XCTAssertEqual(model.delayText, "5 min late")
        XCTAssertEqual(model.assignedStopText, "Temporary Stop")
        XCTAssertEqual(model.occupancyText, "84% occupied")
        XCTAssertEqual(model.congestionText, "Stop-and-go traffic")
    }
}
