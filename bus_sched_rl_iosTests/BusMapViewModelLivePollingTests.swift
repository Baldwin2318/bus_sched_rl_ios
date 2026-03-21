import XCTest
import CoreLocation
@testable import bus_sched_rl_ios

@MainActor
final class BusMapViewModelLivePollingTests: XCTestCase {
    func testPollingPausesAndResumes() async throws {
        let gtfsRepository = MockGTFSRepository()
        let realtimeRepository = CountingRealtimeRepository()

        let vm = BusMapViewModel(
            gtfsRepository: gtfsRepository,
            realtimeRepository: realtimeRepository,
            livePollInterval: .milliseconds(120),
            interpolationConfig: InterpolationConfig(
                durationRatio: 0.8,
                manualDuration: .milliseconds(120),
                frameInterval: .milliseconds(60),
                maxJumpMeters: 2_000
            )
        )

        vm.loadIfNeeded()
        try await Task.sleep(for: .milliseconds(360))
        let runningCount = await realtimeRepository.callCount()
        XCTAssertGreaterThanOrEqual(runningCount, 2)

        vm.toggleLiveUpdatesPaused()
        let pausedCount = await realtimeRepository.callCount()
        try await Task.sleep(for: .milliseconds(240))
        let pausedAfterWaitCount = await realtimeRepository.callCount()
        XCTAssertEqual(pausedCount, pausedAfterWaitCount)

        vm.toggleLiveUpdatesPaused()
        try await Task.sleep(for: .milliseconds(240))
        let resumedCount = await realtimeRepository.callCount()
        XCTAssertGreaterThan(resumedCount, pausedAfterWaitCount)
    }
}

private actor MockGTFSRepository: GTFSRepository {
    func loadStaticData() async throws -> GTFSStaticData {
        GTFSStaticData(
            routeShapes: [:],
            routeStops: [:],
            routeStopSchedules: [:],
            shapeCoordinatesByID: [:],
            routeShapeIDsByKey: [:],
            routeDirectionLabels: [:],
            routeStylesByRouteID: [:],
            feedInfo: nil
        )
    }

    func refreshStaticData(force: Bool) async throws -> GTFSStaticData {
        try await loadStaticData()
    }

    func cacheMetadata() async -> GTFSCacheMetadata {
        .empty
    }
}

private actor CountingRealtimeRepository: RealtimeRepository {
    private var calls = 0

    func fetchSnapshot() async throws -> RealtimeSnapshot {
        calls += 1
        let offset = Double(calls) * 0.0001
        let vehicle = VehiclePosition(
            id: "vehicle-1",
            tripID: "trip-1",
            route: "165",
            direction: 0,
            heading: 0,
            coord: CLLocationCoordinate2D(latitude: 45.5 + offset, longitude: -73.6 + offset)
        )

        return RealtimeSnapshot(
            vehicles: [vehicle],
            tripUpdates: []
        )
    }

    func callCount() async -> Int {
        calls
    }
}
