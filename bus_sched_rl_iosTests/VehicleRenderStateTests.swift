import XCTest
import CoreLocation
@testable import bus_sched_rl_ios

final class VehicleRenderStateTests: XCTestCase {
    func testUpdatedStateInterpolatesCoordinateAndHeadingAcrossPolls() {
        let startTime = Date(timeIntervalSince1970: 1_710_000_000)
        let endTime = startTime.addingTimeInterval(10)
        let firstVehicle = VehiclePosition(
            id: "vehicle-1",
            tripID: "trip-1",
            route: "55",
            direction: 0,
            heading: 20,
            coord: CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.6000),
            lastUpdatedAt: startTime
        )
        let secondVehicle = VehiclePosition(
            id: "vehicle-1",
            tripID: "trip-1",
            route: "55",
            direction: 0,
            heading: 80,
            coord: CLLocationCoordinate2D(latitude: 45.5020, longitude: -73.6040),
            lastUpdatedAt: endTime
        )

        let initialState = VehicleRenderState.updated(
            existing: nil,
            with: firstVehicle,
            receivedAt: startTime,
            expectedPollInterval: 10
        )
        let updatedState = VehicleRenderState.updated(
            existing: initialState,
            with: secondVehicle,
            receivedAt: endTime,
            expectedPollInterval: 10
        )

        let sampled = updatedState.sample(at: endTime.addingTimeInterval(5))

        XCTAssertEqual(sampled.vehicle.id, "vehicle-1")
        XCTAssertTrue(sampled.isInterpolating)
        XCTAssertEqual(sampled.freshness, .fresh)
        XCTAssertEqual(sampled.coordinate.latitude, 45.5010, accuracy: 0.00001)
        XCTAssertEqual(sampled.coordinate.longitude, -73.6020, accuracy: 0.00001)
        XCTAssertEqual(sampled.heading, 50, accuracy: 0.5)
    }

    func testSampleBecomesStaleFromVehicleTimestamp() {
        let sampleTime = Date(timeIntervalSince1970: 1_710_000_000)
        let vehicle = VehiclePosition(
            id: "vehicle-1",
            tripID: "trip-1",
            route: "55",
            direction: 0,
            heading: 45,
            coord: CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.6000),
            lastUpdatedAt: sampleTime
        )

        let state = VehicleRenderState.updated(
            existing: nil,
            with: vehicle,
            receivedAt: sampleTime,
            expectedPollInterval: 10
        )

        let sampled = state.sample(at: sampleTime.addingTimeInterval(120))

        XCTAssertEqual(sampled.freshness, .stale)
        XCTAssertFalse(sampled.isInterpolating)
        XCTAssertEqual(sampled.coordinate.latitude, vehicle.coord.latitude, accuracy: 0.000001)
        XCTAssertEqual(sampled.coordinate.longitude, vehicle.coord.longitude, accuracy: 0.000001)
    }

    func testSampleSnapsConservativelyToNearbyRouteShape() {
        let sampleTime = Date(timeIntervalSince1970: 1_710_000_000)
        let vehicle = VehiclePosition(
            id: "vehicle-1",
            tripID: "trip-1",
            route: "55",
            direction: 0,
            heading: 90,
            coord: CLLocationCoordinate2D(latitude: 45.50018, longitude: -73.6008),
            lastUpdatedAt: sampleTime
        )

        let state = VehicleRenderState.updated(
            existing: nil,
            with: vehicle,
            receivedAt: sampleTime,
            expectedPollInterval: 10
        )

        let shapePoints = [
            CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.6000),
            CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.6015)
        ]
        let sampled = state.sample(
            at: sampleTime.addingTimeInterval(5),
            routeShapePoints: shapePoints,
            snapToRoute: true,
            maximumSnapDistanceMeters: 35
        )

        XCTAssertTrue(sampled.isSnappedToRoute)
        XCTAssertEqual(sampled.coordinate.latitude, 45.5000, accuracy: 0.00002)
        XCTAssertEqual(sampled.coordinate.longitude, -73.6008, accuracy: 0.00002)
    }
}
