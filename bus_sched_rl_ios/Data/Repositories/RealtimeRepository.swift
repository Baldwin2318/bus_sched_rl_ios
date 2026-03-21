import Foundation
import CoreLocation
import SwiftProtobuf

protocol RealtimeRepository {
    func fetchSnapshot() async throws -> RealtimeSnapshot
}

extension RealtimeRepository {
    func fetchVehicles() async throws -> [VehiclePosition] {
        try await fetchSnapshot().vehicles
    }
}

actor STMRealtimeRepository: RealtimeRepository {
    private let vehicleFeedURL = URL(string: "https://api.stm.info/pub/od/gtfs-rt/ic/v2/vehiclePositions")!
    private let tripUpdatesFeedURL = URL(string: "https://api.stm.info/pub/od/gtfs-rt/ic/v2/tripUpdates")!
    private let apiKey: String
    private let session: URLSession

    init(configuration: AppConfigurationProviding = BundleAppConfiguration(), session: URLSession = .shared) {
        self.apiKey = configuration.stmAPIKey
        self.session = session
    }

    func fetchSnapshot() async throws -> RealtimeSnapshot {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "RealtimeRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing STMApiKey in Info.plist"])
        }

        async let vehiclesTask = fetchVehiclesFeed(apiKey: apiKey)
        async let tripUpdatesTask = fetchTripUpdatesFeed(apiKey: apiKey)

        let vehicles = try await vehiclesTask
        let tripUpdates = (try? await tripUpdatesTask) ?? []
        return RealtimeSnapshot(vehicles: vehicles, tripUpdates: tripUpdates)
    }

    private func fetchVehiclesFeed(apiKey: String) async throws -> [VehiclePosition] {
        var request = URLRequest(url: vehicleFeedURL)
        request.timeoutInterval = 7
        request.addValue(apiKey, forHTTPHeaderField: "apiKey")
        request.addValue("application/x-protobuf", forHTTPHeaderField: "Accept")

        let (data, _) = try await session.data(for: request)
        let feed = try TransitRealtime_FeedMessage(serializedBytes: data)

        return feed.entity.compactMap { entity in
            guard entity.hasVehicle else { return nil }
            let vehicle = entity.vehicle
            let pos = vehicle.position
            let latitude = pos.latitude
            let longitude = pos.longitude
            guard !(latitude == 0 && longitude == 0) else { return nil }
            return VehiclePosition(
                id: vehicle.vehicle.id,
                tripID: normalized(vehicle.trip.tripID),
                route: normalized(vehicle.trip.routeID),
                direction: vehicle.trip.hasDirectionID ? Int(vehicle.trip.directionID) : nil,
                heading: Double(pos.bearing),
                coord: CLLocationCoordinate2D(
                    latitude: CLLocationDegrees(latitude),
                    longitude: CLLocationDegrees(longitude)
                )
            )
        }
    }

    private func fetchTripUpdatesFeed(apiKey: String) async throws -> [TripUpdatePayload] {
        var request = URLRequest(url: tripUpdatesFeedURL)
        request.timeoutInterval = 7
        request.addValue(apiKey, forHTTPHeaderField: "apiKey")
        request.addValue("application/x-protobuf", forHTTPHeaderField: "Accept")

        let (data, _) = try await session.data(for: request)
        let feed = try TransitRealtime_FeedMessage(serializedBytes: data)

        return feed.entity.compactMap { entity in
            guard entity.hasTripUpdate else { return nil }
            let tripUpdate = entity.tripUpdate
            guard tripUpdate.hasTrip,
                  let tripID = normalized(tripUpdate.trip.tripID) else { return nil }

            let stopUpdates = tripUpdate.stopTimeUpdate.compactMap { update -> TripStopTimeUpdate? in
                let arrival = update.hasArrival ? stopTimeEventDate(update.arrival) : nil
                let departure = update.hasDeparture ? stopTimeEventDate(update.departure) : nil
                let stopID = normalized(update.stopID)
                let stopSequence = update.hasStopSequence ? Int(update.stopSequence) : nil

                guard stopID != nil || stopSequence != nil || arrival != nil || departure != nil else { return nil }
                return TripStopTimeUpdate(
                    stopID: stopID,
                    stopSequence: stopSequence,
                    arrivalTime: arrival,
                    departureTime: departure
                )
            }

            return TripUpdatePayload(
                tripID: tripID,
                routeID: normalized(tripUpdate.trip.routeID),
                directionID: tripUpdate.trip.hasDirectionID ? Int(tripUpdate.trip.directionID) : nil,
                vehicleID: tripUpdate.hasVehicle ? normalized(tripUpdate.vehicle.id) : nil,
                timestamp: tripUpdate.hasTimestamp ? Date(timeIntervalSince1970: TimeInterval(tripUpdate.timestamp)) : nil,
                stopTimeUpdates: stopUpdates
            )
        }
    }

    private func stopTimeEventDate(_ event: TransitRealtime_TripUpdate.StopTimeEvent) -> Date? {
        guard event.hasTime else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(event.time))
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
