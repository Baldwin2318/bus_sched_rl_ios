import Foundation
import CoreLocation

actor VehicleInterpolationEngine {
    private var currentByID: [String: VehiclePosition] = [:]
    private var fromByID: [String: VehiclePosition] = [:]
    private var toByID: [String: VehiclePosition] = [:]
    private var orderedIDs: [String] = []

    func setInitial(_ vehicles: [VehiclePosition]) {
        let map = deduplicatedMap(vehicles)
        currentByID = map
        fromByID = map
        toByID = map
        var nextOrder: [String] = []
        nextOrder.reserveCapacity(vehicles.count)
        var seen: Set<String> = []
        for vehicle in vehicles where seen.insert(vehicle.id).inserted {
            nextOrder.append(vehicle.id)
        }
        orderedIDs = nextOrder
    }

    func beginTransition(to target: [VehiclePosition], maxJumpMeters: CLLocationDistance) {
        let targetMap = deduplicatedMap(target)
        var nextFromByID: [String: VehiclePosition] = [:]
        nextFromByID.reserveCapacity(targetMap.count)

        var nextOrder: [String] = []
        nextOrder.reserveCapacity(targetMap.count)
        var seen: Set<String> = []
        for vehicle in target {
            guard seen.insert(vehicle.id).inserted else { continue }
            nextOrder.append(vehicle.id)
        }

        for id in nextOrder {
            guard let targetVehicle = targetMap[id] else { continue }
            if let start = currentByID[id], !shouldSnap(from: start, to: targetVehicle, maxJumpMeters: maxJumpMeters) {
                nextFromByID[id] = start
            } else {
                // New vehicle or implausible jump: snap directly to fresh position.
                nextFromByID[id] = targetVehicle
                currentByID[id] = targetVehicle
            }
        }

        fromByID = nextFromByID
        toByID = targetMap
        orderedIDs = nextOrder

        // Remove stale vehicles eagerly so map density reflects current feed quickly.
        currentByID = currentByID.filter { targetMap[$0.key] != nil }
    }

    func frame(fraction: Double) -> [VehiclePosition] {
        let progress = min(max(fraction, 0), 1)

        var next: [String: VehiclePosition] = [:]
        next.reserveCapacity(toByID.count)

        for id in orderedIDs {
            guard let target = toByID[id] else { continue }
            if let start = fromByID[id] {
                next[id] = start.interpolated(to: target, fraction: progress)
            } else {
                next[id] = target
            }
        }

        currentByID = next
        return orderedIDs.compactMap { next[$0] }
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
}
