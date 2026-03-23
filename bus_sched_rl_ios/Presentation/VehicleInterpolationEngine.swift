import Foundation
import CoreLocation

actor VehicleInterpolationEngine {
    private enum TransitionCurve {
        case linear
        case easeInOut
    }

    private struct RoutePath {
        let points: [CLLocationCoordinate2D]
        let cumulativeDistances: [CLLocationDistance]
        let totalLength: CLLocationDistance
    }

    private enum TransitionMode {
        case snap
        case straight(
            from: CLLocationCoordinate2D,
            to: CLLocationCoordinate2D,
            bearing: Double,
            curve: TransitionCurve
        )
        case route(RoutePath)
    }

    private struct VehicleTransition {
        let target: VehiclePosition
        let mode: TransitionMode
        let duration: TimeInterval
    }

    private struct PolylineProjection {
        let coordinate: CLLocationCoordinate2D
        let segmentIndex: Int
        let distanceToPolyline: CLLocationDistance
        let cumulativeDistance: CLLocationDistance
    }

    private struct ShapeCandidate {
        let points: [CLLocationCoordinate2D]
        let cumulativeDistances: [CLLocationDistance]
        let targetProjection: PolylineProjection
    }

    private var currentByID: [String: VehiclePosition] = [:]
    private var transitionsByID: [String: VehicleTransition] = [:]
    private var orderedIDs: [String] = []
    private var activeDuration: TimeInterval = 0
    private var activeToken: Int = 0

    func setInitial(_ vehicles: [VehiclePosition]) {
        let map = deduplicatedMap(vehicles)
        currentByID = map
        transitionsByID = map.mapValues { vehicle in
            VehicleTransition(target: vehicle, mode: .snap, duration: 0)
        }

        var nextOrder: [String] = []
        nextOrder.reserveCapacity(vehicles.count)
        var seen: Set<String> = []
        for vehicle in vehicles where seen.insert(vehicle.id).inserted {
            nextOrder.append(vehicle.id)
        }
        orderedIDs = nextOrder
        activeDuration = 0
        activeToken += 1
    }

    // Legacy API used by existing tests.
    func beginTransition(to target: [VehiclePosition], maxJumpMeters: CLLocationDistance) {
        _ = beginTransitionInternal(
            to: target,
            routeCandidatesByVehicleID: [:],
            routeAnimationDuration: 1.0,
            fallbackAnimationDuration: 1.0,
            fallbackCurve: .linear,
            maxJumpMeters: maxJumpMeters,
            offRouteThresholdMeters: 0,
            token: activeToken + 1
        )
    }

    // Legacy API used by existing tests.
    func frame(fraction: Double) -> [VehiclePosition] {
        let clamped = min(max(fraction, 0), 1)
        let elapsed = activeDuration * clamped
        return frameInternal(elapsed: elapsed, token: activeToken)
    }

    @discardableResult
    func beginTransition(
        to target: [VehiclePosition],
        routeCandidatesByVehicleID: [String: [[CLLocationCoordinate2D]]],
        routeAnimationDuration: TimeInterval,
        fallbackAnimationDuration: TimeInterval,
        maxJumpMeters: CLLocationDistance,
        offRouteThresholdMeters: CLLocationDistance,
        token: Int
    ) -> TimeInterval {
        beginTransitionInternal(
            to: target,
            routeCandidatesByVehicleID: routeCandidatesByVehicleID,
            routeAnimationDuration: routeAnimationDuration,
            fallbackAnimationDuration: fallbackAnimationDuration,
            fallbackCurve: .easeInOut,
            maxJumpMeters: maxJumpMeters,
            offRouteThresholdMeters: offRouteThresholdMeters,
            token: token
        )
    }

    private func beginTransitionInternal(
        to target: [VehiclePosition],
        routeCandidatesByVehicleID: [String: [[CLLocationCoordinate2D]]],
        routeAnimationDuration: TimeInterval,
        fallbackAnimationDuration: TimeInterval,
        fallbackCurve: TransitionCurve,
        maxJumpMeters: CLLocationDistance,
        offRouteThresholdMeters: CLLocationDistance,
        token: Int
    ) -> TimeInterval {
        let targetMap = deduplicatedMap(target)
        var nextTransitions: [String: VehicleTransition] = [:]
        nextTransitions.reserveCapacity(targetMap.count)

        var nextOrder: [String] = []
        nextOrder.reserveCapacity(targetMap.count)
        var seen: Set<String> = []
        for vehicle in target where seen.insert(vehicle.id).inserted {
            nextOrder.append(vehicle.id)
        }

        var nextMaxDuration: TimeInterval = 0
        for id in nextOrder {
            guard let targetVehicle = targetMap[id] else { continue }
            let startVehicle = currentByID[id]

            let transition = buildTransition(
                from: startVehicle,
                to: targetVehicle,
                routeCandidates: routeCandidatesByVehicleID[id] ?? [],
                routeAnimationDuration: routeAnimationDuration,
                fallbackAnimationDuration: fallbackAnimationDuration,
                fallbackCurve: fallbackCurve,
                maxJumpMeters: maxJumpMeters,
                offRouteThresholdMeters: offRouteThresholdMeters
            )
            nextTransitions[id] = transition
            nextMaxDuration = max(nextMaxDuration, transition.duration)

            if case .snap = transition.mode {
                currentByID[id] = transition.target
            }
        }

        transitionsByID = nextTransitions
        orderedIDs = nextOrder
        currentByID = currentByID.filter { targetMap[$0.key] != nil }
        activeDuration = nextMaxDuration
        activeToken = token
        return nextMaxDuration
    }

    func frame(elapsed: TimeInterval, token: Int) -> [VehiclePosition] {
        frameInternal(elapsed: elapsed, token: token)
    }

    private func frameInternal(elapsed: TimeInterval, token: Int) -> [VehiclePosition] {
        guard token == activeToken else {
            return orderedIDs.compactMap { currentByID[$0] }
        }

        let clampedElapsed = max(0, elapsed)
        var next: [String: VehiclePosition] = [:]
        next.reserveCapacity(transitionsByID.count)

        for id in orderedIDs {
            guard let transition = transitionsByID[id] else { continue }
            let vehicle: VehiclePosition

            switch transition.mode {
            case .snap:
                vehicle = transition.target
            case .straight(let from, let to, let bearing, let curve):
                let progress = normalizedProgress(elapsed: clampedElapsed, duration: transition.duration)
                let eased = applyCurve(progress, curve: curve)
                let coordinate = interpolateCoordinate(from: from, to: to, fraction: eased)
                vehicle = makeVehicle(from: transition.target, coord: coordinate, heading: bearing)
            case .route(let path):
                let progress = normalizedProgress(elapsed: clampedElapsed, duration: transition.duration)
                let distance = path.totalLength * progress
                let coordinate = coordinate(atDistance: distance, in: path)
                let heading = bearing(atDistance: distance, in: path) ?? transition.target.heading
                vehicle = makeVehicle(from: transition.target, coord: coordinate, heading: heading)
            }

            next[id] = vehicle
        }

        currentByID = next
        return orderedIDs.compactMap { next[$0] }
    }

    private func buildTransition(
        from start: VehiclePosition?,
        to target: VehiclePosition,
        routeCandidates: [[CLLocationCoordinate2D]],
        routeAnimationDuration: TimeInterval,
        fallbackAnimationDuration: TimeInterval,
        fallbackCurve: TransitionCurve,
        maxJumpMeters: CLLocationDistance,
        offRouteThresholdMeters: CLLocationDistance
    ) -> VehicleTransition {
        guard let start else {
            return VehicleTransition(target: target, mode: .snap, duration: 0)
        }

        if shouldSnap(from: start, to: target, maxJumpMeters: maxJumpMeters) {
            return VehicleTransition(target: target, mode: .snap, duration: 0)
        }

        if let routeTransition = buildRouteTransition(
            from: start,
            to: target,
            routeCandidates: routeCandidates,
            routeAnimationDuration: routeAnimationDuration,
            offRouteThresholdMeters: offRouteThresholdMeters
        ) {
            return routeTransition
        }

        return buildStraightTransition(
            from: start,
            to: target,
            duration: fallbackAnimationDuration,
            curve: fallbackCurve
        )
    }

    private func buildStraightTransition(
        from start: VehiclePosition,
        to target: VehiclePosition,
        duration: TimeInterval,
        curve: TransitionCurve
    ) -> VehicleTransition {
        let bearingValue = bearing(from: start.coord, to: target.coord) ?? target.heading
        return VehicleTransition(
            target: target,
            mode: .straight(from: start.coord, to: target.coord, bearing: bearingValue, curve: curve),
            duration: max(0, duration)
        )
    }

    private func buildRouteTransition(
        from start: VehiclePosition,
        to target: VehiclePosition,
        routeCandidates: [[CLLocationCoordinate2D]],
        routeAnimationDuration: TimeInterval,
        offRouteThresholdMeters: CLLocationDistance
    ) -> VehicleTransition? {
        guard routeAnimationDuration > 0 else { return nil }
        guard offRouteThresholdMeters > 0 else { return nil }

        var bestCandidate: ShapeCandidate?
        for shape in routeCandidates where shape.count >= 2 {
            let cumulative = cumulativeDistances(for: shape)
            guard let total = cumulative.last, total > 0 else { continue }
            guard let targetProjection = nearestProjection(
                of: target.coord,
                on: shape,
                cumulativeDistances: cumulative
            ) else { continue }

            if bestCandidate == nil || targetProjection.distanceToPolyline < bestCandidate!.targetProjection.distanceToPolyline {
                bestCandidate = ShapeCandidate(
                    points: shape,
                    cumulativeDistances: cumulative,
                    targetProjection: targetProjection
                )
            }
        }

        guard let bestCandidate else { return nil }
        guard bestCandidate.targetProjection.distanceToPolyline <= offRouteThresholdMeters else { return nil }

        guard let startProjection = nearestProjection(
            of: start.coord,
            on: bestCandidate.points,
            cumulativeDistances: bestCandidate.cumulativeDistances
        ) else { return nil }
        guard startProjection.distanceToPolyline <= offRouteThresholdMeters else { return nil }

        let pathPoints = deduplicateConsecutiveCoordinates(
            pathPointsBetween(
                in: bestCandidate.points,
                start: startProjection,
                end: bestCandidate.targetProjection
            )
        )
        guard pathPoints.count >= 2 else {
            let snappedTarget = makeVehicle(
                from: target,
                coord: bestCandidate.targetProjection.coordinate,
                heading: target.heading
            )
            return VehicleTransition(target: snappedTarget, mode: .snap, duration: 0)
        }

        let pathCumulative = cumulativeDistances(for: pathPoints)
        guard let pathTotal = pathCumulative.last, pathTotal > 0 else {
            let snappedTarget = makeVehicle(
                from: target,
                coord: bestCandidate.targetProjection.coordinate,
                heading: target.heading
            )
            return VehicleTransition(target: snappedTarget, mode: .snap, duration: 0)
        }

        let routePath = RoutePath(
            points: pathPoints,
            cumulativeDistances: pathCumulative,
            totalLength: pathTotal
        )
        let snappedTarget = makeVehicle(
            from: target,
            coord: bestCandidate.targetProjection.coordinate,
            heading: target.heading
        )

        return VehicleTransition(
            target: snappedTarget,
            mode: .route(routePath),
            duration: routeAnimationDuration
        )
    }

    private func pathPointsBetween(
        in shape: [CLLocationCoordinate2D],
        start: PolylineProjection,
        end: PolylineProjection
    ) -> [CLLocationCoordinate2D] {
        if start.segmentIndex == end.segmentIndex {
            return [start.coordinate, end.coordinate]
        }

        if start.cumulativeDistance <= end.cumulativeDistance {
            var points: [CLLocationCoordinate2D] = [start.coordinate]
            var index = start.segmentIndex + 1
            while index <= end.segmentIndex && index < shape.count {
                points.append(shape[index])
                index += 1
            }
            points.append(end.coordinate)
            return points
        }

        var points: [CLLocationCoordinate2D] = [start.coordinate]
        var index = start.segmentIndex
        while index > end.segmentIndex && index >= 0 {
            points.append(shape[index])
            index -= 1
        }
        points.append(end.coordinate)
        return points
    }

    private func nearestProjection(
        of coordinate: CLLocationCoordinate2D,
        on shape: [CLLocationCoordinate2D],
        cumulativeDistances: [CLLocationDistance]
    ) -> PolylineProjection? {
        guard shape.count >= 2,
              cumulativeDistances.count == shape.count else {
            return nil
        }

        var best: PolylineProjection?
        for index in 0..<(shape.count - 1) {
            let start = shape[index]
            let end = shape[index + 1]
            let segmentLength = cumulativeDistances[index + 1] - cumulativeDistances[index]
            guard segmentLength > 0 else { continue }

            let t = projectedFraction(of: coordinate, ontoSegmentFrom: start, to: end)
            let projectedCoordinate = interpolateCoordinate(from: start, to: end, fraction: t)
            let distance = planarDistanceMeters(from: coordinate, to: projectedCoordinate)
            let cumulative = cumulativeDistances[index] + (segmentLength * t)

            let projection = PolylineProjection(
                coordinate: projectedCoordinate,
                segmentIndex: index,
                distanceToPolyline: distance,
                cumulativeDistance: cumulative
            )

            if best == nil || distance < best!.distanceToPolyline {
                best = projection
            }
        }

        return best
    }

    private func projectedFraction(
        of point: CLLocationCoordinate2D,
        ontoSegmentFrom start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let latMeters = 111_132.92
        let referenceLatitude = (point.latitude + start.latitude + end.latitude) / 3
        let lonMeters = max(1.0, 111_412.84 * cos(referenceLatitude * .pi / 180))

        let sx = start.longitude * lonMeters
        let sy = start.latitude * latMeters
        let ex = end.longitude * lonMeters
        let ey = end.latitude * latMeters
        let px = point.longitude * lonMeters
        let py = point.latitude * latMeters

        let abx = ex - sx
        let aby = ey - sy
        let apx = px - sx
        let apy = py - sy
        let denominator = (abx * abx) + (aby * aby)
        guard denominator > 0 else { return 0 }

        let t = ((apx * abx) + (apy * aby)) / denominator
        return min(max(t, 0), 1)
    }

    private func cumulativeDistances(for points: [CLLocationCoordinate2D]) -> [CLLocationDistance] {
        guard !points.isEmpty else { return [] }

        var cumulative: [CLLocationDistance] = [0]
        cumulative.reserveCapacity(points.count)
        var running: CLLocationDistance = 0

        for index in 1..<points.count {
            let segment = planarDistanceMeters(from: points[index - 1], to: points[index])
            running += segment
            cumulative.append(running)
        }

        return cumulative
    }

    private func coordinate(atDistance distance: CLLocationDistance, in path: RoutePath) -> CLLocationCoordinate2D {
        let clampedDistance = min(max(distance, 0), path.totalLength)
        guard path.points.count >= 2,
              path.cumulativeDistances.count == path.points.count else {
            return path.points.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }

        if clampedDistance <= 0 {
            return path.points[0]
        }
        if clampedDistance >= path.totalLength {
            return path.points[path.points.count - 1]
        }

        var low = 1
        var high = path.cumulativeDistances.count - 1
        while low < high {
            let mid = (low + high) / 2
            if path.cumulativeDistances[mid] < clampedDistance {
                low = mid + 1
            } else {
                high = mid
            }
        }

        let upper = low
        let lower = max(upper - 1, 0)
        let startDistance = path.cumulativeDistances[lower]
        let endDistance = path.cumulativeDistances[upper]
        let segmentLength = max(0.000_001, endDistance - startDistance)
        let fraction = (clampedDistance - startDistance) / segmentLength
        return interpolateCoordinate(
            from: path.points[lower],
            to: path.points[upper],
            fraction: fraction
        )
    }

    private func bearing(atDistance distance: CLLocationDistance, in path: RoutePath) -> Double? {
        guard path.totalLength > 0 else { return nil }
        let window: CLLocationDistance = 3
        let fromDistance = max(0, distance - window)
        let toDistance = min(path.totalLength, distance + window)
        guard toDistance > fromDistance else { return nil }

        let from = coordinate(atDistance: fromDistance, in: path)
        let to = coordinate(atDistance: toDistance, in: path)
        return bearing(from: from, to: to)
    }

    private func normalizedProgress(elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        return min(max(elapsed / duration, 0), 1)
    }

    private func applyCurve(_ progress: Double, curve: TransitionCurve) -> Double {
        switch curve {
        case .linear:
            return progress
        case .easeInOut:
            return 0.5 - (0.5 * cos(.pi * progress))
        }
    }

    private func deduplicateConsecutiveCoordinates(_ points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard !points.isEmpty else { return [] }
        var deduplicated: [CLLocationCoordinate2D] = [points[0]]
        deduplicated.reserveCapacity(points.count)

        for point in points.dropFirst() {
            guard let last = deduplicated.last else {
                deduplicated.append(point)
                continue
            }
            if planarDistanceMeters(from: last, to: point) > 0.05 {
                deduplicated.append(point)
            }
        }
        return deduplicated
    }

    private func interpolateCoordinate(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        let clamped = min(max(fraction, 0), 1)
        let latitude = start.latitude + ((end.latitude - start.latitude) * clamped)
        let longitude = start.longitude + ((end.longitude - start.longitude) * clamped)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func makeVehicle(
        from base: VehiclePosition,
        coord: CLLocationCoordinate2D,
        heading: Double
    ) -> VehiclePosition {
        VehiclePosition(
            id: base.id,
            tripID: base.tripID,
            route: base.route,
            direction: base.direction,
            heading: heading,
            coord: coord,
            lastUpdatedAt: base.lastUpdatedAt
        )
    }

    private func deduplicatedMap(_ vehicles: [VehiclePosition]) -> [String: VehiclePosition] {
        var map: [String: VehiclePosition] = [:]
        map.reserveCapacity(vehicles.count)
        for vehicle in vehicles where map[vehicle.id] == nil {
            map[vehicle.id] = vehicle
        }
        return map
    }

    private func shouldSnap(
        from start: VehiclePosition,
        to target: VehiclePosition,
        maxJumpMeters: CLLocationDistance
    ) -> Bool {
        guard maxJumpMeters > 0 else { return false }
        return planarDistanceMeters(from: start.coord, to: target.coord) > maxJumpMeters
    }

    private func planarDistanceMeters(
        from lhs: CLLocationCoordinate2D,
        to rhs: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let latMeters = 111_132.92
        let avgLatitude = (lhs.latitude + rhs.latitude) * 0.5
        let lonMeters = max(1.0, 111_412.84 * cos(avgLatitude * .pi / 180))
        let dx = (rhs.longitude - lhs.longitude) * lonMeters
        let dy = (rhs.latitude - lhs.latitude) * latMeters
        return sqrt(dx * dx + dy * dy)
    }

    private func bearing(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double? {
        let distance = planarDistanceMeters(from: start, to: end)
        guard distance > 0.01 else { return nil }

        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180
        let dLon = lon2 - lon1

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        return radians * 180 / .pi
    }
}
