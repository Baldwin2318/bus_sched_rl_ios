import XCTest
import CoreLocation
@testable import bus_sched_rl_ios

@MainActor
final class SearchViewModelTests: XCTestCase {
    func testDebouncePublishesLatestQueryResultsOnly() async throws {
        let vm = SearchViewModel()
        vm.setSearchIndex(makeIndex())
        vm.present()

        vm.query = "1"
        try await Task.sleep(for: .milliseconds(40))
        vm.query = "24"

        try await Task.sleep(for: .milliseconds(260))

        let routeMatches = vm.results.compactMap { result -> RouteSearchMatch? in
            if case .route(let route) = result { return route }
            return nil
        }

        XCTAssertEqual(routeMatches.first?.route.routeShortName, "24")
    }

    func testDismissCancelsInFlightSearch() async throws {
        let vm = SearchViewModel()
        vm.setSearchIndex(makeIndex())
        vm.present()

        vm.query = "165"
        vm.dismiss(clearQuery: false)

        try await Task.sleep(for: .milliseconds(260))

        XCTAssertFalse(vm.isPresented)
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertFalse(vm.isSearching)
    }

    private func makeIndex() -> SearchIndex {
        let routes = [
            RouteSearchEntry(
                routeId: "165",
                routeShortName: "165",
                routeLongName: "Cote-des-Neiges",
                routeColor: "00AEEF",
                directionOptions: [
                    RouteDirectionSearchEntry(directionId: "0", directionText: "Northbound")
                ]
            ),
            RouteSearchEntry(
                routeId: "24",
                routeShortName: "24",
                routeLongName: "Sherbrooke",
                routeColor: "E31C79",
                directionOptions: [
                    RouteDirectionSearchEntry(directionId: "0", directionText: "Towards Downtown")
                ]
            )
        ]

        let stops = [
            StopSearchEntry(
                stopId: "S1",
                stopName: "Cote-des-Neiges / 165",
                coordinate: CLLocationCoordinate2D(latitude: 45.5000, longitude: -73.6000),
                nearbyRouteIds: ["165"]
            ),
            StopSearchEntry(
                stopId: "S2",
                stopName: "Sherbrooke / 24",
                coordinate: CLLocationCoordinate2D(latitude: 45.5300, longitude: -73.6200),
                nearbyRouteIds: ["24"]
            )
        ]

        return SearchIndex(routes: routes, stops: stops)
    }
}
