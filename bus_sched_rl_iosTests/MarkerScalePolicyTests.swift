import XCTest
@testable import bus_sched_rl_ios

final class MarkerScalePolicyTests: XCTestCase {
    func testScaleClampsToBounds() {
        let policy = MarkerScalePolicy.default

        let belowMinimum = policy.scale(forAltitude: policy.minAltitude / 10)
        let aboveMaximum = policy.scale(forAltitude: policy.maxAltitude * 10)

        XCTAssertEqual(belowMinimum, policy.maxScale, accuracy: 0.0001)
        XCTAssertEqual(aboveMaximum, policy.minScale, accuracy: 0.0001)
    }

    func testScaleDecreasesAsAltitudeIncreases() {
        let policy = MarkerScalePolicy.default
        let lowAltitude = policy.minAltitude
        let midAltitude = sqrt(policy.minAltitude * policy.maxAltitude)
        let highAltitude = policy.maxAltitude

        let lowScale = policy.scale(forAltitude: lowAltitude)
        let midScale = policy.scale(forAltitude: midAltitude)
        let highScale = policy.scale(forAltitude: highAltitude)

        XCTAssertGreaterThan(lowScale, midScale)
        XCTAssertGreaterThan(midScale, highScale)
    }

    func testSelectedScaleUsesConfiguredBoost() {
        let policy = MarkerScalePolicy.default
        let baseScale = policy.scale(forAltitude: 1_000)

        let selectedScale = policy.composedScale(baseScale: baseScale, isSelected: true)
        let unselectedScale = policy.composedScale(baseScale: baseScale, isSelected: false)

        XCTAssertEqual(unselectedScale, baseScale, accuracy: 0.0001)
        XCTAssertEqual(selectedScale, baseScale * policy.selectedScaleBoost, accuracy: 0.0001)
        XCTAssertGreaterThan(selectedScale, unselectedScale)
    }

    func testShouldApplyScaleHonorsThreshold() {
        let policy = MarkerScalePolicy.default
        let current: CGFloat = 1
        let tinyDelta = current + (policy.scaleUpdateThreshold * 0.4)
        let significantDelta = current + (policy.scaleUpdateThreshold * 1.2)

        XCTAssertFalse(policy.shouldApplyScale(current: current, next: tinyDelta))
        XCTAssertTrue(policy.shouldApplyScale(current: current, next: significantDelta))
    }
}
