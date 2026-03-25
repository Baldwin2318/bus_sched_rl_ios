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
    private let alertsFeedURL = URL(string: "https://api.stm.info/pub/od/gtfs-rt/ic/v2/serviceAlerts")!
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
        async let alertsTask = fetchAlertsFeed(apiKey: apiKey)

        let vehicles = try await vehiclesTask
        let tripUpdateResult = try? await tripUpdatesTask
        let tripUpdates = tripUpdateResult?.updates ?? []
        let embeddedAlerts = tripUpdateResult?.alerts ?? []
        let tripUpdateShapes = tripUpdateResult?.shapePointsByShapeID ?? [:]
        let serviceAlerts = (try? await alertsTask) ?? []
        let alerts = dedupeAlerts(embeddedAlerts + serviceAlerts)

        return RealtimeSnapshot(
            vehicles: vehicles,
            tripUpdates: tripUpdates,
            alerts: alerts,
            shapePointsByShapeID: tripUpdateShapes
        )
    }

    private func fetchVehiclesFeed(apiKey: String) async throws -> [VehiclePosition] {
        var request = URLRequest(url: vehicleFeedURL)
        request.timeoutInterval = 7
        request.addValue(apiKey, forHTTPHeaderField: "apiKey")
        request.addValue("application/x-protobuf", forHTTPHeaderField: "Accept")

        let (data, _) = try await session.data(for: request)
        let feed = try TransitRealtime_FeedMessage(serializedBytes: data)
        let feedTimestamp: Date? = feed.header.hasTimestamp
            ? Date(timeIntervalSince1970: TimeInterval(feed.header.timestamp))
            : nil

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
                stopID: normalized(vehicle.hasStopID ? vehicle.stopID : nil),
                currentStatus: vehicle.hasCurrentStatus ? parseVehicleStopStatus(vehicle.currentStatus) : nil,
                congestionLevel: vehicle.hasCongestionLevel ? parseCongestionLevel(vehicle.congestionLevel) : nil,
                occupancyStatus: vehicle.hasOccupancyStatus ? parseOccupancyStatus(vehicle.occupancyStatus) : nil,
                occupancyPercentage: vehicle.hasOccupancyPercentage ? Int(vehicle.occupancyPercentage) : nil,
                heading: Double(pos.bearing),
                coord: CLLocationCoordinate2D(
                    latitude: CLLocationDegrees(latitude),
                    longitude: CLLocationDegrees(longitude)
                ),
                lastUpdatedAt: vehicle.hasTimestamp
                    ? Date(timeIntervalSince1970: TimeInterval(vehicle.timestamp))
                    : feedTimestamp
            )
        }
    }

    private func fetchTripUpdatesFeed(apiKey: String) async throws -> (
        updates: [TripUpdatePayload],
        alerts: [ServiceAlert],
        shapePointsByShapeID: [String: [CLLocationCoordinate2D]]
    ) {
        let feed = try await fetchFeed(url: tripUpdatesFeedURL, apiKey: apiKey)

        let updates = feed.entity.compactMap { entity -> TripUpdatePayload? in
            guard entity.hasTripUpdate else { return nil }
            let tripUpdate = entity.tripUpdate
            guard tripUpdate.hasTrip,
                  let tripID = normalized(tripUpdate.trip.tripID) else { return nil }

            let stopUpdates = tripUpdate.stopTimeUpdate.compactMap { update -> TripStopTimeUpdate? in
                let arrival = update.hasArrival ? stopTimeEventDate(update.arrival) : nil
                let departure = update.hasDeparture ? stopTimeEventDate(update.departure) : nil
                let stopID = normalized(update.stopID)
                let stopSequence = update.hasStopSequence ? Int(update.stopSequence) : nil
                let assignedStopID = update.hasStopTimeProperties
                    ? normalized(update.stopTimeProperties.hasAssignedStopID ? update.stopTimeProperties.assignedStopID : nil)
                    : nil
                let eventDelay = stopTimeEventDelay(update.hasArrival ? update.arrival : nil)
                    ?? stopTimeEventDelay(update.hasDeparture ? update.departure : nil)

                guard stopID != nil || stopSequence != nil || arrival != nil || departure != nil || assignedStopID != nil else { return nil }
                return TripStopTimeUpdate(
                    stopID: stopID,
                    stopSequence: stopSequence,
                    arrivalTime: arrival,
                    departureTime: departure,
                    assignedStopID: assignedStopID,
                    delaySeconds: eventDelay
                )
            }

            return TripUpdatePayload(
                tripID: tripID,
                routeID: normalized(tripUpdate.trip.routeID),
                directionID: tripUpdate.trip.hasDirectionID ? Int(tripUpdate.trip.directionID) : nil,
                vehicleID: tripUpdate.hasVehicle ? normalized(tripUpdate.vehicle.id) : nil,
                timestamp: tripUpdate.hasTimestamp ? Date(timeIntervalSince1970: TimeInterval(tripUpdate.timestamp)) : nil,
                shapeIDOverride: tripUpdate.hasTripProperties && tripUpdate.tripProperties.hasShapeID
                    ? normalized(tripUpdate.tripProperties.shapeID)
                    : nil,
                delaySeconds: tripUpdate.hasDelay ? Int(tripUpdate.delay) : nil,
                stopTimeUpdates: stopUpdates
            )
        }

        return (
            updates: updates,
            alerts: GTFSRealtimeAlertParser.parseAlerts(from: feed),
            shapePointsByShapeID: GTFSRealtimeShapeParser.parseShapes(from: feed)
        )
    }

    private func fetchAlertsFeed(apiKey: String) async throws -> [ServiceAlert] {
        let feed = try await fetchFeed(url: alertsFeedURL, apiKey: apiKey)
        return GTFSRealtimeAlertParser.parseAlerts(from: feed)
    }

    private func fetchFeed(url: URL, apiKey: String) async throws -> TransitRealtime_FeedMessage {
        var request = URLRequest(url: url)
        request.timeoutInterval = 7
        request.addValue(apiKey, forHTTPHeaderField: "apiKey")
        request.addValue("application/x-protobuf", forHTTPHeaderField: "Accept")

        let (data, _) = try await session.data(for: request)
        return try TransitRealtime_FeedMessage(serializedBytes: data)
    }

    private func dedupeAlerts(_ alerts: [ServiceAlert]) -> [ServiceAlert] {
        var seen: Set<String> = []
        return alerts.filter { seen.insert($0.id).inserted }
    }

    private func stopTimeEventDate(_ event: TransitRealtime_TripUpdate.StopTimeEvent) -> Date? {
        guard event.hasTime else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(event.time))
    }

    private func stopTimeEventDelay(_ event: TransitRealtime_TripUpdate.StopTimeEvent?) -> Int? {
        guard let event, event.hasDelay else { return nil }
        return Int(event.delay)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseVehicleStopStatus(
        _ status: TransitRealtime_VehiclePosition.VehicleStopStatus
    ) -> VehicleStopStatus {
        switch status {
        case .incomingAt:
            return .incomingAt
        case .stoppedAt:
            return .stoppedAt
        case .inTransitTo:
            return .inTransitTo
        }
    }

    private func parseCongestionLevel(
        _ level: TransitRealtime_VehiclePosition.CongestionLevel
    ) -> VehicleCongestionLevel? {
        switch level {
        case .runningSmoothly:
            return .runningSmoothly
        case .stopAndGo:
            return .stopAndGo
        case .congestion:
            return .congestion
        case .severeCongestion:
            return .severeCongestion
        case .unknownCongestionLevel:
            return nil
        }
    }

    private func parseOccupancyStatus(
        _ status: TransitRealtime_VehiclePosition.OccupancyStatus
    ) -> VehicleOccupancyStatus? {
        switch status {
        case .empty:
            return .empty
        case .manySeatsAvailable:
            return .manySeatsAvailable
        case .fewSeatsAvailable:
            return .fewSeatsAvailable
        case .standingRoomOnly:
            return .standingRoomOnly
        case .crushedStandingRoomOnly:
            return .crushedStandingRoomOnly
        case .full:
            return .full
        case .notAcceptingPassengers:
            return .notAcceptingPassengers
        case .noDataAvailable:
            return .noDataAvailable
        case .notBoardable:
            return .notBoardable
        }
    }
}

struct GTFSRealtimeShapeParser {
    static func parseShapes(from feed: TransitRealtime_FeedMessage) -> [String: [CLLocationCoordinate2D]] {
        feed.entity.reduce(into: [:]) { partialResult, entity in
            guard entity.hasShape else { return }
            let shape = entity.shape
            guard shape.hasShapeID, shape.hasEncodedPolyline else { return }
            let shapeID = shape.shapeID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !shapeID.isEmpty else { return }
            let coordinates = TransitMath.decodeEncodedPolyline(shape.encodedPolyline)
            guard coordinates.count >= 2 else { return }
            partialResult[shapeID] = coordinates
        }
    }
}

struct GTFSRealtimeAlertParser {
    static func parseAlerts(from feed: TransitRealtime_FeedMessage, referenceDate: Date = Date()) -> [ServiceAlert] {
        feed.entity.compactMap { entity in
            guard entity.hasAlert else { return nil }
            let alert = entity.alert
            let scopes = alert.informedEntity.map(parseScope)
            let title = translatedText(alert.headerText)
                ?? translatedText(alert.effectDetail)
                ?? translatedText(alert.causeDetail)
                ?? effectSummary(alert.effect)
                ?? "Service alert"
            let message = translatedText(alert.descriptionText)
                ?? translatedText(alert.effectDetail)
                ?? translatedText(alert.causeDetail)
            let activePeriods = alert.activePeriod.compactMap(parseDateInterval)

            let serviceAlert = ServiceAlert(
                id: normalized(entity.id) ?? derivedID(title: title, scopes: scopes, activePeriods: activePeriods),
                title: title,
                message: message,
                severity: severity(alert.severityLevel, effect: alert.effect),
                causeText: causeSummary(alert.cause, detail: translatedText(alert.causeDetail)),
                effectText: effectSummary(alert.effect, detail: translatedText(alert.effectDetail)),
                url: translatedURL(alert.url),
                activePeriods: activePeriods,
                scopes: scopes
            )

            return serviceAlert.isActive(at: referenceDate) ? serviceAlert : nil
        }
    }

    private static func parseScope(_ selector: TransitRealtime_EntitySelector) -> AlertScopeSelector {
        AlertScopeSelector(
            routeID: normalized(selector.hasRouteID ? selector.routeID : nil),
            directionID: selector.hasDirectionID ? String(selector.directionID) : nil,
            stopID: normalized(selector.hasStopID ? selector.stopID : nil),
            tripID: selector.hasTrip ? normalized(selector.trip.tripID) : nil
        )
    }

    private static func parseDateInterval(_ timeRange: TransitRealtime_TimeRange) -> DateInterval? {
        let start = timeRange.hasStart ? Date(timeIntervalSince1970: TimeInterval(timeRange.start)) : .distantPast
        let end = timeRange.hasEnd ? Date(timeIntervalSince1970: TimeInterval(timeRange.end)) : .distantFuture
        guard start <= end else { return nil }
        return DateInterval(start: start, end: end)
    }

    private static func translatedText(_ translatedString: TransitRealtime_TranslatedString) -> String? {
        translatedString.translation.lazy
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func translatedURL(_ translatedString: TransitRealtime_TranslatedString) -> URL? {
        guard let rawValue = translatedText(translatedString) else { return nil }
        return URL(string: rawValue)
    }

    private static func severity(
        _ protobufSeverity: TransitRealtime_Alert.SeverityLevel,
        effect: TransitRealtime_Alert.Effect
    ) -> AlertSeverity {
        switch protobufSeverity {
        case .info, .unknownSeverity:
            switch effect {
            case .stopMoved, .detour, .modifiedService, .reducedService, .significantDelays, .accessibilityIssue:
                return .warning
            case .noService:
                return .severe
            default:
                return .info
            }
        case .warning:
            return .warning
        case .severe:
            return .severe
        }
    }

    private static func causeSummary(
        _ cause: TransitRealtime_Alert.Cause,
        detail: String?
    ) -> String? {
        if let detail, !detail.isEmpty {
            return detail
        }

        switch cause {
        case .technicalProblem:
            return "Technical problem"
        case .strike:
            return "Strike"
        case .demonstration:
            return "Demonstration"
        case .accident:
            return "Accident"
        case .holiday:
            return "Holiday"
        case .weather:
            return "Weather"
        case .maintenance:
            return "Maintenance"
        case .construction:
            return "Construction"
        case .policeActivity:
            return "Police activity"
        case .medicalEmergency:
            return "Medical emergency"
        case .otherCause:
            return "Other cause"
        case .unknownCause:
            return nil
        }
    }

    private static func effectSummary(
        _ effect: TransitRealtime_Alert.Effect,
        detail: String? = nil
    ) -> String? {
        if let detail, !detail.isEmpty {
            return detail
        }

        switch effect {
        case .detour:
            return "Detour"
        case .significantDelays:
            return "Significant delays"
        case .modifiedService:
            return "Modified service"
        case .reducedService:
            return "Reduced service"
        case .additionalService:
            return "Additional service"
        case .noService:
            return "No service"
        case .stopMoved:
            return "Stop moved"
        case .accessibilityIssue:
            return "Accessibility issue"
        default:
            return nil
        }
    }

    private static func derivedID(
        title: String,
        scopes: [AlertScopeSelector],
        activePeriods: [DateInterval]
    ) -> String {
        let scopeKey = scopes.map {
            [
                $0.routeID ?? "",
                $0.directionID ?? "",
                $0.stopID ?? "",
                $0.tripID ?? "",
            ].joined(separator: "|")
        }.joined(separator: ",")
        let activeKey = activePeriods.map {
            "\($0.start.timeIntervalSince1970)-\($0.end.timeIntervalSince1970)"
        }.joined(separator: ",")
        return "\(title)#\(scopeKey)#\(activeKey)"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
