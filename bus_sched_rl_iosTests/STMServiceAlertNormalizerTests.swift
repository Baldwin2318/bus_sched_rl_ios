import XCTest
import CoreLocation
@testable import bus_sched_rl_ios

final class STMServiceAlertNormalizerTests: XCTestCase {
    func testNormalizeResolvesSTMRouteDirectionAndStopIdentifiers() {
        let northStop = BusStop(
            id: "stop-north",
            stopCode: "53010",
            name: "North Stop",
            coord: CLLocationCoordinate2D(latitude: 45.50, longitude: -73.60)
        )
        let southStop = BusStop(
            id: "stop-south",
            stopCode: "53051",
            name: "South Stop",
            coord: CLLocationCoordinate2D(latitude: 45.51, longitude: -73.61)
        )
        let staticData = GTFSStaticData(
            routeStops: [
                RouteKey(route: "route-10", direction: "0"): [northStop],
                RouteKey(route: "route-10", direction: "1"): [southStop]
            ],
            routeStopSchedules: [
                RouteKey(route: "route-10", direction: "0"): [
                    RouteStopSchedule(stop: northStop, sequence: 1, scheduledArrival: "08:00:00", scheduledDeparture: nil)
                ],
                RouteKey(route: "route-10", direction: "1"): [
                    RouteStopSchedule(stop: southStop, sequence: 1, scheduledArrival: "08:05:00", scheduledDeparture: nil)
                ]
            ],
            routeDirectionLabels: [
                RouteKey(route: "route-10", direction: "0"): "Nord",
                RouteKey(route: "route-10", direction: "1"): "Sud"
            ],
            routeNamesByRouteID: [
                "route-10": GTFSRouteName(shortName: "10", longName: "Mock Route 10")
            ],
            routeStylesByRouteID: [:],
            feedInfo: nil
        )
        let rawAlert = ServiceAlert(
            id: "stm-raw",
            source: .stmServiceStatus,
            title: "Your stop",
            message: "This stop is relocated.",
            severity: .warning,
            url: nil,
            activePeriods: [],
            scopes: [
                AlertScopeSelector(routeID: "10", directionID: "N", stopID: "53010", tripID: nil)
            ]
        )

        let normalized = STMServiceAlertNormalizer.normalize(
            [rawAlert],
            staticData: staticData,
            index: TransitDataIndex(staticData: staticData)
        )

        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized[0].scopes, [
            AlertScopeSelector(routeID: "route-10", directionID: "0", stopID: "stop-north", tripID: nil)
        ])
    }
}
