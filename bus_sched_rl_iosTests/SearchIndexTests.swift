import XCTest
import CoreLocation
@testable import bus_sched_rl_ios

final class SearchIndexTests: XCTestCase {
    func testExactRouteNumberRanksBeforePrefixMatches() {
        let index = makeIndex()

        let results = index.search(
            query: "10",
            userLocation: nil,
            limit: 20
        )

        let routes = routeMatches(from: results)
        XCTAssertGreaterThanOrEqual(routes.count, 2)
        XCTAssertEqual(routes.first?.route.routeId, "10")
        XCTAssertTrue(routes.contains(where: { $0.route.routeId == "100" }))
    }

    func testDirectionContainsQueryIncludesDirectionInResult() {
        let index = makeIndex()

        let results = index.search(
            query: "downtown",
            userLocation: nil,
            limit: 20
        )

        let routes = routeMatches(from: results)
        XCTAssertFalse(routes.isEmpty)
        XCTAssertTrue(routes.allSatisfy { match in
            guard let direction = match.directionText else { return false }
            return direction.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .contains("downtown")
        })
    }

    func testMultiTokenQueryRequiresAllTokens() {
        let index = makeIndex()

        let results = index.search(
            query: "24 downtown",
            userLocation: nil,
            limit: 20
        )

        let routes = routeMatches(from: results)
        XCTAssertEqual(routes.first?.route.routeId, "24")
        XCTAssertEqual(routes.filter { $0.route.routeId == "24" }.count, 1)
        XCTAssertEqual(routes.first?.directionText, "Towards Downtown")
    }

    func testExactRouteNumberReturnsAllDirectionsForRoute() {
        let index = makeIndex()

        let results = index.search(
            query: "24",
            userLocation: nil,
            limit: 20
        )

        let routes = routeMatches(from: results)
        let route24Matches = routes.filter { $0.route.routeId == "24" }

        XCTAssertEqual(route24Matches.count, 2)
        XCTAssertEqual(
            route24Matches.compactMap(\.directionText),
            ["Towards Downtown", "Towards East"]
        )
    }

    func testSearchIsAccentInsensitiveAndTrimmed() {
        let index = makeIndex()

        let routeResults = index.search(
            query: "  cote  ",
            userLocation: nil,
            limit: 20
        )
        XCTAssertTrue(routeMatches(from: routeResults).contains(where: { $0.route.routeId == "165" }))

        let stopResults = index.search(
            query: "uqam",
            userLocation: nil,
            limit: 20
        )
        XCTAssertTrue(stopMatches(from: stopResults).contains(where: { $0.stop.stopId == "S1" }))
    }

    func testRouteResultsAreDeduplicatedAndCappedAtTwenty() {
        let index = makeLargeIndex()

        let results = index.search(
            query: "1",
            userLocation: nil,
            limit: 20
        )

        let routes = routeMatches(from: results)
        XCTAssertLessThanOrEqual(routes.count, 20)

        let uniqueRouteDirections = Set(routes.map { "\($0.route.routeId):\($0.directionId ?? "_")" })
        XCTAssertEqual(uniqueRouteDirections.count, routes.count)
    }

    func testNearbyRoutesAreSortedByDistanceAndExposeDirection() {
        let index = makeIndex()

        let nearby = index.nearbyRoutes(
            around: CLLocationCoordinate2D(latitude: 45.5001, longitude: -73.6001),
            limit: 20
        )

        XCTAssertGreaterThanOrEqual(nearby.count, 4)
        XCTAssertEqual(nearby[0].route.routeId, "10")
        XCTAssertEqual(nearby[0].directionText, "Towards Downtown")
        XCTAssertEqual(nearby[1].route.routeId, "24")
        XCTAssertEqual(nearby[1].directionText, "Towards Downtown")
        XCTAssertEqual(nearby[2].route.routeId, "24")
        XCTAssertEqual(nearby[2].directionText, "Towards East")
    }

    private func routeMatches(from results: [SearchResult]) -> [RouteSearchMatch] {
        results.compactMap { result in
            if case .route(let route) = result { return route }
            return nil
        }
    }

    private func stopMatches(from results: [SearchResult]) -> [StopSearchMatch] {
        results.compactMap { result in
            if case .stop(let stop) = result { return stop }
            return nil
        }
    }

    private func makeIndex() -> SearchIndex {
        let routes = [
            RouteSearchEntry(
                routeId: "24",
                routeShortName: "24",
                routeLongName: "Sherbrooke",
                routeColor: "E31C79",
                directionOptions: [
                    RouteDirectionSearchEntry(directionId: "0", directionText: "Towards Downtown"),
                    RouteDirectionSearchEntry(directionId: "1", directionText: "Towards East")
                ]
            ),
            RouteSearchEntry(
                routeId: "100",
                routeShortName: "100",
                routeLongName: "Airport Express",
                routeColor: "0099CC",
                directionOptions: [
                    RouteDirectionSearchEntry(directionId: "0", directionText: "Towards Airport")
                ]
            ),
            RouteSearchEntry(
                routeId: "10",
                routeShortName: "10",
                routeLongName: "Verdun Local",
                routeColor: "00AA55",
                directionOptions: [
                    RouteDirectionSearchEntry(directionId: "0", directionText: "Towards Downtown")
                ]
            ),
            RouteSearchEntry(
                routeId: "165",
                routeShortName: "165",
                routeLongName: "Côte-des-Neiges",
                routeColor: "00AEEF",
                directionOptions: [
                    RouteDirectionSearchEntry(directionId: "0", directionText: "Northbound")
                ]
            )
        ]

        let stops = [
            StopSearchEntry(
                stopId: "S1",
                stopName: "Berri-UQAM",
                coordinate: CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.6000),
                nearbyRouteIds: ["24", "10"]
            ),
            StopSearchEntry(
                stopId: "S2",
                stopName: "Sherbrooke / Atwater",
                coordinate: CLLocationCoordinate2D(latitude: 45.5050, longitude: -73.6050),
                nearbyRouteIds: ["24"]
            ),
            StopSearchEntry(
                stopId: "S3",
                stopName: "Côte-des-Neiges / Queen-Mary",
                coordinate: CLLocationCoordinate2D(latitude: 45.5300, longitude: -73.6200),
                nearbyRouteIds: ["165"]
            )
        ]

        return SearchIndex(routes: routes, stops: stops)
    }

    private func makeLargeIndex() -> SearchIndex {
        var routes: [RouteSearchEntry] = []
        for routeNumber in 100...140 {
            let id = String(routeNumber)
            routes.append(
                RouteSearchEntry(
                    routeId: id,
                    routeShortName: id,
                    routeLongName: "Route \(id)",
                    routeColor: nil,
                    directionOptions: [
                        RouteDirectionSearchEntry(directionId: "0", directionText: "Direction \(id)")
                    ]
                )
            )
        }

        let stops = [
            StopSearchEntry(
                stopId: "S-LARGE",
                stopName: "Terminal 100",
                coordinate: CLLocationCoordinate2D(latitude: 45.49, longitude: -73.59),
                nearbyRouteIds: routes.map(\.routeId)
            )
        ]

        return SearchIndex(routes: routes, stops: stops)
    }
}
