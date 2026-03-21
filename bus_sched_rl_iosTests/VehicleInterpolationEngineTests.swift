import XCTest
import CoreLocation
@testable import bus_sched_rl_ios

final class VehicleInterpolationEngineTests: XCTestCase {
    func testFrameInterpolatesMidpoint() async {
        let engine = VehicleInterpolationEngine()
        let start = makeVehicle(id: "v1", lat: 45.5000, lon: -73.6000)
        let end = makeVehicle(id: "v1", lat: 45.5100, lon: -73.5900)

        await engine.setInitial([start])
        await engine.beginTransition(to: [end], maxJumpMeters: 5_000)

        let frame = await engine.frame(fraction: 0.5)
        XCTAssertEqual(frame.count, 1)
        XCTAssertEqual(frame[0].coord.latitude, 45.5050, accuracy: 0.0001)
        XCTAssertEqual(frame[0].coord.longitude, -73.5950, accuracy: 0.0001)
    }

    func testFrameClampsFractionBounds() async {
        let engine = VehicleInterpolationEngine()
        let start = makeVehicle(id: "v1", lat: 45.5000, lon: -73.6000)
        let end = makeVehicle(id: "v1", lat: 45.5100, lon: -73.5900)

        await engine.setInitial([start])
        await engine.beginTransition(to: [end], maxJumpMeters: 5_000)

        let negativeFrame = await engine.frame(fraction: -1)
        XCTAssertEqual(negativeFrame[0].coord.latitude, start.coord.latitude, accuracy: 0.0001)

        let beyondFrame = await engine.frame(fraction: 5)
        XCTAssertEqual(beyondFrame[0].coord.latitude, end.coord.latitude, accuracy: 0.0001)
    }

    func testNewVehicleSnapsImmediately() async {
        let engine = VehicleInterpolationEngine()
        let incoming = makeVehicle(id: "new", lat: 45.5200, lon: -73.5800)

        await engine.setInitial([])
        await engine.beginTransition(to: [incoming], maxJumpMeters: 5_000)

        let frame = await engine.frame(fraction: 0.2)
        XCTAssertEqual(frame.count, 1)
        XCTAssertEqual(frame[0].coord.latitude, incoming.coord.latitude, accuracy: 0.0001)
        XCTAssertEqual(frame[0].coord.longitude, incoming.coord.longitude, accuracy: 0.0001)
    }

    func testLargeJumpSnapsToTarget() async {
        let engine = VehicleInterpolationEngine()
        let start = makeVehicle(id: "v1", lat: 45.5000, lon: -73.6000)
        let farAway = makeVehicle(id: "v1", lat: 45.9000, lon: -73.1000)

        await engine.setInitial([start])
        await engine.beginTransition(to: [farAway], maxJumpMeters: 500)

        let frame = await engine.frame(fraction: 0.2)
        XCTAssertEqual(frame.count, 1)
        XCTAssertEqual(frame[0].coord.latitude, farAway.coord.latitude, accuracy: 0.0001)
        XCTAssertEqual(frame[0].coord.longitude, farAway.coord.longitude, accuracy: 0.0001)
    }

    func testStaleVehicleIsRemovedOnTransition() async {
        let engine = VehicleInterpolationEngine()
        let first = makeVehicle(id: "v1", lat: 45.5000, lon: -73.6000)
        let second = makeVehicle(id: "v2", lat: 45.5100, lon: -73.5900)

        await engine.setInitial([first, second])
        await engine.beginTransition(to: [first], maxJumpMeters: 5_000)

        let frame = await engine.frame(fraction: 1)
        XCTAssertEqual(frame.map(\.id), ["v1"])
    }

    private func makeVehicle(id: String, lat: Double, lon: Double) -> VehiclePosition {
        VehiclePosition(
            id: id,
            tripID: nil,
            route: "165",
            direction: 0,
            heading: 0,
            coord: CLLocationCoordinate2D(latitude: lat, longitude: lon)
        )
    }
}
