import XCTest
import CoreLocation
@testable import bus_sched_rl_ios

final class RoutePathResolverTests: XCTestCase {
    func testResolvePrefersRealtimeDetourShapeOverride() {
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
            distanceMeters: nil,
            etaMinutes: 4,
            arrivalTime: Date(),
            source: .live,
            routeStyle: nil
        )
        let routeKey = RouteKey(route: "55", direction: "0")
        let stop = BusStop(
            id: "stop-1",
            name: "Main Stop",
            coord: CLLocationCoordinate2D(latitude: 45.5030, longitude: -73.6030)
        )
        let staticData = GTFSStaticData(
            routeStops: [routeKey: [stop]],
            routeStopSchedules: [routeKey: []],
            routeDirectionLabels: [routeKey: "Nord"],
            routeNamesByRouteID: ["55": GTFSRouteName(shortName: "55", longName: "Mock Route")],
            routeStylesByRouteID: [:],
            routeShapeIDByRouteKey: [routeKey: "static-shape"],
            shapeIDByTripID: ["trip-1": "static-shape"],
            shapePointsByShapeID: [
                "static-shape": [
                    CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.6000),
                    CLLocationCoordinate2D(latitude: 45.5010, longitude: -73.6010),
                    CLLocationCoordinate2D(latitude: 45.5030, longitude: -73.6030)
                ]
            ],
            feedInfo: nil
        )
        let snapshot = RealtimeSnapshot(
            vehicles: [],
            tripUpdates: [
                TripUpdatePayload(
                    tripID: "trip-1",
                    routeID: "55",
                    directionID: 0,
                    vehicleID: "vehicle-1",
                    timestamp: Date(),
                    shapeIDOverride: "detour-shape",
                    stopTimeUpdates: []
                )
            ],
            shapePointsByShapeID: [
                "detour-shape": [
                    CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.6000),
                    CLLocationCoordinate2D(latitude: 45.5004, longitude: -73.6012),
                    CLLocationCoordinate2D(latitude: 45.5015, longitude: -73.6022),
                    CLLocationCoordinate2D(latitude: 45.5030, longitude: -73.6030)
                ]
            ]
        )

        let resolution = RoutePathResolver.resolve(
            card: card,
            staticData: staticData,
            snapshot: snapshot,
            vehicleCoordinate: CLLocationCoordinate2D(latitude: 45.5001, longitude: -73.6001),
            stopCoordinate: stop.coord
        )

        XCTAssertEqual(resolution.source, .realtimeDetour)
        XCTAssertEqual(resolution.coordinates.count, 4)
    }
}
