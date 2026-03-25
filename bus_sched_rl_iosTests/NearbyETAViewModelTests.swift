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

    func testLiveVehicleRenderUsesContinuityCacheForCurrentCard() async throws {
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
            routeShapeIDByRouteKey: [routeKey: "shape-55"],
            shapeIDByTripID: ["trip-1": "shape-55"],
            shapePointsByShapeID: [
                "shape-55": [
                    CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.6000),
                    CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.6010)
                ]
            ],
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
                    heading: 90,
                    coord: CLLocationCoordinate2D(latitude: 45.5002, longitude: -73.6004),
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
        let renderedVehicle = try XCTUnwrap(viewModel.liveVehicleRender(for: liveCard, referenceDate: now))

        XCTAssertEqual(renderedVehicle.vehicle.id, "vehicle-1")
        XCTAssertEqual(renderedVehicle.heading, 90, accuracy: 0.001)
        XCTAssertEqual(renderedVehicle.freshness, .fresh)
        XCTAssertTrue(renderedVehicle.isSnappedToRoute)
    }

    func testCardQualitySurfacesStatusFreshnessAndDelay() async throws {
        let routeKey = RouteKey(route: "55", direction: "0")
        let stop = BusStop(
            id: "stop-1",
            name: "Main Stop",
            coord: CLLocationCoordinate2D(latitude: 45.50, longitude: -73.60)
        )
        let now = Date()
        let staticData = GTFSStaticData(
            routeStops: [routeKey: [stop]],
            routeStopSchedules: [routeKey: [
                RouteStopSchedule(stop: stop, sequence: 1, scheduledArrival: "23:59:00", scheduledDeparture: nil)
            ]],
            routeDirectionLabels: [routeKey: "Nord"],
            routeNamesByRouteID: ["55": GTFSRouteName(shortName: "55", longName: "Mock Route")],
            routeStylesByRouteID: [:],
            feedInfo: nil
        )
        let snapshot = RealtimeSnapshot(
            vehicles: [
                VehiclePosition(
                    id: "vehicle-1",
                    tripID: "trip-1",
                    route: "55",
                    direction: 0,
                    currentStatus: .incomingAt,
                    heading: 90,
                    coord: CLLocationCoordinate2D(latitude: 45.5002, longitude: -73.6004),
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
                    delaySeconds: 300,
                    stopTimeUpdates: [
                        TripStopTimeUpdate(
                            stopID: "stop-1",
                            stopSequence: 1,
                            arrivalTime: now.addingTimeInterval(3 * 60),
                            departureTime: nil,
                            delaySeconds: 300
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
        let quality = try XCTUnwrap(viewModel.cardQuality(for: liveCard, referenceDate: now))

        XCTAssertEqual(quality.statusText, "Approaching stop")
        XCTAssertEqual(quality.freshness, .fresh)
        XCTAssertEqual(quality.delayText, "5 min late")
    }

    func testArrivalLiveMapModelHidesStaleVehicle() async throws {
        let routeKey = RouteKey(route: "55", direction: "0")
        let stop = BusStop(
            id: "stop-1",
            name: "Main Stop",
            coord: CLLocationCoordinate2D(latitude: 45.50, longitude: -73.60)
        )
        let now = Date()
        let staleTime = now.addingTimeInterval(-180)
        let staticData = GTFSStaticData(
            routeStops: [routeKey: [stop]],
            routeStopSchedules: [routeKey: [
                RouteStopSchedule(stop: stop, sequence: 1, scheduledArrival: "23:59:00", scheduledDeparture: nil)
            ]],
            routeDirectionLabels: [routeKey: "Nord"],
            routeNamesByRouteID: ["55": GTFSRouteName(shortName: "55", longName: "Mock Route")],
            routeStylesByRouteID: [:],
            feedInfo: nil
        )
        let snapshot = RealtimeSnapshot(
            vehicles: [
                VehiclePosition(
                    id: "vehicle-1",
                    tripID: "trip-1",
                    route: "55",
                    direction: 0,
                    heading: 90,
                    coord: CLLocationCoordinate2D(latitude: 45.5002, longitude: -73.6004),
                    lastUpdatedAt: staleTime
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

        XCTAssertNil(
            viewModel.arrivalLiveMapModel(
                for: liveCard,
                userLocation: CLLocationCoordinate2D(latitude: 45.5001, longitude: -73.6001),
                referenceDate: now
            )
        )
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

    func testDeniedLocationShowsUnlimitedScheduledBusList() async throws {
        let routeStopSchedules = Dictionary(uniqueKeysWithValues: (1...24).map { index in
            let routeKey = RouteKey(route: "\(index)", direction: "0")
            let stop = BusStop(
                id: "stop-\(index)",
                name: "Stop \(index)",
                coord: CLLocationCoordinate2D(latitude: 45.50 + (Double(index) * 0.0001), longitude: -73.60)
            )
            return (
                routeKey,
                [
                    RouteStopSchedule(
                        stop: stop,
                        sequence: 1,
                        scheduledArrival: "23:59:00",
                        scheduledDeparture: nil
                    )
                ]
            )
        })
        let staticData = GTFSStaticData(
            routeStops: routeStopSchedules.mapValues { $0.map(\.stop) },
            routeStopSchedules: routeStopSchedules,
            routeDirectionLabels: [:],
            routeNamesByRouteID: Dictionary(uniqueKeysWithValues: (1...24).map {
                ("\($0)", GTFSRouteName(shortName: "\($0)", longName: "Route \($0)"))
            }),
            routeStylesByRouteID: [:],
            feedInfo: nil
        )
        let now = Date()
        let snapshot = RealtimeSnapshot(
            vehicles: [],
            tripUpdates: [
                TripUpdatePayload(
                    tripID: "trip-1",
                    routeID: "1",
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
        let viewModel = NearbyETAViewModel(
            gtfsRepository: StaticRepository(staticData: staticData),
            realtimeRepository: SnapshotRepository(snapshot: snapshot),
            livePollInterval: .seconds(120)
        )

        viewModel.updateLocationAuthorization(.denied)
        viewModel.loadIfNeeded()

        try await waitUntil { !viewModel.nearbyCards.isEmpty }

        XCTAssertEqual(viewModel.titleText, "Scheduled buses")
        XCTAssertEqual(viewModel.nearbyCards.count, 24)
        XCTAssertTrue(viewModel.nearbyCards.allSatisfy { $0.source == .scheduled })
        XCTAssertEqual(viewModel.subtitleText, "Showing all scheduled buses until location access is turned on.")
    }

    func testMainAlertsMatchVisibleCardsAndIgnoreUnrelatedScopes() async throws {
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
        let snapshot = RealtimeSnapshot(
            vehicles: [],
            tripUpdates: [],
            alerts: [
                makeAlert(
                    id: "matching-alert",
                    routeID: "55",
                    directionID: "0",
                    stopID: "stop-1",
                    severity: .warning
                ),
                makeAlert(
                    id: "other-route-alert",
                    routeID: "80",
                    directionID: "0",
                    stopID: "stop-1",
                    severity: .warning
                ),
                makeAlert(
                    id: "global-alert",
                    routeID: nil,
                    directionID: nil,
                    stopID: nil,
                    severity: .info
                ),
            ]
        )
        let viewModel = NearbyETAViewModel(
            gtfsRepository: StaticRepository(staticData: staticData),
            realtimeRepository: SnapshotRepository(snapshot: snapshot),
            livePollInterval: .seconds(120)
        )

        viewModel.updateUserLocation(CLLocationCoordinate2D(latitude: 45.5001, longitude: -73.6001))
        viewModel.loadIfNeeded()

        try await waitUntil { !viewModel.nearbyCards.isEmpty }

        XCTAssertEqual(viewModel.mainAlerts.map(\.id), ["matching-alert", "global-alert"])
    }

    func testDetailAlertsFilterToSelectedRouteAndStop() async throws {
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
        let snapshot = RealtimeSnapshot(
            vehicles: [],
            tripUpdates: [],
            alerts: [
                makeAlert(
                    id: "detail-match",
                    routeID: "55",
                    directionID: "0",
                    stopID: "stop-1",
                    severity: .warning
                ),
                makeAlert(
                    id: "detail-miss",
                    routeID: "55",
                    directionID: "0",
                    stopID: "stop-2",
                    severity: .warning
                ),
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
        let card = try XCTUnwrap(viewModel.cards.first)

        XCTAssertEqual(viewModel.alerts(for: card).map(\.id), ["detail-match"])
    }

    func testGlobalSTMNoticesStayOnMainScreenButNotDetailAlerts() async throws {
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
        let snapshot = RealtimeSnapshot(
            vehicles: [],
            tripUpdates: [],
            alerts: [
                ServiceAlert(
                    id: "stm-global",
                    source: .stmServiceStatus,
                    title: "STM network disruption",
                    message: "System-wide service is affected.",
                    severity: .severe,
                    url: nil,
                    activePeriods: [],
                    scopes: []
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
        let card = try XCTUnwrap(viewModel.cards.first)

        XCTAssertEqual(viewModel.mainAlerts.map(\.id), ["stm-global"])
        XCTAssertTrue(viewModel.alerts(for: card).isEmpty)
    }

    func testDetailHelpersResolveTripUpdateAndAssignedStop() async throws {
        let routeKey = RouteKey(route: "55", direction: "0")
        let originalStop = BusStop(
            id: "stop-1",
            name: "Main Stop",
            coord: CLLocationCoordinate2D(latitude: 45.50, longitude: -73.60)
        )
        let reassignedStop = BusStop(
            id: "stop-2",
            name: "Temporary Stop",
            coord: CLLocationCoordinate2D(latitude: 45.501, longitude: -73.601)
        )
        let staticData = GTFSStaticData(
            routeStops: [routeKey: [originalStop, reassignedStop]],
            routeStopSchedules: [
                routeKey: [
                    RouteStopSchedule(
                        stop: originalStop,
                        sequence: 1,
                        scheduledArrival: "08:00:00",
                        scheduledDeparture: nil
                    ),
                    RouteStopSchedule(
                        stop: reassignedStop,
                        sequence: 2,
                        scheduledArrival: "08:05:00",
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
                    stopID: "stop-1",
                    currentStatus: .incomingAt,
                    congestionLevel: .congestion,
                    occupancyStatus: .standingRoomOnly,
                    occupancyPercentage: 78,
                    heading: 90,
                    coord: CLLocationCoordinate2D(latitude: 45.5004, longitude: -73.6004),
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
                    delaySeconds: 240,
                    stopTimeUpdates: [
                        TripStopTimeUpdate(
                            stopID: "stop-1",
                            stopSequence: 1,
                            arrivalTime: now.addingTimeInterval(4 * 60),
                            departureTime: nil,
                            assignedStopID: "stop-2",
                            delaySeconds: 240
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
        let card = try XCTUnwrap(viewModel.cards.first)

        XCTAssertEqual(viewModel.tripUpdate(for: card)?.delaySeconds, 240)
        XCTAssertEqual(viewModel.assignedStop(for: card)?.id, "stop-2")
    }

    func testStaticDataOlderThanSixMonthsShowsRefreshState() async throws {
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
        let staleMetadata = GTFSCacheMetadata(
            lastUpdatedAt: Calendar.current.date(byAdding: .month, value: -7, to: Date()),
            etag: nil,
            lastModified: nil,
            feedInfo: nil
        )
        let viewModel = NearbyETAViewModel(
            gtfsRepository: StaticRepository(staticData: staticData, metadata: staleMetadata),
            realtimeRepository: SnapshotRepository(snapshot: RealtimeSnapshot(vehicles: [], tripUpdates: [])),
            livePollInterval: .seconds(120)
        )

        viewModel.loadIfNeeded()
        try await waitUntil { viewModel.phase == .ready }

        XCTAssertTrue(viewModel.staticDataNeedsRefresh)
        XCTAssertTrue(viewModel.showsStaticDataUpdatePrompt)
        XCTAssertEqual(viewModel.staticDataStatusTitle, "Transit data update available")
    }

    func testStaticDataNewerThanSixMonthsHidesRefreshPrompt() async throws {
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
        let freshMetadata = GTFSCacheMetadata(
            lastUpdatedAt: Calendar.current.date(byAdding: .month, value: -2, to: Date()),
            etag: nil,
            lastModified: nil,
            feedInfo: nil
        )
        let viewModel = NearbyETAViewModel(
            gtfsRepository: StaticRepository(staticData: staticData, metadata: freshMetadata),
            realtimeRepository: SnapshotRepository(snapshot: RealtimeSnapshot(vehicles: [], tripUpdates: [])),
            livePollInterval: .seconds(120)
        )

        viewModel.loadIfNeeded()
        try await waitUntil { viewModel.phase == .ready }

        XCTAssertFalse(viewModel.staticDataNeedsRefresh)
        XCTAssertFalse(viewModel.showsStaticDataUpdatePrompt)
    }

    func testRedownloadStaticDataForcesRefreshAndUpdatesMetadata() async throws {
        let oldRouteKey = RouteKey(route: "55", direction: "0")
        let newRouteKey = RouteKey(route: "80", direction: "0")
        let oldStop = BusStop(
            id: "stop-1",
            name: "Main Stop",
            coord: CLLocationCoordinate2D(latitude: 45.50, longitude: -73.60)
        )
        let newStop = BusStop(
            id: "stop-2",
            name: "Second Stop",
            coord: CLLocationCoordinate2D(latitude: 45.51, longitude: -73.61)
        )
        let initialStaticData = GTFSStaticData(
            routeStops: [oldRouteKey: [oldStop]],
            routeStopSchedules: [
                oldRouteKey: [
                    RouteStopSchedule(
                        stop: oldStop,
                        sequence: 1,
                        scheduledArrival: "08:00:00",
                        scheduledDeparture: nil
                    )
                ]
            ],
            routeDirectionLabels: [oldRouteKey: "Nord"],
            routeNamesByRouteID: ["55": GTFSRouteName(shortName: "55", longName: "Mock Route")],
            routeStylesByRouteID: [:],
            feedInfo: nil
        )
        let refreshedStaticData = GTFSStaticData(
            routeStops: [newRouteKey: [newStop]],
            routeStopSchedules: [
                newRouteKey: [
                    RouteStopSchedule(
                        stop: newStop,
                        sequence: 1,
                        scheduledArrival: "09:00:00",
                        scheduledDeparture: nil
                    )
                ]
            ],
            routeDirectionLabels: [newRouteKey: "Sud"],
            routeNamesByRouteID: ["80": GTFSRouteName(shortName: "80", longName: "Updated Route")],
            routeStylesByRouteID: [:],
            feedInfo: nil
        )
        let staleMetadata = GTFSCacheMetadata(
            lastUpdatedAt: Calendar.current.date(byAdding: .month, value: -7, to: Date()),
            etag: nil,
            lastModified: nil,
            feedInfo: nil
        )
        let refreshedMetadata = GTFSCacheMetadata(
            lastUpdatedAt: Date(),
            etag: "new-etag",
            lastModified: nil,
            feedInfo: nil
        )
        let repository = StaticRepository(
            staticData: initialStaticData,
            metadata: staleMetadata,
            refreshedStaticData: refreshedStaticData,
            refreshedMetadata: refreshedMetadata
        )
        let viewModel = NearbyETAViewModel(
            gtfsRepository: repository,
            realtimeRepository: SnapshotRepository(snapshot: RealtimeSnapshot(vehicles: [], tripUpdates: [])),
            livePollInterval: .seconds(120)
        )

        viewModel.updateLocationAuthorization(.denied)
        viewModel.loadIfNeeded()
        try await waitUntil { viewModel.phase == .ready }

        XCTAssertTrue(viewModel.staticDataNeedsRefresh)

        viewModel.redownloadStaticData()

        try await waitUntil {
            !viewModel.isRefreshingStaticData &&
                viewModel.nearbyCards.contains(where: { $0.routeID == "80" })
        }

        XCTAssertEqual(await repository.forcedRefreshRequests(), [true])
        XCTAssertFalse(viewModel.staticDataNeedsRefresh)
        XCTAssertFalse(viewModel.showsStaticDataUpdatePrompt)
        XCTAssertEqual(viewModel.staticCacheMetadata.lastUpdatedAt, refreshedMetadata.lastUpdatedAt)
        XCTAssertTrue(viewModel.nearbyCards.contains(where: { $0.routeID == "80" }))
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

    private func makeAlert(
        id: String,
        routeID: String?,
        directionID: String?,
        stopID: String?,
        severity: AlertSeverity
    ) -> ServiceAlert {
        ServiceAlert(
            id: id,
            title: id,
            message: nil,
            severity: severity,
            url: nil,
            activePeriods: [],
            scopes: [
                AlertScopeSelector(
                    routeID: routeID,
                    directionID: directionID,
                    stopID: stopID,
                    tripID: nil
                )
            ]
        )
    }
}

private actor StaticRepository: GTFSRepository {
    let staticData: GTFSStaticData
    private let refreshedStaticData: GTFSStaticData?
    private var metadata: GTFSCacheMetadata
    private let refreshedMetadata: GTFSCacheMetadata?
    private var refreshForceFlags: [Bool] = []

    init(
        staticData: GTFSStaticData,
        metadata: GTFSCacheMetadata = .empty,
        refreshedStaticData: GTFSStaticData? = nil,
        refreshedMetadata: GTFSCacheMetadata? = nil
    ) {
        self.staticData = staticData
        self.metadata = metadata
        self.refreshedStaticData = refreshedStaticData
        self.refreshedMetadata = refreshedMetadata
    }

    func loadStaticData() async throws -> GTFSStaticData {
        staticData
    }

    func refreshStaticData(force: Bool) async throws -> GTFSStaticData {
        refreshForceFlags.append(force)
        if let refreshedMetadata {
            metadata = refreshedMetadata
        }
        return refreshedStaticData ?? staticData
    }

    func cacheMetadata() async -> GTFSCacheMetadata {
        metadata
    }

    func forcedRefreshRequests() async -> [Bool] {
        refreshForceFlags
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
