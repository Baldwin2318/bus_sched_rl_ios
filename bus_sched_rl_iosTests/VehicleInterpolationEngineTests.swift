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

    func testRouteConstrainedTransitionUsesPolylinePath() async {
        let engine = VehicleInterpolationEngine()
        let start = makeVehicle(id: "v1", lat: 45.5000, lon: -73.6000)
        let target = makeVehicle(id: "v1", lat: 45.5098, lon: -73.5898)
        let routeShape = [
            CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.6000),
            CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.5900),
            CLLocationCoordinate2D(latitude: 45.5100, longitude: -73.5900)
        ]

        await engine.setInitial([start])
        let duration = await engine.beginTransition(
            to: [target],
            routeCandidatesByVehicleID: ["v1": [routeShape]],
            routeAnimationDuration: 30,
            fallbackAnimationDuration: 0.5,
            maxJumpMeters: 5_000,
            offRouteThresholdMeters: 50,
            token: 1
        )
        XCTAssertEqual(duration, 30, accuracy: 0.001)

        let frame = await engine.frame(elapsed: 15, token: 1)
        XCTAssertEqual(frame.count, 1)
        XCTAssertEqual(frame[0].coord.latitude, 45.5000, accuracy: 0.0015)
        XCTAssertEqual(frame[0].coord.longitude, -73.5900, accuracy: 0.0015)
        XCTAssertGreaterThan(abs(frame[0].coord.latitude - 45.5050), 0.002)
    }

    func testOffRouteTargetFallsBackToStraightTransition() async {
        let engine = VehicleInterpolationEngine()
        let start = makeVehicle(id: "v1", lat: 45.5000, lon: -73.6000)
        let target = makeVehicle(id: "v1", lat: 45.5040, lon: -73.5960)
        let routeShape = [
            CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.6000),
            CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.5900),
            CLLocationCoordinate2D(latitude: 45.5100, longitude: -73.5900)
        ]

        await engine.setInitial([start])
        let duration = await engine.beginTransition(
            to: [target],
            routeCandidatesByVehicleID: ["v1": [routeShape]],
            routeAnimationDuration: 30,
            fallbackAnimationDuration: 0.5,
            maxJumpMeters: 5_000,
            offRouteThresholdMeters: 50,
            token: 2
        )
        XCTAssertEqual(duration, 0.5, accuracy: 0.001)

        let frame = await engine.frame(elapsed: 0.25, token: 2)
        XCTAssertEqual(frame.count, 1)
        XCTAssertEqual(frame[0].coord.latitude, 45.5020, accuracy: 0.0006)
        XCTAssertEqual(frame[0].coord.longitude, -73.5980, accuracy: 0.0006)
    }

    func testRouteWithInsufficientPointsFallsBackToStraightTransition() async {
        let engine = VehicleInterpolationEngine()
        let start = makeVehicle(id: "v1", lat: 45.5000, lon: -73.6000)
        let target = makeVehicle(id: "v1", lat: 45.5040, lon: -73.5960)
        let invalidShape = [CLLocationCoordinate2D(latitude: 45.5, longitude: -73.6)]

        await engine.setInitial([start])
        let duration = await engine.beginTransition(
            to: [target],
            routeCandidatesByVehicleID: ["v1": [invalidShape]],
            routeAnimationDuration: 30,
            fallbackAnimationDuration: 0.5,
            maxJumpMeters: 5_000,
            offRouteThresholdMeters: 50,
            token: 3
        )
        XCTAssertEqual(duration, 0.5, accuracy: 0.001)

        let frame = await engine.frame(elapsed: 0.25, token: 3)
        XCTAssertEqual(frame.count, 1)
        XCTAssertEqual(frame[0].coord.latitude, 45.5020, accuracy: 0.0006)
        XCTAssertEqual(frame[0].coord.longitude, -73.5980, accuracy: 0.0006)
    }

    func testRouteTransitionClampsAtTerminalPoint() async {
        let engine = VehicleInterpolationEngine()
        let start = makeVehicle(id: "v1", lat: 45.5000, lon: -73.6000)
        let target = makeVehicle(id: "v1", lat: 45.5200, lon: -73.5900)
        let routeShape = [
            CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.6000),
            CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.5900),
            CLLocationCoordinate2D(latitude: 45.5100, longitude: -73.5900)
        ]

        await engine.setInitial([start])
        _ = await engine.beginTransition(
            to: [target],
            routeCandidatesByVehicleID: ["v1": [routeShape]],
            routeAnimationDuration: 30,
            fallbackAnimationDuration: 0.5,
            maxJumpMeters: 5_000,
            offRouteThresholdMeters: 50,
            token: 4
        )

        let frame = await engine.frame(elapsed: 40, token: 4)
        XCTAssertEqual(frame.count, 1)
        XCTAssertEqual(frame[0].coord.latitude, 45.5100, accuracy: 0.0006)
        XCTAssertEqual(frame[0].coord.longitude, -73.5900, accuracy: 0.0006)
    }

    func testInterruptingTransitionStartsFromCurrentInterpolatedPosition() async {
        let engine = VehicleInterpolationEngine()
        let start = makeVehicle(id: "v1", lat: 45.5000, lon: -73.6000)
        let midTarget = makeVehicle(id: "v1", lat: 45.5100, lon: -73.5900)
        let finalTarget = makeVehicle(id: "v1", lat: 45.5200, lon: -73.5900)
        let routeShape = [
            CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.6000),
            CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.5900),
            CLLocationCoordinate2D(latitude: 45.5100, longitude: -73.5900),
            CLLocationCoordinate2D(latitude: 45.5200, longitude: -73.5900)
        ]

        await engine.setInitial([start])
        _ = await engine.beginTransition(
            to: [midTarget],
            routeCandidatesByVehicleID: ["v1": [routeShape]],
            routeAnimationDuration: 30,
            fallbackAnimationDuration: 0.5,
            maxJumpMeters: 5_000,
            offRouteThresholdMeters: 50,
            token: 10
        )
        let inFlightFrame = await engine.frame(elapsed: 10, token: 10)
        XCTAssertEqual(inFlightFrame.count, 1)

        _ = await engine.beginTransition(
            to: [finalTarget],
            routeCandidatesByVehicleID: ["v1": [routeShape]],
            routeAnimationDuration: 30,
            fallbackAnimationDuration: 0.5,
            maxJumpMeters: 5_000,
            offRouteThresholdMeters: 50,
            token: 11
        )

        _ = await engine.frame(elapsed: 20, token: 10)
        let restartFrame = await engine.frame(elapsed: 0, token: 11)
        XCTAssertEqual(restartFrame.count, 1)

        let deltaLat = abs(restartFrame[0].coord.latitude - inFlightFrame[0].coord.latitude)
        let deltaLon = abs(restartFrame[0].coord.longitude - inFlightFrame[0].coord.longitude)
        XCTAssertLessThan(deltaLat, 0.0008)
        XCTAssertLessThan(deltaLon, 0.0008)
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
