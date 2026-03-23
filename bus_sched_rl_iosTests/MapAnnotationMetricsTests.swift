import XCTest
@testable import bus_sched_rl_ios

final class MapAnnotationMetricsTests: XCTestCase {
    func testMinimumTapTargetMeetsAccessibilitySize() {
        XCTAssertGreaterThanOrEqual(MapAnnotationMetrics.minimumTapTarget, 44)
    }

    func testBusMarkerVisualCoreIsNotShrunk() {
        XCTAssertGreaterThanOrEqual(MapAnnotationMetrics.busCircleDiameter, 34)
    }

    func testBusLabelTypographyIsLargeEnoughForOutdoorReadability() {
        XCTAssertGreaterThanOrEqual(MapAnnotationMetrics.busRouteTextSize, 14)
        XCTAssertGreaterThanOrEqual(MapAnnotationMetrics.busDirectionTextSize, 12)
    }
}
