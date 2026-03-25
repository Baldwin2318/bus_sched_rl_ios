import Foundation
import CoreLocation

enum VehicleFreshness: Equatable {
    case fresh
    case aging
    case stale

    var title: String {
        switch self {
        case .fresh:
            return "Fresh"
        case .aging:
            return "Aging"
        case .stale:
            return "Stale"
        }
    }
}

struct RenderedVehiclePosition: Equatable {
    let vehicle: VehiclePosition
    let coordinate: CLLocationCoordinate2D
    let heading: Double
    let freshness: VehicleFreshness
    let ageSeconds: TimeInterval?
    let isInterpolating: Bool
    let isSnappedToRoute: Bool

    static func == (lhs: RenderedVehiclePosition, rhs: RenderedVehiclePosition) -> Bool {
        lhs.vehicle == rhs.vehicle &&
            abs(lhs.coordinate.latitude - rhs.coordinate.latitude) < 0.000001 &&
            abs(lhs.coordinate.longitude - rhs.coordinate.longitude) < 0.000001 &&
            abs(lhs.heading - rhs.heading) < 0.000001 &&
            lhs.freshness == rhs.freshness &&
            lhs.ageSeconds == rhs.ageSeconds &&
            lhs.isInterpolating == rhs.isInterpolating &&
            lhs.isSnappedToRoute == rhs.isSnappedToRoute
    }
}

struct VehicleRenderState: Equatable {
    struct FreshnessThresholds: Equatable {
        let agingAfter: TimeInterval
        let staleAfter: TimeInterval

        static let `default` = FreshnessThresholds(
            agingAfter: 45,
            staleAfter: 90
        )
    }

    let current: VehiclePosition
    let previous: VehiclePosition?
    let receivedAt: Date
    let interpolationDuration: TimeInterval
    let expectedPollInterval: TimeInterval

    static func updated(
        existing: VehicleRenderState?,
        with vehicle: VehiclePosition,
        receivedAt: Date,
        expectedPollInterval: TimeInterval
    ) -> VehicleRenderState {
        guard let existing else {
            return VehicleRenderState(
                current: vehicle,
                previous: nil,
                receivedAt: receivedAt,
                interpolationDuration: expectedPollInterval,
                expectedPollInterval: expectedPollInterval
            )
        }

        if shouldKeepCurrentContinuity(existing.current, new: vehicle) {
            return VehicleRenderState(
                current: vehicle,
                previous: existing.previous,
                receivedAt: existing.receivedAt,
                interpolationDuration: existing.interpolationDuration,
                expectedPollInterval: expectedPollInterval
            )
        }

        let interpolationDuration = interpolationDuration(
            previous: existing.current,
            current: vehicle,
            expectedPollInterval: expectedPollInterval
        )

        return VehicleRenderState(
            current: vehicle,
            previous: existing.current,
            receivedAt: receivedAt,
            interpolationDuration: interpolationDuration,
            expectedPollInterval: expectedPollInterval
        )
    }

    func sample(
        at referenceDate: Date,
        routeShapePoints: [CLLocationCoordinate2D]? = nil,
        snapToRoute: Bool = false,
        maximumSnapDistanceMeters: CLLocationDistance = 35,
        freshnessThresholds: FreshnessThresholds = .default
    ) -> RenderedVehiclePosition {
        let ageSeconds = current.lastUpdatedAt.map { max(0, referenceDate.timeIntervalSince($0)) }
        let freshness = freshness(for: ageSeconds, thresholds: freshnessThresholds)
        let progress = interpolationProgress(at: referenceDate, freshness: freshness)

        let interpolatedCoordinate: CLLocationCoordinate2D
        let interpolatedHeading: Double
        if let previous {
            interpolatedCoordinate = TransitMath.interpolateCoordinate(
                from: previous.coord,
                to: current.coord,
                progress: progress
            )
            interpolatedHeading = TransitMath.interpolateHeadingDegrees(
                from: previous.heading,
                to: current.heading,
                progress: progress
            )
        } else {
            interpolatedCoordinate = current.coord
            interpolatedHeading = current.heading
        }

        let snappedCoordinate: CLLocationCoordinate2D
        let isSnappedToRoute: Bool
        if snapToRoute,
           freshness != .stale,
           let routeShapePoints,
           let routePoint = TransitMath.nearestPoint(
               on: routeShapePoints,
               to: interpolatedCoordinate,
               maximumDistanceMeters: maximumSnapDistanceMeters
           ) {
            snappedCoordinate = routePoint
            isSnappedToRoute = true
        } else {
            snappedCoordinate = interpolatedCoordinate
            isSnappedToRoute = false
        }

        return RenderedVehiclePosition(
            vehicle: current,
            coordinate: snappedCoordinate,
            heading: interpolatedHeading,
            freshness: freshness,
            ageSeconds: ageSeconds,
            isInterpolating: previous != nil && progress < 1,
            isSnappedToRoute: isSnappedToRoute
        )
    }

    private func interpolationProgress(at referenceDate: Date, freshness: VehicleFreshness) -> Double {
        guard previous != nil, freshness != .stale else { return 1 }
        let elapsed = max(0, referenceDate.timeIntervalSince(receivedAt))
        guard interpolationDuration > 0 else { return 1 }
        return min(1, max(0, elapsed / interpolationDuration))
    }

    private func freshness(
        for ageSeconds: TimeInterval?,
        thresholds: FreshnessThresholds
    ) -> VehicleFreshness {
        guard let ageSeconds else { return .aging }
        if ageSeconds >= thresholds.staleAfter {
            return .stale
        }
        if ageSeconds >= thresholds.agingAfter {
            return .aging
        }
        return .fresh
    }

    private static func shouldKeepCurrentContinuity(_ current: VehiclePosition, new: VehiclePosition) -> Bool {
        sameCoordinate(current.coord, new.coord) &&
            abs(current.heading - new.heading) < 0.000001 &&
            current.lastUpdatedAt == new.lastUpdatedAt
    }

    private static func interpolationDuration(
        previous: VehiclePosition,
        current: VehiclePosition,
        expectedPollInterval: TimeInterval
    ) -> TimeInterval {
        let rawDuration: TimeInterval? = {
            guard let previousDate = previous.lastUpdatedAt,
                  let currentDate = current.lastUpdatedAt else {
                return nil
            }
            return max(0, currentDate.timeIntervalSince(previousDate))
        }()

        let candidateDuration = rawDuration ?? expectedPollInterval
        return min(expectedPollInterval, max(1.0, candidateDuration))
    }

    private static func sameCoordinate(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> Bool {
        abs(lhs.latitude - rhs.latitude) < 0.000001 &&
            abs(lhs.longitude - rhs.longitude) < 0.000001
    }
}
