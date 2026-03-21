import XCTest
import CoreLocation
@testable import bus_sched_rl_ios

@MainActor
final class BusMapViewModelUXContractTests: XCTestCase {
    func testRouteStyleIsAvailableAfterStaticLoad() async throws {
        let routeStyle = GTFSRouteStyle(routeColorHex: "00AEEF", routeTextColorHex: "101010")
        let staticData = makeStaticData(routeStyle: routeStyle)
        let vm = BusMapViewModel(
            gtfsRepository: StaticGTFSRepository(staticData: staticData),
            realtimeRepository: SnapshotRealtimeRepository(snapshot: RealtimeSnapshot(vehicles: [], tripUpdates: [])),
            livePollInterval: .seconds(120)
        )

        vm.loadIfNeeded()
        try await waitForReady(vm)

        XCTAssertEqual(vm.routeStyle(for: "55"), routeStyle)
        XCTAssertNil(vm.routeStyle(for: "999"))
    }

    func testFreshnessLevelUsesConfiguredThresholds() {
        let vm = BusMapViewModel(
            gtfsRepository: StaticGTFSRepository(staticData: makeStaticData()),
            realtimeRepository: SnapshotRealtimeRepository(snapshot: RealtimeSnapshot(vehicles: [], tripUpdates: [])),
            livePollInterval: .seconds(120)
        )

        let now = Date()
        let liveVehicle = VehiclePosition(
            id: "live",
            tripID: nil,
            route: "55",
            direction: 0,
            heading: 0,
            coord: CLLocationCoordinate2D(latitude: 45.5, longitude: -73.6),
            lastUpdatedAt: now.addingTimeInterval(-20)
        )
        let agingVehicle = VehiclePosition(
            id: "aging",
            tripID: nil,
            route: "55",
            direction: 0,
            heading: 0,
            coord: CLLocationCoordinate2D(latitude: 45.5, longitude: -73.6),
            lastUpdatedAt: now.addingTimeInterval(-70)
        )
        let staleVehicle = VehiclePosition(
            id: "stale",
            tripID: nil,
            route: "55",
            direction: 0,
            heading: 0,
            coord: CLLocationCoordinate2D(latitude: 45.5, longitude: -73.6),
            lastUpdatedAt: now.addingTimeInterval(-150)
        )

        XCTAssertEqual(vm.freshnessLevel(for: liveVehicle, referenceDate: now), .live)
        XCTAssertEqual(vm.freshnessLevel(for: agingVehicle, referenceDate: now), .aging)
        XCTAssertEqual(vm.freshnessLevel(for: staleVehicle, referenceDate: now), .stale)
    }

    func testStopArrivalsPrefersLiveTripUpdatesWhenAvailable() async throws {
        let route = "55"
        let direction = "0"
        let stopID = "STOP-1"
        let staticData = makeStaticData(route: route, direction: direction, stopID: stopID)
        let now = Date()
        let liveTripUpdate = TripUpdatePayload(
            tripID: "trip-live",
            routeID: route,
            directionID: Int(direction),
            vehicleID: nil,
            timestamp: now,
            stopTimeUpdates: [
                TripStopTimeUpdate(
                    stopID: stopID,
                    stopSequence: 1,
                    arrivalTime: now.addingTimeInterval(4 * 60),
                    departureTime: nil
                )
            ]
        )
        let vm = BusMapViewModel(
            gtfsRepository: StaticGTFSRepository(staticData: staticData),
            realtimeRepository: SnapshotRealtimeRepository(
                snapshot: RealtimeSnapshot(vehicles: [], tripUpdates: [liveTripUpdate])
            ),
            livePollInterval: .seconds(120)
        )

        vm.loadIfNeeded()
        try await waitForReady(vm)

        let arrivals = vm.stopArrivals(for: stopID)
        XCTAssertEqual(arrivals?.arrivals.first?.source, .live)
    }

    func testStopArrivalsFallsBackToScheduledWhenNoLiveUpdate() async throws {
        let stopID = "STOP-1"
        let vm = BusMapViewModel(
            gtfsRepository: StaticGTFSRepository(staticData: makeStaticData(stopID: stopID)),
            realtimeRepository: SnapshotRealtimeRepository(
                snapshot: RealtimeSnapshot(vehicles: [], tripUpdates: [])
            ),
            livePollInterval: .seconds(120)
        )

        vm.loadIfNeeded()
        try await waitForReady(vm)

        let arrivals = vm.stopArrivals(for: stopID)
        XCTAssertEqual(arrivals?.arrivals.first?.source, .scheduled)
        XCTAssertNotNil(arrivals?.arrivals.first?.arrivalText)
    }

    private func waitForReady(_ vm: BusMapViewModel, timeoutSeconds: TimeInterval = 2.0) async throws {
        let timeout = Date().addingTimeInterval(timeoutSeconds)
        while Date() < timeout {
            if case .ready = vm.phase {
                return
            }
            if case .error(let message) = vm.phase {
                XCTFail("ViewModel entered error phase: \(message)")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for view model to become ready")
    }

    private func makeStaticData(
        route: String = "55",
        direction: String = "0",
        stopID: String = "STOP-1",
        routeStyle: GTFSRouteStyle? = nil
    ) -> GTFSStaticData {
        let key = RouteKey(route: route, direction: direction)
        let stop = BusStop(
            id: stopID,
            name: "Mock Stop",
            coord: CLLocationCoordinate2D(latitude: 45.51, longitude: -73.60)
        )
        let schedule = RouteStopSchedule(
            stop: stop,
            sequence: 1,
            scheduledArrival: "08:10:00",
            scheduledDeparture: "08:12:00"
        )
        let shape: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: 45.50, longitude: -73.62),
            CLLocationCoordinate2D(latitude: 45.52, longitude: -73.58)
        ]

        var stylesByRouteID: [String: GTFSRouteStyle] = [:]
        if let routeStyle {
            stylesByRouteID[route] = routeStyle
        }

        return GTFSStaticData(
            routeShapes: [route: [direction: shape]],
            routeStops: [key: [stop]],
            routeStopSchedules: [key: [schedule]],
            shapeCoordinatesByID: ["shape-\(route)-\(direction)": shape],
            routeShapeIDsByKey: [key: ["shape-\(route)-\(direction)"]],
            routeDirectionLabels: [key: "Nord"],
            routeStylesByRouteID: stylesByRouteID,
            feedInfo: nil
        )
    }
}

private actor StaticGTFSRepository: GTFSRepository {
    private let staticData: GTFSStaticData

    init(staticData: GTFSStaticData) {
        self.staticData = staticData
    }

    func loadStaticData() async throws -> GTFSStaticData {
        staticData
    }

    func refreshStaticData(force: Bool) async throws -> GTFSStaticData {
        staticData
    }

    func cacheMetadata() async -> GTFSCacheMetadata {
        .empty
    }
}

private actor SnapshotRealtimeRepository: RealtimeRepository {
    private let snapshot: RealtimeSnapshot

    init(snapshot: RealtimeSnapshot) {
        self.snapshot = snapshot
    }

    func fetchSnapshot() async throws -> RealtimeSnapshot {
        snapshot
    }
}
