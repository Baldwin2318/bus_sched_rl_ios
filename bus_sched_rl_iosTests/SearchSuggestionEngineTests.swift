import XCTest
import CoreLocation
@testable import bus_sched_rl_ios

final class SearchSuggestionEngineTests: XCTestCase {
    func testPrefixQueryMatchesRoutes() async {
        let engine = SearchSuggestionEngine()
        let suggestions = await engine.buildSuggestions(
            query: "16",
            vehicles: [],
            nearbyRoutes: [],
            allRoutes: ["165", "166", "72"],
            routePrefixIndex: ["16": ["165", "166"]],
            routeStops: [:],
            userLocation: CLLocationCoordinate2D(latitude: 45.5, longitude: -73.6)
        )

        let titles = suggestions.map { $0.route }
        XCTAssertTrue(titles.contains("165"))
        XCTAssertTrue(titles.contains("166"))
    }
}
