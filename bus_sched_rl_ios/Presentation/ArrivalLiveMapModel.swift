import Foundation
import MapKit
import CoreLocation

struct ArrivalLiveMapModel {
    let vehicle: RenderedVehiclePosition
    let stopName: String
    let stopCoordinate: CLLocationCoordinate2D
    let userLocation: CLLocationCoordinate2D?
    let region: MKCoordinateRegion
    let routeLine: MKPolyline
    let usesRouteShapePath: Bool

    init(
        vehicle: RenderedVehiclePosition,
        stopName: String,
        stopCoordinate: CLLocationCoordinate2D,
        userLocation: CLLocationCoordinate2D?,
        pathCoordinates: [CLLocationCoordinate2D]
    ) {
        self.vehicle = vehicle
        self.stopName = stopName
        self.stopCoordinate = stopCoordinate
        self.userLocation = userLocation

        let normalizedPath = Self.normalizedPath(
            providedPath: pathCoordinates,
            vehicleCoordinate: vehicle.coordinate,
            stopCoordinate: stopCoordinate
        )
        self.usesRouteShapePath = normalizedPath.count > 2
        self.routeLine = MKPolyline(coordinates: normalizedPath, count: normalizedPath.count)
        self.region = Self.region(userLocation: userLocation, pathCoordinates: normalizedPath)
    }

    private static func normalizedPath(
        providedPath: [CLLocationCoordinate2D],
        vehicleCoordinate: CLLocationCoordinate2D,
        stopCoordinate: CLLocationCoordinate2D
    ) -> [CLLocationCoordinate2D] {
        let candidatePath = providedPath.count >= 2 ? providedPath : [vehicleCoordinate, stopCoordinate]
        var result: [CLLocationCoordinate2D] = [vehicleCoordinate]

        for coordinate in candidatePath.dropFirst().dropLast() {
            if !sameCoordinate(coordinate, as: result.last) {
                result.append(coordinate)
            }
        }

        if !sameCoordinate(stopCoordinate, as: result.last) {
            result.append(stopCoordinate)
        }

        return result
    }

    private static func region(
        userLocation: CLLocationCoordinate2D?,
        pathCoordinates: [CLLocationCoordinate2D]
    ) -> MKCoordinateRegion {
        let coordinates = ([userLocation].compactMap { $0 }) + pathCoordinates
        let fallback = pathCoordinates.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        let minLatitude = latitudes.min() ?? fallback.latitude
        let maxLatitude = latitudes.max() ?? fallback.latitude
        let minLongitude = longitudes.min() ?? fallback.longitude
        let maxLongitude = longitudes.max() ?? fallback.longitude

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) * 0.5,
            longitude: (minLongitude + maxLongitude) * 0.5
        )

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLatitude - minLatitude) * 1.8, 0.01),
                longitudeDelta: max((maxLongitude - minLongitude) * 1.8, 0.01)
            )
        )
    }

    private static func sameCoordinate(_ lhs: CLLocationCoordinate2D, as rhs: CLLocationCoordinate2D?) -> Bool {
        guard let rhs else { return false }
        return abs(lhs.latitude - rhs.latitude) < 0.000001 &&
            abs(lhs.longitude - rhs.longitude) < 0.000001
    }
}
