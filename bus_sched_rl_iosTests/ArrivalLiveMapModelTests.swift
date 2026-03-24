import XCTest
import CoreLocation
@testable import bus_sched_rl_ios

final class ArrivalLiveMapModelTests: XCTestCase {
    func testMapModelIncludesStopVehicleAndUserLocationInRegion() {
        let userLocation = CLLocationCoordinate2D(latitude: 45.5010, longitude: -73.6010)
        let stopLocation = CLLocationCoordinate2D(latitude: 45.5020, longitude: -73.6020)
        let vehicle = VehiclePosition(
            id: "vehicle-1",
            tripID: "trip-1",
            route: "55",
            direction: 0,
            heading: 90,
            coord: CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.6000),
            lastUpdatedAt: Date()
        )

        let model = ArrivalLiveMapModel(
            vehicle: vehicle,
            stopName: "Main Stop",
            stopCoordinate: stopLocation,
            userLocation: userLocation,
            pathCoordinates: [vehicle.coord, stopLocation]
        )

        XCTAssertEqual(model.stopName, "Main Stop")
        XCTAssertEqual(model.routeLine.pointCount, 2)
        XCTAssertGreaterThan(model.region.span.latitudeDelta, 0)
        XCTAssertGreaterThan(model.region.span.longitudeDelta, 0)
        XCTAssertFalse(model.usesRouteShapePath)
    }

    func testMapModelMarksShapeBackedPolylineWhenPathHasIntermediatePoints() {
        let stopLocation = CLLocationCoordinate2D(latitude: 45.5020, longitude: -73.6020)
        let vehicle = VehiclePosition(
            id: "vehicle-1",
            tripID: "trip-1",
            route: "55",
            direction: 0,
            heading: 90,
            coord: CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.6000),
            lastUpdatedAt: Date()
        )

        let model = ArrivalLiveMapModel(
            vehicle: vehicle,
            stopName: "Main Stop",
            stopCoordinate: stopLocation,
            userLocation: nil,
            pathCoordinates: [
                vehicle.coord,
                CLLocationCoordinate2D(latitude: 45.5008, longitude: -73.6007),
                CLLocationCoordinate2D(latitude: 45.5014, longitude: -73.6014),
                stopLocation
            ]
        )

        XCTAssertTrue(model.usesRouteShapePath)
        XCTAssertEqual(model.routeLine.pointCount, 4)
    }
}
