import XCTest
import CoreLocation
@testable import bus_sched_rl_ios

@MainActor
final class NearbyETAViewModelTests: XCTestCase {
    func testLoadBuildsNearbyCards() async throws {
        let routeKey = RouteKey(route: "55", direction: "0")
        let stop = BusStop(
            id: "stop-1",
            name: "Main Stop",
            coord: CLLocationCoordinate2D(latitude: 45.50, longitude: -73.60)
        )
        let staticData = GTFSStaticData(
            routeStops: [routeKey: [stop]],
            routeStopSchedules: [
                routeKey: [
                    RouteStopSchedule(
                        stop: stop,
                        sequence: 1,
                        scheduledArrival: "08:00:00",
                        scheduledDeparture: nil
                    )
                ]
            ],
            routeDirectionLabels: [routeKey: "Nord"],
            routeNamesByRouteID: ["55": GTFSRouteName(shortName: "55", longName: "Mock Route")],
            routeStylesByRouteID: [:],
            feedInfo: nil
        )
        let now = Date()
        let snapshot = RealtimeSnapshot(
            vehicles: [],
            tripUpdates: [
                TripUpdatePayload(
                    tripID: "trip-1",
                    routeID: "55",
                    directionID: 0,
                    vehicleID: nil,
                    timestamp: now,
                    stopTimeUpdates: [
                        TripStopTimeUpdate(
                            stopID: "stop-1",
                            stopSequence: 1,
                            arrivalTime: now.addingTimeInterval(3 * 60),
                            departureTime: nil
                        )
                    ]
                )
            ]
        )

        let viewModel = NearbyETAViewModel(
            gtfsRepository: StaticRepository(staticData: staticData),
            realtimeRepository: SnapshotRepository(snapshot: snapshot),
            livePollInterval: .seconds(120)
        )

        viewModel.updateUserLocation(CLLocationCoordinate2D(latitude: 45.5001, longitude: -73.6001))
        viewModel.loadIfNeeded()

        try await waitUntil { !viewModel.cards.isEmpty }

        XCTAssertEqual(viewModel.cards.first?.routeID, "55")
        XCTAssertEqual(viewModel.cards.first?.source, .live)
    }

    func testSelectingSearchResultFiltersToMatchedRoute() async throws {
        let routeKey = RouteKey(route: "55", direction: "0")
        let stop = BusStop(
            id: "stop-1",
            name: "Main Stop",
            coord: CLLocationCoordinate2D(latitude: 45.50, longitude: -73.60)
        )
        let staticData = GTFSStaticData(
            routeStops: [routeKey: [stop]],
            routeStopSchedules: [
                routeKey: [
                    RouteStopSchedule(
                        stop: stop,
                        sequence: 1,
                        scheduledArrival: "08:00:00",
                        scheduledDeparture: nil
                    )
                ]
            ],
            routeDirectionLabels: [routeKey: "Nord"],
            routeNamesByRouteID: ["55": GTFSRouteName(shortName: "55", longName: "Mock Route")],
            routeStylesByRouteID: [:],
            feedInfo: nil
        )
        let snapshot = RealtimeSnapshot(vehicles: [], tripUpdates: [])
        let viewModel = NearbyETAViewModel(
            gtfsRepository: StaticRepository(staticData: staticData),
            realtimeRepository: SnapshotRepository(snapshot: snapshot),
            livePollInterval: .seconds(120)
        )

        viewModel.loadIfNeeded()
        try await waitUntil { viewModel.phase == .ready }

        let routeEntry = RouteSearchEntry(
            routeId: "55",
            routeShortName: "55",
            routeLongName: "Mock Route",
            routeColor: nil,
            directionOptions: [
                RouteDirectionSearchEntry(directionId: "0", directionText: "Nord")
            ]
        )
        let match = RouteSearchMatch(
            route: routeEntry,
            directionId: "0",
            directionText: "Nord",
            distanceMeters: nil
        )

        viewModel.selectSearchResult(.route(match))

        XCTAssertEqual(viewModel.titleText, "55 Nord")
        XCTAssertEqual(viewModel.cards.first?.routeID, "55")
    }

    func testLiveVehicleResolutionRequiresLiveCardAndMatchingVehicle() async throws {
        let routeKey = RouteKey(route: "55", direction: "0")
        let stop = BusStop(
            id: "stop-1",
            name: "Main Stop",
            coord: CLLocationCoordinate2D(latitude: 45.50, longitude: -73.60)
        )
        let staticData = GTFSStaticData(
            routeStops: [routeKey: [stop]],
            routeStopSchedules: [
                routeKey: [
                    RouteStopSchedule(
                        stop: stop,
                        sequence: 1,
                        scheduledArrival: "23:59:00",
                        scheduledDeparture: nil
                    )
                ]
            ],
            routeDirectionLabels: [routeKey: "Nord"],
            routeNamesByRouteID: ["55": GTFSRouteName(shortName: "55", longName: "Mock Route")],
            routeStylesByRouteID: [:],
            feedInfo: nil
        )
        let now = Date()
        let snapshot = RealtimeSnapshot(
            vehicles: [
                VehiclePosition(
                    id: "vehicle-1",
                    tripID: "trip-1",
                    route: "55",
                    direction: 0,
                    heading: 25,
                    coord: CLLocationCoordinate2D(latitude: 45.5005, longitude: -73.6005),
                    lastUpdatedAt: now
                )
            ],
            tripUpdates: [
                TripUpdatePayload(
                    tripID: "trip-1",
                    routeID: "55",
                    directionID: 0,
                    vehicleID: "vehicle-1",
                    timestamp: now,
                    stopTimeUpdates: [
                        TripStopTimeUpdate(
                            stopID: "stop-1",
                            stopSequence: 1,
                            arrivalTime: now.addingTimeInterval(3 * 60),
                            departureTime: nil
                        )
                    ]
                )
            ]
        )
        let viewModel = NearbyETAViewModel(
            gtfsRepository: StaticRepository(staticData: staticData),
            realtimeRepository: SnapshotRepository(snapshot: snapshot),
            livePollInterval: .seconds(120)
        )

        viewModel.updateUserLocation(CLLocationCoordinate2D(latitude: 45.5001, longitude: -73.6001))
        viewModel.loadIfNeeded()

        try await waitUntil { !viewModel.cards.isEmpty }
        let liveCard = try XCTUnwrap(viewModel.cards.first)

        XCTAssertEqual(viewModel.liveVehicle(for: liveCard)?.id, "vehicle-1")

        let scheduledCard = NearbyETACard(
            id: liveCard.id,
            routeID: liveCard.routeID,
            routeShortName: liveCard.routeShortName,
            routeLongName: liveCard.routeLongName,
            directionID: liveCard.directionID,
            directionText: liveCard.directionText,
            stopID: liveCard.stopID,
            stopName: liveCard.stopName,
            tripID: liveCard.tripID,
            liveVehicleID: liveCard.liveVehicleID,
            distanceMeters: liveCard.distanceMeters,
            etaMinutes: liveCard.etaMinutes,
            arrivalTime: liveCard.arrivalTime,
            source: .scheduled,
            routeStyle: liveCard.routeStyle
        )

        XCTAssertNil(viewModel.liveVehicle(for: scheduledCard))
    }

    func testArrivalLiveMapModelUsesRouteShapeSegmentWhenAvailable() async throws {
        let routeKey = RouteKey(route: "55", direction: "0")
        let stop = BusStop(
            id: "stop-1",
            name: "Main Stop",
            coord: CLLocationCoordinate2D(latitude: 45.5030, longitude: -73.6030)
        )
        let shapePoints = [
            CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.6000),
            CLLocationCoordinate2D(latitude: 45.5005, longitude: -73.6010),
            CLLocationCoordinate2D(latitude: 45.5012, longitude: -73.6018),
            CLLocationCoordinate2D(latitude: 45.5020, longitude: -73.6023),
            CLLocationCoordinate2D(latitude: 45.5030, longitude: -73.6030),
        ]
        let staticData = GTFSStaticData(
            routeStops: [routeKey: [stop]],
            routeStopSchedules: [
                routeKey: [
                    RouteStopSchedule(
                        stop: stop,
                        sequence: 1,
                        scheduledArrival: "23:59:00",
                        scheduledDeparture: nil
                    )
                ]
            ],
            routeDirectionLabels: [routeKey: "Nord"],
            routeNamesByRouteID: ["55": GTFSRouteName(shortName: "55", longName: "Mock Route")],
            routeStylesByRouteID: [:],
            routeShapeIDByRouteKey: [routeKey: "shape-55"],
            shapeIDByTripID: ["trip-1": "shape-55"],
            shapePointsByShapeID: ["shape-55": shapePoints],
            feedInfo: nil
        )
        let now = Date()
        let snapshot = RealtimeSnapshot(
            vehicles: [
                VehiclePosition(
                    id: "vehicle-1",
                    tripID: "trip-1",
                    route: "55",
                    direction: 0,
                    heading: 25,
                    coord: CLLocationCoordinate2D(latitude: 45.5004, longitude: -73.6009),
                    lastUpdatedAt: now
                )
            ],
            tripUpdates: [
                TripUpdatePayload(
                    tripID: "trip-1",
                    routeID: "55",
                    directionID: 0,
                    vehicleID: "vehicle-1",
                    timestamp: now,
                    stopTimeUpdates: [
                        TripStopTimeUpdate(
                            stopID: "stop-1",
                            stopSequence: 1,
                            arrivalTime: now.addingTimeInterval(3 * 60),
                            departureTime: nil
                        )
                    ]
                )
            ]
        )
        let viewModel = NearbyETAViewModel(
            gtfsRepository: StaticRepository(staticData: staticData),
            realtimeRepository: SnapshotRepository(snapshot: snapshot),
            livePollInterval: .seconds(120)
        )

        viewModel.updateUserLocation(CLLocationCoordinate2D(latitude: 45.5001, longitude: -73.6001))
        viewModel.loadIfNeeded()

        try await waitUntil { !viewModel.cards.isEmpty }
        let liveCard = try XCTUnwrap(viewModel.cards.first)
        let mapModel = try XCTUnwrap(
            viewModel.arrivalLiveMapModel(
                for: liveCard,
                userLocation: CLLocationCoordinate2D(latitude: 45.4998, longitude: -73.5998)
            )
        )

        XCTAssertTrue(mapModel.usesRouteShapePath)
        XCTAssertGreaterThan(mapModel.routeLine.pointCount, 2)
    }

    func testFavoritingCardPinsItAndRemovesItFromNearbyList() async throws {
        let routeKey = RouteKey(route: "55", direction: "0")
        let stop = BusStop(
            id: "stop-1",
            name: "Main Stop",
            coord: CLLocationCoordinate2D(latitude: 45.50, longitude: -73.60)
        )
        let staticData = GTFSStaticData(
            routeStops: [routeKey: [stop]],
            routeStopSchedules: [
                routeKey: [
                    RouteStopSchedule(
                        stop: stop,
                        sequence: 1,
                        scheduledArrival: "08:00:00",
                        scheduledDeparture: nil
                    )
                ]
            ],
            routeDirectionLabels: [routeKey: "Nord"],
            routeNamesByRouteID: ["55": GTFSRouteName(shortName: "55", longName: "Mock Route")],
            routeStylesByRouteID: [:],
            feedInfo: nil
        )
        let now = Date()
        let snapshot = RealtimeSnapshot(
            vehicles: [],
            tripUpdates: [
                TripUpdatePayload(
                    tripID: "trip-1",
                    routeID: "55",
                    directionID: 0,
                    vehicleID: nil,
                    timestamp: now,
                    stopTimeUpdates: [
                        TripStopTimeUpdate(
                            stopID: "stop-1",
                            stopSequence: 1,
                            arrivalTime: now.addingTimeInterval(4 * 60),
                            departureTime: nil
                        )
                    ]
                )
            ]
        )
        let favoritesRepository = InMemoryFavoritesRepository()
        let viewModel = NearbyETAViewModel(
            gtfsRepository: StaticRepository(staticData: staticData),
            realtimeRepository: SnapshotRepository(snapshot: snapshot),
            favoritesRepository: favoritesRepository,
            livePollInterval: .seconds(120)
        )

        viewModel.updateUserLocation(CLLocationCoordinate2D(latitude: 45.5001, longitude: -73.6001))
        viewModel.loadIfNeeded()

        try await waitUntil { !viewModel.nearbyCards.isEmpty }
        let card = try XCTUnwrap(viewModel.nearbyCards.first)

        viewModel.toggleFavorite(card)

        XCTAssertEqual(viewModel.favoriteCards.map(\.id), [card.id])
        XCTAssertFalse(viewModel.nearbyCards.contains(where: { $0.id == card.id }))
        XCTAssertEqual(favoritesRepository.loadFavorites(), [FavoriteArrivalID(card: card)])
    }

    func testFavoriteCardRefreshesEtaOverTime() async throws {
        let routeKey = RouteKey(route: "55", direction: "0")
        let stop = BusStop(
            id: "stop-1",
            name: "Main Stop",
            coord: CLLocationCoordinate2D(latitude: 45.50, longitude: -73.60)
        )
        let staticData = GTFSStaticData(
            routeStops: [routeKey: [stop]],
            routeStopSchedules: [
                routeKey: [
                    RouteStopSchedule(
                        stop: stop,
                        sequence: 1,
                        scheduledArrival: "08:00:00",
                        scheduledDeparture: nil
                    )
                ]
            ],
            routeDirectionLabels: [routeKey: "Nord"],
            routeNamesByRouteID: ["55": GTFSRouteName(shortName: "55", longName: "Mock Route")],
            routeStylesByRouteID: [:],
            feedInfo: nil
        )
        let now = Date()
        let repository = MutableSnapshotRepository(
            snapshot: RealtimeSnapshot(
                vehicles: [],
                tripUpdates: [
                    TripUpdatePayload(
                        tripID: "trip-1",
                        routeID: "55",
                        directionID: 0,
                        vehicleID: nil,
                        timestamp: now,
                        stopTimeUpdates: [
                            TripStopTimeUpdate(
                                stopID: "stop-1",
                                stopSequence: 1,
                                arrivalTime: now.addingTimeInterval(2 * 60),
                                departureTime: nil
                            )
                        ]
                    )
                ]
            )
        )
        let viewModel = NearbyETAViewModel(
            gtfsRepository: StaticRepository(staticData: staticData),
            realtimeRepository: repository,
            favoritesRepository: InMemoryFavoritesRepository(),
            livePollInterval: .seconds(120)
        )

        viewModel.updateUserLocation(CLLocationCoordinate2D(latitude: 45.5001, longitude: -73.6001))
        viewModel.loadIfNeeded()

        try await waitUntil { !viewModel.nearbyCards.isEmpty }
        let card = try XCTUnwrap(viewModel.nearbyCards.first)
        viewModel.toggleFavorite(card)
        let initialETA = viewModel.favoriteCards.first?.etaMinutes

        await repository.updateSnapshot(
            RealtimeSnapshot(
                vehicles: [],
                tripUpdates: [
                    TripUpdatePayload(
                        tripID: "trip-1",
                        routeID: "55",
                        directionID: 0,
                        vehicleID: nil,
                        timestamp: now.addingTimeInterval(60),
                        stopTimeUpdates: [
                            TripStopTimeUpdate(
                                stopID: "stop-1",
                                stopSequence: 1,
                                arrivalTime: now.addingTimeInterval(7 * 60),
                                departureTime: nil
                            )
                        ]
                    )
                ]
            )
        )

        viewModel.refreshManually()
        try await waitUntil {
            (viewModel.favoriteCards.first?.etaMinutes ?? -1) != (initialETA ?? -1)
        }

        XCTAssertEqual(viewModel.favoriteCards.first?.id, card.id)
        XCTAssertNotEqual(viewModel.favoriteCards.first?.etaMinutes, initialETA)
    }

    func testMissingFavoriteIsIgnoredSafely() async throws {
        let routeKey = RouteKey(route: "55", direction: "0")
        let stop = BusStop(
            id: "stop-1",
            name: "Main Stop",
            coord: CLLocationCoordinate2D(latitude: 45.50, longitude: -73.60)
        )
        let staticData = GTFSStaticData(
            routeStops: [routeKey: [stop]],
            routeStopSchedules: [
                routeKey: [
                    RouteStopSchedule(
                        stop: stop,
                        sequence: 1,
                        scheduledArrival: "08:00:00",
                        scheduledDeparture: nil
                    )
                ]
            ],
            routeDirectionLabels: [routeKey: "Nord"],
            routeNamesByRouteID: ["55": GTFSRouteName(shortName: "55", longName: "Mock Route")],
            routeStylesByRouteID: [:],
            feedInfo: nil
        )
        let favoritesRepository = InMemoryFavoritesRepository(
            favorites: [
                FavoriteArrivalID(routeID: "99", directionID: "1", stopID: "missing-stop")
            ]
        )
        let viewModel = NearbyETAViewModel(
            gtfsRepository: StaticRepository(staticData: staticData),
            realtimeRepository: SnapshotRepository(snapshot: RealtimeSnapshot(vehicles: [], tripUpdates: [])),
            favoritesRepository: favoritesRepository,
            livePollInterval: .seconds(120)
        )

        viewModel.updateUserLocation(CLLocationCoordinate2D(latitude: 45.5001, longitude: -73.6001))
        viewModel.loadIfNeeded()

        try await waitUntil { viewModel.phase == .ready }

        XCTAssertTrue(viewModel.favoriteCards.isEmpty)
        XCTAssertFalse(viewModel.nearbyCards.isEmpty)
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval = 2.0,
        condition: @escaping () -> Bool
    ) async throws {
        let timeout = Date().addingTimeInterval(timeoutSeconds)
        while Date() < timeout {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for condition")
    }
}

private actor StaticRepository: GTFSRepository {
    let staticData: GTFSStaticData

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

private actor SnapshotRepository: RealtimeRepository {
    let snapshot: RealtimeSnapshot

    init(snapshot: RealtimeSnapshot) {
        self.snapshot = snapshot
    }

    func fetchSnapshot() async throws -> RealtimeSnapshot {
        snapshot
    }
}

private actor MutableSnapshotRepository: RealtimeRepository {
    private var snapshot: RealtimeSnapshot

    init(snapshot: RealtimeSnapshot) {
        self.snapshot = snapshot
    }

    func updateSnapshot(_ snapshot: RealtimeSnapshot) {
        self.snapshot = snapshot
    }

    func fetchSnapshot() async throws -> RealtimeSnapshot {
        snapshot
    }
}

private final class InMemoryFavoritesRepository: FavoritesRepository {
    private var favorites: [FavoriteArrivalID]

    init(favorites: [FavoriteArrivalID] = []) {
        self.favorites = favorites
    }

    func loadFavorites() -> [FavoriteArrivalID] {
        favorites
    }

    func saveFavorites(_ favorites: [FavoriteArrivalID]) {
        self.favorites = favorites
    }
}
