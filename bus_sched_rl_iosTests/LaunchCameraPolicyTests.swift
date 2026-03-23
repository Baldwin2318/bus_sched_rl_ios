import XCTest
@testable import bus_sched_rl_ios

final class LaunchCameraPolicyTests: XCTestCase {
    func testDecisionCentersOnUserWhenLocationIsAvailable() {
        let decision = LaunchCameraPolicy.decision(
            currentLocationAvailable: true,
            hasPersistedCamera: true
        )

        XCTAssertEqual(decision, .centerOnUser)
    }

    func testDecisionRestoresPersistedCameraWhenLocationIsUnavailable() {
        let decision = LaunchCameraPolicy.decision(
            currentLocationAvailable: false,
            hasPersistedCamera: true
        )

        XCTAssertEqual(decision, .restorePersisted)
    }

    func testDecisionReturnsNoneWithoutLocationOrPersistedCamera() {
        let decision = LaunchCameraPolicy.decision(
            currentLocationAvailable: false,
            hasPersistedCamera: false
        )

        XCTAssertEqual(decision, .none)
    }
}
