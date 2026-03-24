import XCTest
import CoreLocation
@testable import bus_sched_rl_ios

final class NearbyETAComposerTests: XCTestCase {
    func testComposeCardsPrefersLiveArrivalsAndCapsResultsAtTwenty() {
        let routeStopSchedules = Dictionary(uniqueKeysWithValues: (1...24).map { index in
            let routeKey = RouteKey(route: "\(index)", direction: "0")
            let stop = BusStop(
                id: "stop-\(index)",
                name: "Stop \(index)",
                coord: CLLocationCoordinate2D(latitude: 45.50 + (Double(index) * 0.0001), longitude: -73.60)
            )
            let schedule = RouteStopSchedule(
                stop: stop,
                sequence: 1,
                scheduledArrival: "08:00:00",
                scheduledDeparture: nil
            )
            return (routeKey, [schedule])
        })

        let staticData = makeStaticData(routeStopSchedules: routeStopSchedules)
        let index = TransitDataIndex(staticData: staticData)
        let now = Date()
        let snapshot = RealtimeSnapshot(
            vehicles: [],
            tripUpdates: (1...24).map { index in
                TripUpdatePayload(
                    tripID: "trip-\(index)",
                    routeID: "\(index)",
                    directionID: 0,
                    vehicleID: nil,
                    timestamp: now,
                    stopTimeUpdates: [
                        TripStopTimeUpdate(
                            stopID: "stop-\(index)",
                            stopSequence: 1,
                            arrivalTime: now.addingTimeInterval(Double(index) * 60),
                            departureTime: nil
                        )
                    ]
                )
            }
        )

        let cards = NearbyETAComposer().composeCards(
            staticData: staticData,
            index: index,
            snapshot: snapshot,
            userLocation: CLLocationCoordinate2D(latitude: 45.5001, longitude: -73.60),
            scope: .nearby,
            referenceDate: now
        )

        XCTAssertEqual(cards.count, 20)
        XCTAssertEqual(cards.first?.routeShortName, "1")
        XCTAssertEqual(cards.first?.source, .live)
        XCTAssertLessThanOrEqual(cards.first?.etaMinutes ?? .max, cards.last?.etaMinutes ?? .max)
    }

    func testComposeCardsForRouteScopeOnlyReturnsSelectedRoute() {
        let targetRoute = RouteKey(route: "55", direction: "1")
        let otherRoute = RouteKey(route: "80", direction: "0")

        let targetStop = BusStop(
            id: "target-stop",
            name: "Target Stop",
            coord: CLLocationCoordinate2D(latitude: 45.50, longitude: -73.60)
        )
        let otherStop = BusStop(
            id: "other-stop",
            name: "Other Stop",
            coord: CLLocationCoordinate2D(latitude: 45.51, longitude: -73.61)
        )

        let staticData = makeStaticData(
            routeStopSchedules: [
                targetRoute: [
                    RouteStopSchedule(
                        stop: targetStop,
                        sequence: 1,
                        scheduledArrival: "08:00:00",
                        scheduledDeparture: nil
                    )
                ],
                otherRoute: [
                    RouteStopSchedule(
                        stop: otherStop,
                        sequence: 1,
                        scheduledArrival: "08:05:00",
                        scheduledDeparture: nil
                    )
                ]
            ],
            routeDirectionLabels: [
                targetRoute: "Sud",
                otherRoute: "Nord"
            ]
        )

        let cards = NearbyETAComposer().composeCards(
            staticData: staticData,
            index: TransitDataIndex(staticData: staticData),
            snapshot: RealtimeSnapshot(vehicles: [], tripUpdates: []),
            userLocation: CLLocationCoordinate2D(latitude: 45.5002, longitude: -73.6001),
            scope: .route(routeID: "55", directionID: "1"),
            referenceDate: Date()
        )

        XCTAssertFalse(cards.isEmpty)
        XCTAssertTrue(cards.allSatisfy { $0.routeID == "55" && $0.directionID == "1" })
    }

    func testComposeCardsCarriesLiveVehicleIdentityForLiveArrivals() {
        let now = Date()
        let routeKey = RouteKey(route: "55", direction: "0")
        let stop = BusStop(
            id: "stop-1",
            name: "Main Stop",
            coord: CLLocationCoordinate2D(latitude: 45.50, longitude: -73.60)
        )
        let staticData = makeStaticData(
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
            routeDirectionLabels: [routeKey: "Nord"]
        )
        let snapshot = RealtimeSnapshot(
            vehicles: [
                VehiclePosition(
                    id: "vehicle-1",
                    tripID: "trip-1",
                    route: "55",
                    direction: 0,
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

        let cards = NearbyETAComposer().composeCards(
            staticData: staticData,
            index: TransitDataIndex(staticData: staticData),
            snapshot: snapshot,
            userLocation: CLLocationCoordinate2D(latitude: 45.5001, longitude: -73.6001),
            scope: .nearby,
            referenceDate: now
        )

        XCTAssertEqual(cards.first?.source, .live)
        XCTAssertEqual(cards.first?.tripID, "trip-1")
        XCTAssertEqual(cards.first?.liveVehicleID, "vehicle-1")
    }

    func testComposeCardsScheduledListIgnoresLiveDataAndDoesNotCapResults() {
        let now = Date()
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
        let staticData = makeStaticData(routeStopSchedules: routeStopSchedules)
        let snapshot = RealtimeSnapshot(
            vehicles: [],
            tripUpdates: (1...24).map { index in
                TripUpdatePayload(
                    tripID: "trip-\(index)",
                    routeID: "\(index)",
                    directionID: 0,
                    vehicleID: nil,
                    timestamp: now,
                    stopTimeUpdates: [
                        TripStopTimeUpdate(
                            stopID: "stop-\(index)",
                            stopSequence: 1,
                            arrivalTime: now.addingTimeInterval(2 * 60),
                            departureTime: nil
                        )
                    ]
                )
            }
        )

        let cards = NearbyETAComposer().composeCards(
            staticData: staticData,
            index: TransitDataIndex(staticData: staticData),
            snapshot: snapshot,
            userLocation: nil,
            scope: .nearby,
            feedMode: .scheduledList,
            referenceDate: now
        )

        XCTAssertEqual(cards.count, 24)
        XCTAssertTrue(cards.allSatisfy { $0.source == .scheduled })
        XCTAssertTrue(cards.allSatisfy { $0.liveVehicleID == nil })
    }

    private func makeStaticData(
        routeStopSchedules: [RouteKey: [RouteStopSchedule]],
        routeDirectionLabels: [RouteKey: String] = [:]
    ) -> GTFSStaticData {
        let routeStops = routeStopSchedules.mapValues { $0.map(\.stop) }
        let routeNamesByRouteID = Dictionary(uniqueKeysWithValues: routeStopSchedules.keys.map { key in
            (key.route, GTFSRouteName(shortName: key.route, longName: "Route \(key.route)"))
        })

        return GTFSStaticData(
            routeStops: routeStops,
            routeStopSchedules: routeStopSchedules,
            routeDirectionLabels: routeDirectionLabels,
            routeNamesByRouteID: routeNamesByRouteID,
            routeStylesByRouteID: [:],
            feedInfo: nil
        )
    }
}
