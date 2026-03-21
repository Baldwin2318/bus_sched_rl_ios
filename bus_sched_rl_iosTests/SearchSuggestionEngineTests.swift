import XCTest
import CoreLocation
@testable import bus_sched_rl_ios

final class SearchSuggestionEngineTests: XCTestCase {
    func testNoLocationFallsBackToKnownRoutes() async {
        let engine = SearchSuggestionEngine()
        let suggestions = await engine.buildSuggestions(
            vehicles: [],
            nearbyRoutes: [],
            allRoutes: ["165", "166", "72"],
            routeStops: [:],
            routeDirectionLabels: [:],
            userLocation: nil
        )

        XCTAssertEqual(suggestions.map(\.route), ["165", "166", "72"])
    }

    func testNearbyRoutesProduceSuggestionsWithDirectionLabel() async {
        let engine = SearchSuggestionEngine()
        let routeKey = RouteKey(route: "165", direction: "0")
        let suggestions = await engine.buildSuggestions(
            vehicles: [],
            nearbyRoutes: [routeKey],
            allRoutes: [],
            routeStops: [
                routeKey: [
                    BusStop(
                        id: "s1",
                        name: "Test Stop",
                        coord: CLLocationCoordinate2D(latitude: 45.5, longitude: -73.6)
                    )
                ]
            ],
            routeDirectionLabels: [routeKey: "Nord"],
            userLocation: CLLocationCoordinate2D(latitude: 45.5001, longitude: -73.6001)
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.route, "165")
        XCTAssertEqual(suggestions.first?.displayDirection, "Nord")
    }
}
