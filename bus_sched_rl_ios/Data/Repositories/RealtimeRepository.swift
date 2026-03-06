import Foundation
import CoreLocation
import SwiftProtobuf

protocol RealtimeRepository {
    func fetchVehicles() async throws -> [VehiclePosition]
}

actor STMRealtimeRepository: RealtimeRepository {
    private let feedURL = URL(string: "https://api.stm.info/pub/od/gtfs-rt/ic/v2/vehiclePositions")!
    private let apiKey: String
    private let session: URLSession

    init(configuration: AppConfigurationProviding = BundleAppConfiguration(), session: URLSession = .shared) {
        self.apiKey = configuration.stmAPIKey
        self.session = session
    }

    func fetchVehicles() async throws -> [VehiclePosition] {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "RealtimeRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing STMApiKey in Info.plist"])
        }

        var request = URLRequest(url: feedURL)
        request.timeoutInterval = 7
        request.addValue(apiKey, forHTTPHeaderField: "apiKey")
        request.addValue("application/x-protobuf", forHTTPHeaderField: "Accept")

        let (data, _) = try await session.data(for: request)
        let feed = try TransitRealtime_FeedMessage(serializedData: data)

        return feed.entity.compactMap { entity in
            guard entity.hasVehicle else { return nil }
            let vehicle = entity.vehicle
            let pos = vehicle.position
            return VehiclePosition(
                id: vehicle.vehicle.id,
                route: vehicle.trip.routeID,
                direction: Int(vehicle.trip.directionID),
                heading: Double(pos.bearing ?? 0),
                coord: CLLocationCoordinate2D(
                    latitude: CLLocationDegrees(pos.latitude ?? 0),
                    longitude: CLLocationDegrees(pos.longitude ?? 0)
                )
            )
        }
    }
}
