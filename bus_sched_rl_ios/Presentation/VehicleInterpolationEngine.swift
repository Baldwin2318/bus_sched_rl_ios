import Foundation

actor VehicleInterpolationEngine {
    private var currentByID: [String: VehiclePosition] = [:]
    private var fromByID: [String: VehiclePosition] = [:]
    private var toByID: [String: VehiclePosition] = [:]

    func setInitial(_ vehicles: [VehiclePosition]) {
        let map = Dictionary(uniqueKeysWithValues: vehicles.map { ($0.id, $0) })
        currentByID = map
        fromByID = map
        toByID = map
    }

    func beginTransition(to target: [VehiclePosition]) {
        let targetMap = Dictionary(uniqueKeysWithValues: target.map { ($0.id, $0) })
        fromByID = currentByID
        toByID = targetMap

        // Remove stale vehicles eagerly so map density reflects current feed quickly.
        currentByID = currentByID.filter { targetMap[$0.key] != nil }
    }

    func frame(fraction: Double) -> [VehiclePosition] {
        let progress = min(max(fraction, 0), 1)

        var next: [String: VehiclePosition] = [:]
        next.reserveCapacity(toByID.count)

        for (id, target) in toByID {
            if let start = fromByID[id] {
                next[id] = start.interpolated(to: target, fraction: progress)
            } else {
                next[id] = target
            }
        }

        currentByID = next
        return next.values.sorted { $0.id < $1.id }
    }
}
