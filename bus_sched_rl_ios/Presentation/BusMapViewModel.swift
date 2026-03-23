import Foundation
import CoreLocation
import SwiftUI

struct BusSuggestion: Identifiable, Hashable {
    let id: String
    let route: String
    let displayDirection: String
    let directionID: String?
    let metersAway: Int?
    let etaMinutes: Int?
    let estimatedArrivalAt: Date?
    let source: StopTimeSourceLabel
    let nearestStopName: String?

    var title: String {
        "\(route) \(displayDirection)"
    }

    var subtitle: String {
        var chunks: [String] = []
        if let etaMinutes {
            chunks.append("ETA \(etaMinutes) min")
        }
        if let nearestStopName, !nearestStopName.isEmpty {
            chunks.append("Stop: \(nearestStopName)")
        }
        return chunks.joined(separator: " • ")
    }
}

enum GTFSStalenessLevel: Equatable {
    case fresh
    case warning
    case expired

    var label: String {
        switch self {
        case .fresh:
            return "Fresh"
        case .warning:
            return "Aging"
        case .expired:
            return "Expired"
        }
    }
}

enum VehicleFreshnessLevel: Equatable {
    case live
    case aging
    case stale
}

enum StopTimeSourceLabel: String, Equatable {
    case live = "Live"
    case scheduled = "Scheduled"
}

struct BusDetailStopRow: Identifiable, Hashable {
    let id: String
    let stopName: String
    let arrivalText: String?
    let departureText: String?
    let source: StopTimeSourceLabel
}

struct BusDetailPresentation: Identifiable, Hashable {
    let id: String
    let route: String
    let directionText: String
    let source: StopTimeSourceLabel
    let rows: [BusDetailStopRow]
}

struct MapStopPresentation: Identifiable, Hashable {
    let id: String
    let name: String
    let coord: CLLocationCoordinate2D

    static func == (lhs: MapStopPresentation, rhs: MapStopPresentation) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.coord.latitude == rhs.coord.latitude &&
        lhs.coord.longitude == rhs.coord.longitude
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(coord.latitude)
        hasher.combine(coord.longitude)
    }
}

struct StopArrivalPresentation: Identifiable, Hashable {
    let id: String
    let route: String
    let directionID: String
    let directionText: String
    let arrivalText: String?
    let source: StopTimeSourceLabel
}

struct StopArrivalsPresentation: Identifiable, Hashable {
    let id: String
    let stopName: String
    let arrivals: [StopArrivalPresentation]
}

struct NextBusGlance: Equatable {
    let route: String
    let directionText: String
    let etaMinutes: Int?
    let nearestStopName: String?
    let metersAway: Int?
}

enum SearchSelectionMapResponse {
    case route(
        shape: [CLLocationCoordinate2D],
        detail: BusDetailPresentation?
    )
    case stop(
        coordinate: CLLocationCoordinate2D,
        arrivals: StopArrivalsPresentation?
    )
}

enum LiveRefreshTrigger {
    case initialLoad
    case polling
    case manual
}

struct InterpolationConfig {
    let durationRatio: Double
    let manualDuration: Duration
    let frameInterval: Duration
    let maxJumpMeters: CLLocationDistance

    static let `default` = InterpolationConfig(
        durationRatio: 0.85,
        manualDuration: .seconds(1.6),
        frameInterval: .milliseconds(100),
        maxJumpMeters: 1200
    )

    func duration(forPollInterval pollInterval: Duration, trigger: LiveRefreshTrigger) -> Duration {
        switch trigger {
        case .manual:
            return manualDuration
        case .initialLoad, .polling:
            let seconds = max(0.2, pollIntervalTimeInterval(pollInterval) * durationRatio)
            return .seconds(seconds)
        }
    }

    private func pollIntervalTimeInterval(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + (Double(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}

@MainActor
final class BusMapViewModel: ObservableObject {
    @Published private(set) var vehicles: [VehiclePosition] = []
    @Published private(set) var displayedVehicles: [VehiclePosition] = []
    @Published private(set) var nearbyScheduleSuggestions: [BusSuggestion] = []
    @Published private(set) var selectedRouteShape: [CLLocationCoordinate2D] = []
    @Published private(set) var selectedBusID: String?
    @Published private(set) var selectedBusDetail: BusDetailPresentation?
    @Published private(set) var selectedRouteID: String?
    @Published private(set) var selectedRouteDirectionID: String?
    @Published private(set) var availableRoutes: [String] = []
    @Published private(set) var phase: BusMapPhase = .idle
    @Published private(set) var isRefreshing = false
    @Published private(set) var busLayerOpacity = 1.0
    @Published private(set) var lastTraceSource: String = "none"
    @Published private(set) var isLiveUpdatesPaused = false
    @Published private(set) var lastVehicleRefreshAt: Date?
    @Published private(set) var liveFeedStatusMessage: String?
    @Published private(set) var searchIndex: SearchIndex?

    @Published private(set) var gtfsCacheMetadata: GTFSCacheMetadata = .empty
    @Published private(set) var isRefreshingStaticData = false
    @Published private(set) var staticDataRefreshStatus = ""

    private let gtfsRepository: GTFSRepository
    private let realtimeRepository: RealtimeRepository
    private let suggestionEngine = SearchSuggestionEngine()
    private let routeIndex = NearbyRouteIndex()
    private let traceResolver = RouteTraceResolver()
    private let interpolationEngine = VehicleInterpolationEngine()
    private let interpolationConfig: InterpolationConfig

    private var routeShapes: [String: [String: [CLLocationCoordinate2D]]] = [:]
    private var routeStops: [RouteKey: [BusStop]] = [:]
    private var routeStopSchedules: [RouteKey: [RouteStopSchedule]] = [:]
    private var shapeCoordinatesByID: [String: [CLLocationCoordinate2D]] = [:]
    private var routeShapeIDsByKey: [RouteKey: [String]] = [:]
    private var routeDirectionLabels: [RouteKey: String] = [:]
    private var routeStylesByRouteID: [String: GTFSRouteStyle] = [:]
    private var allStopsByID: [String: BusStop] = [:]
    private var routeKeysByStopID: [String: Set<RouteKey>] = [:]
    private var tripUpdatesByTripID: [String: TripUpdatePayload] = [:]
    private var userLocation: CLLocationCoordinate2D?
    private var hasLoadedStaticData = false
    private var isSceneActive = true
    private var livePollingTask: Task<Void, Never>?
    private var interpolationTask: Task<Void, Never>?
    private var staticRefreshTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    private var searchIndexBuildTask: Task<Void, Never>?
    private var suggestionToken = 0
    private var interpolationToken = 0
    private var interpolatedVehicles: [VehiclePosition] = []
    private var displayedVehicleIDs: Set<String>?

    private let nearbyVehicleDistance: CLLocationDistance = 2500
    private let nearbyRouteDistance: CLLocationDistance = 600
    private let liveFreshnessThreshold: TimeInterval = 35
    private let agingFreshnessThreshold: TimeInterval = 90
    private let routeSnapThresholdMeters: CLLocationDistance = 50
    private let noRouteFallbackAnimationDuration: TimeInterval = 0.5
    private let livePollInterval: Duration

    var statusMessage: String {
        switch phase {
        case .idle:
            return ""
        case .loading(let message):
            return message
        case .ready:
            if let liveFeedStatusMessage {
                return liveFeedStatusMessage
            }
            return isRefreshing ? "Refreshing live buses..." : "Ready"
        case .error(let message):
            return message
        }
    }

    var liveRefreshIntervalSeconds: Int {
        max(1, Int(round(durationToTimeInterval(livePollInterval))))
    }

    var nextBusGlance: NextBusGlance? {
        guard !nearbyScheduleSuggestions.isEmpty else { return nil }
        let withEta = nearbyScheduleSuggestions.filter { $0.etaMinutes != nil }
        let primarySuggestion: BusSuggestion
        if let nearestETA = withEta.min(by: { lhs, rhs in
            (lhs.etaMinutes ?? Int.max) < (rhs.etaMinutes ?? Int.max)
        }) {
            primarySuggestion = nearestETA
        } else if let closest = nearbyScheduleSuggestions.min(by: { lhs, rhs in
            (lhs.metersAway ?? Int.max) < (rhs.metersAway ?? Int.max)
        }) {
            primarySuggestion = closest
        } else {
            primarySuggestion = nearbyScheduleSuggestions[0]
        }

        return NextBusGlance(
            route: primarySuggestion.route,
            directionText: primarySuggestion.displayDirection,
            etaMinutes: primarySuggestion.etaMinutes,
            nearestStopName: primarySuggestion.nearestStopName,
            metersAway: primarySuggestion.metersAway
        )
    }

    init(
        gtfsRepository: GTFSRepository = LiveGTFSRepository(),
        realtimeRepository: RealtimeRepository = STMRealtimeRepository(),
        livePollInterval: Duration = .seconds(30),
        interpolationConfig: InterpolationConfig = .default
    ) {
        self.gtfsRepository = gtfsRepository
        self.realtimeRepository = realtimeRepository
        self.livePollInterval = livePollInterval
        self.interpolationConfig = interpolationConfig
    }

    deinit {
        livePollingTask?.cancel()
        interpolationTask?.cancel()
        staticRefreshTask?.cancel()
        suggestionTask?.cancel()
        searchIndexBuildTask?.cancel()
    }

    func loadIfNeeded() {
        guard !hasLoadedStaticData else { return }
        phase = .loading("Loading route data...")

        Task {
            await refreshCacheMetadata()
            do {
                let staticData = try await gtfsRepository.loadStaticData()
                await applyStaticData(staticData)
                await refreshCacheMetadata()
                phase = .ready
                recomputeDisplayedVehicles()
                scheduleSuggestionRefresh()
                startLivePollingIfNeeded()
                refreshLiveBuses(trigger: .initialLoad)
            } catch {
                phase = .error("Failed to load routes: \(error.localizedDescription)")
            }
        }
    }

    func setScenePhase(_ phase: ScenePhase) {
        isSceneActive = phase == .active
        if isSceneActive {
            startLivePollingIfNeeded()
        } else {
            stopLivePolling()
            stopInterpolation()
        }
    }

    func toggleLiveUpdatesPaused() {
        isLiveUpdatesPaused.toggle()
        if isLiveUpdatesPaused {
            stopLivePolling()
            stopInterpolation()
        } else {
            startLivePollingIfNeeded()
            refreshLiveBuses(trigger: .manual)
        }
    }

    func updateUserLocation(_ location: CLLocationCoordinate2D) {
        userLocation = location
        recomputeDisplayedVehicles()
        scheduleSuggestionRefresh()
    }

    func refreshLiveBuses() {
        refreshLiveBuses(trigger: .manual)
    }

    func refreshLiveBuses(trigger: LiveRefreshTrigger) {
        Task {
            await performSingleRefreshIfNeeded(trigger: trigger)
        }
    }

    func refreshStaticDataNow() {
        guard staticRefreshTask == nil else { return }
        staticRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.performStaticRefreshNow()
            await MainActor.run {
                self.staticRefreshTask = nil
            }
        }
    }

    func selectBus(_ bus: VehiclePosition) {
        selectedBusID = bus.id
        selectedRouteID = bus.route
        if bus.route != nil {
            selectedRouteDirectionID = bus.direction.map(String.init) ?? "0"
        } else {
            selectedRouteDirectionID = nil
        }
        let result = traceResolver.resolveTrace(
            bus: bus,
            routeShapes: routeShapes,
            routeShapeIDsByKey: routeShapeIDsByKey,
            shapeCoordinatesByID: shapeCoordinatesByID
        )
        selectedRouteShape = result.trace
        lastTraceSource = result.source
        selectedBusDetail = buildBusDetail(for: bus)
    }

    func dismissBusDetail() {
        selectedBusDetail = nil
        selectedBusID = nil
    }

    func applySuggestion(_ suggestion: BusSuggestion) {
        selectedBusID = nil
        selectedBusDetail = nil
        selectedRouteID = suggestion.route
        selectedRouteDirectionID = suggestion.directionID
        if let direction = suggestion.directionID {
            selectedRouteShape = routeShapes[suggestion.route]?[direction] ?? []
        } else {
            selectedRouteShape = []
        }
    }

    func restoreRouteSelection(routeID: String, directionID: String?) {
        let normalizedRouteID = routeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRouteID.isEmpty else { return }

        selectedBusID = nil
        selectedBusDetail = nil
        selectedRouteID = normalizedRouteID

        let preferredDirection = directionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDirection: String?
        if let preferredDirection,
           !preferredDirection.isEmpty,
           routeShapes[normalizedRouteID]?[preferredDirection] != nil {
            resolvedDirection = preferredDirection
        } else {
            resolvedDirection = routeShapes[normalizedRouteID]?.keys.sorted().first
        }

        selectedRouteDirectionID = resolvedDirection
        if let resolvedDirection {
            selectedRouteShape = routeShapes[normalizedRouteID]?[resolvedDirection] ?? []
        } else {
            selectedRouteShape = []
        }
    }

    func visibleStops(
        around center: CLLocationCoordinate2D?,
        maxDistanceMeters: CLLocationDistance,
        maxCount: Int
    ) -> [MapStopPresentation] {
        guard maxCount > 0 else { return [] }
        guard let center else {
            return allStopsByID.values
                .prefix(maxCount)
                .map { stop in
                    MapStopPresentation(id: stop.id, name: stop.name, coord: stop.coord)
                }
        }

        let centerPoint = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let candidateStops = allStopsByID.values.compactMap { stop -> (stop: BusStop, distance: CLLocationDistance)? in
            let stopPoint = CLLocation(latitude: stop.coord.latitude, longitude: stop.coord.longitude)
            let distance = centerPoint.distance(from: stopPoint)
            if distance <= maxDistanceMeters {
                return (stop, distance)
            }
            return nil
        }
        .sorted { $0.distance < $1.distance }
        .prefix(maxCount)

        return candidateStops.map { candidate in
            MapStopPresentation(
                id: candidate.stop.id,
                name: candidate.stop.name,
                coord: candidate.stop.coord
            )
        }
    }

    func stopArrivals(for stopID: String) -> StopArrivalsPresentation? {
        guard let stop = allStopsByID[stopID] else { return nil }
        let routeKeys = Array(routeKeysByStopID[stopID] ?? []).sorted { lhs, rhs in
            if lhs.route != rhs.route {
                return lhs.route.localizedStandardCompare(rhs.route) == .orderedAscending
            }
            return lhs.direction.localizedStandardCompare(rhs.direction) == .orderedAscending
        }
        guard !routeKeys.isEmpty else { return nil }

        let now = Date()
        var rows: [(date: Date, row: StopArrivalPresentation)] = []
        for key in routeKeys {
            let routeSchedules = routeStopSchedules[key] ?? []
            let routeDirection = routeDirectionLabels[key] ?? "Direction \(key.direction)"
            let scheduleForStop = routeSchedules.first(where: { $0.stop.id == stopID })
            let liveDate = liveArrivalDate(for: stopID, routeKey: key, now: now)
            let scheduledDate = scheduledTimeDate(scheduleForStop?.scheduledArrival ?? scheduleForStop?.scheduledDeparture)

            let source: StopTimeSourceLabel
            let displayDate: Date?
            if let liveDate {
                source = .live
                displayDate = liveDate
            } else {
                source = .scheduled
                displayDate = scheduledDate
            }

            let row = StopArrivalPresentation(
                id: "\(key.route)-\(key.direction)-\(stopID)",
                route: key.route,
                directionID: key.direction,
                directionText: routeDirection,
                arrivalText: formatStopArrival(displayDate, fallbackRaw: scheduleForStop?.scheduledArrival ?? scheduleForStop?.scheduledDeparture),
                source: source
            )

            rows.append((displayDate ?? .distantFuture, row))
        }

        let orderedRows = rows.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            if lhs.row.route != rhs.row.route {
                return lhs.row.route.localizedStandardCompare(rhs.row.route) == .orderedAscending
            }
            return lhs.row.directionID.localizedStandardCompare(rhs.row.directionID) == .orderedAscending
        }
        .map(\.row)

        return StopArrivalsPresentation(
            id: stop.id,
            stopName: stop.name,
            arrivals: orderedRows
        )
    }

    func routeDetail(route: String, directionID: String) -> BusDetailPresentation? {
        let key = RouteKey(route: route, direction: directionID)
        guard let schedules = routeStopSchedules[key], !schedules.isEmpty else { return nil }
        let directionText = routeDirectionLabels[key] ?? "Direction \(directionID)"
        let rows = schedules.map { schedule in
            BusDetailStopRow(
                id: "route-\(schedule.stop.id)-\(schedule.sequence)",
                stopName: schedule.stop.name,
                arrivalText: formatScheduledTime(schedule.scheduledArrival),
                departureText: formatScheduledTime(schedule.scheduledDeparture),
                source: .scheduled
            )
        }

        return BusDetailPresentation(
            id: "route-\(route)-\(directionID)",
            route: route,
            directionText: directionText,
            source: .scheduled,
            rows: Array(rows.prefix(24))
        )
    }

    func directionText(for vehicle: VehiclePosition) -> String {
        guard let route = vehicle.route else { return frenchCardinal(for: vehicle.heading) }
        let key = RouteKey(route: route, direction: vehicle.direction.map(String.init) ?? "0")
        return routeDirectionLabels[key] ?? frenchCardinal(for: vehicle.heading)
    }

    func routeStyle(for routeID: String?) -> GTFSRouteStyle? {
        guard let routeID else { return nil }
        return routeStylesByRouteID[routeID]
    }

    func refreshSuggestionsForCurrentState() {
        scheduleSuggestionRefresh()
    }

    func applySearchSelection(_ result: SearchResult) -> SearchSelectionMapResponse? {
        switch result {
        case .route(let routeMatch):
            return applyRouteSearchSelection(
                routeID: routeMatch.route.routeId,
                preferredDirectionID: routeMatch.directionId
            )
        case .stop(let stopMatch):
            return applyStopSearchSelection(stopMatch)
        }
    }

    func gtfsStalenessLevel(referenceDate: Date = Date()) -> GTFSStalenessLevel {
        if let feedEndDate = gtfsCacheMetadata.feedInfo?.feedEndDate {
            if referenceDate > feedEndDate {
                return .expired
            }
            let warningWindowStart = Calendar.current.date(byAdding: .day, value: -7, to: feedEndDate) ?? feedEndDate
            if referenceDate >= warningWindowStart {
                return .warning
            }
        }

        if let lastUpdatedAt = gtfsCacheMetadata.lastUpdatedAt {
            let age = referenceDate.timeIntervalSince(lastUpdatedAt)
            if age < 7 * 24 * 60 * 60 {
                return .fresh
            }
            return .warning
        }

        return .warning
    }

    func freshnessLevel(for vehicle: VehiclePosition, referenceDate: Date = Date()) -> VehicleFreshnessLevel {
        guard let timestamp = vehicle.lastUpdatedAt ?? lastVehicleRefreshAt else {
            return .stale
        }

        let age = max(0, referenceDate.timeIntervalSince(timestamp))
        if age <= liveFreshnessThreshold {
            return .live
        }
        if age <= agingFreshnessThreshold {
            return .aging
        }
        return .stale
    }

    private func performSingleRefreshIfNeeded(trigger: LiveRefreshTrigger) async {
        guard !isRefreshing else { return }
        await performSingleRefresh(trigger: trigger)
    }

    private func performSingleRefresh(trigger: LiveRefreshTrigger) async {
        await didStartRefresh(trigger: trigger)

        do {
            let snapshot = try await realtimeRepository.fetchSnapshot()
            await didReceiveSnapshot(snapshot, trigger: trigger)
        } catch {
            await MainActor.run {
                if hasLoadedStaticData {
                    liveFeedStatusMessage = "Live tracking unavailable"
                    phase = .ready
                } else {
                    phase = .error("Refresh failed: \(error.localizedDescription)")
                }
            }
        }

        await didFinishRefresh(trigger: trigger)
    }

    private func didStartRefresh(trigger: LiveRefreshTrigger) async {
        await MainActor.run {
            isRefreshing = true
            if trigger == .manual {
                withAnimation(.easeOut(duration: 0.16)) {
                    busLayerOpacity = 0.2
                }
            }
        }
    }

    private func didReceiveSnapshot(_ snapshot: RealtimeSnapshot, trigger: LiveRefreshTrigger) async {
        await MainActor.run {
            vehicles = snapshot.vehicles
            var updatesByTripID: [String: TripUpdatePayload] = [:]
            for update in snapshot.tripUpdates where updatesByTripID[update.tripID] == nil {
                updatesByTripID[update.tripID] = update
            }
            tripUpdatesByTripID = updatesByTripID
            lastVehicleRefreshAt = Date()
            liveFeedStatusMessage = nil
            updateDisplayedVehicleSelection(using: snapshot.vehicles)
            applyDisplayedVehiclesFrame(interpolatedVehicles.isEmpty ? snapshot.vehicles : interpolatedVehicles)
            scheduleSuggestionRefresh()
            refreshSelectedBusDetailIfNeeded()
            phase = .ready
        }

        await beginInterpolation(to: snapshot.vehicles)
    }

    private func didFinishRefresh(trigger: LiveRefreshTrigger) async {
        await MainActor.run {
            if trigger == .manual {
                withAnimation(.easeIn(duration: 0.24)) {
                    busLayerOpacity = 1
                }
            }
            isRefreshing = false
        }
    }

    private func beginInterpolation(to targetVehicles: [VehiclePosition]) async {
        stopInterpolation()
        let token = interpolationToken

        if interpolatedVehicles.isEmpty {
            await interpolationEngine.setInitial(targetVehicles)
            interpolatedVehicles = targetVehicles
            applyDisplayedVehiclesFrame(targetVehicles)
            return
        }

        let routeCandidatesByVehicleID = buildRouteCandidatesByVehicleID(for: targetVehicles)
        let totalSeconds = await interpolationEngine.beginTransition(
            to: targetVehicles,
            routeCandidatesByVehicleID: routeCandidatesByVehicleID,
            routeAnimationDuration: durationToTimeInterval(livePollInterval),
            fallbackAnimationDuration: noRouteFallbackAnimationDuration,
            maxJumpMeters: interpolationConfig.maxJumpMeters,
            offRouteThresholdMeters: routeSnapThresholdMeters,
            token: token
        )
        guard totalSeconds > 0 else {
            let frame = await interpolationEngine.frame(elapsed: 0, token: token)
            interpolatedVehicles = frame
            applyDisplayedVehiclesFrame(frame)
            return
        }

        interpolationTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = Date()

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startedAt)
                let frame = await self.interpolationEngine.frame(elapsed: elapsed, token: token)

                await MainActor.run {
                    guard self.interpolationToken == token else { return }
                    self.interpolatedVehicles = frame
                    self.applyDisplayedVehiclesFrame(frame)
                }

                if elapsed >= totalSeconds {
                    break
                }

                do {
                    try await Task.sleep(for: self.interpolationConfig.frameInterval)
                } catch {
                    break
                }
            }

            await MainActor.run {
                guard self.interpolationToken == token else { return }
                self.interpolationTask = nil
            }
        }
    }

    private func stopInterpolation() {
        interpolationToken += 1
        interpolationTask?.cancel()
        interpolationTask = nil
    }

    private func buildRouteCandidatesByVehicleID(for vehicles: [VehiclePosition]) -> [String: [[CLLocationCoordinate2D]]] {
        var candidatesByVehicleID: [String: [[CLLocationCoordinate2D]]] = [:]
        candidatesByVehicleID.reserveCapacity(vehicles.count)

        for vehicle in vehicles {
            candidatesByVehicleID[vehicle.id] = routeCandidates(for: vehicle)
        }

        return candidatesByVehicleID
    }

    private func routeCandidates(for vehicle: VehiclePosition) -> [[CLLocationCoordinate2D]] {
        guard let routeID = vehicle.route?.trimmingCharacters(in: .whitespacesAndNewlines),
              !routeID.isEmpty else {
            return []
        }

        let directionID = vehicle.direction.map(String.init) ?? "0"
        let key = RouteKey(route: routeID, direction: directionID)
        var candidates: [[CLLocationCoordinate2D]] = []

        if let shapeIDs = routeShapeIDsByKey[key] {
            for shapeID in shapeIDs {
                guard let shape = shapeCoordinatesByID[shapeID], shape.count >= 2 else { continue }
                candidates.append(shape)
            }
        }

        if let primaryShape = routeShapes[routeID]?[directionID], primaryShape.count >= 2 {
            candidates.append(primaryShape)
        }

        if candidates.isEmpty, let routeDirectionShapes = routeShapes[routeID] {
            for shape in routeDirectionShapes.values where shape.count >= 2 {
                candidates.append(shape)
            }
        }

        return candidates
    }

    private func durationToTimeInterval(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + (Double(components.attoseconds) / 1_000_000_000_000_000_000)
    }

    private func startLivePollingIfNeeded() {
        guard hasLoadedStaticData,
              isSceneActive,
              !isLiveUpdatesPaused,
              livePollingTask == nil else { return }

        livePollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.performSingleRefreshIfNeeded(trigger: .polling)
                do {
                    try await Task.sleep(for: self.livePollInterval)
                } catch {
                    break
                }
            }
            await MainActor.run {
                self.livePollingTask = nil
            }
        }
    }

    private func stopLivePolling() {
        livePollingTask?.cancel()
        livePollingTask = nil
    }

    private func performStaticRefreshNow() async {
        await MainActor.run {
            isRefreshingStaticData = true
            staticDataRefreshStatus = ""
        }

        do {
            let refreshed = try await gtfsRepository.refreshStaticData(force: true)
            await applyStaticData(refreshed)
            await refreshCacheMetadata()
            await MainActor.run {
                phase = .ready
                staticDataRefreshStatus = "Updated just now"
            }
        } catch {
            await MainActor.run {
                staticDataRefreshStatus = "Update failed: \(error.localizedDescription)"
            }
        }

        await MainActor.run {
            isRefreshingStaticData = false
        }
    }

    private func refreshCacheMetadata() async {
        gtfsCacheMetadata = await gtfsRepository.cacheMetadata()
    }

    private func applyStaticData(_ staticData: GTFSStaticData) async {
        routeShapes = staticData.routeShapes
        routeStops = staticData.routeStops
        routeStopSchedules = staticData.routeStopSchedules
        shapeCoordinatesByID = staticData.shapeCoordinatesByID
        routeShapeIDsByKey = staticData.routeShapeIDsByKey
        routeDirectionLabels = staticData.routeDirectionLabels
        routeStylesByRouteID = staticData.routeStylesByRouteID
        rebuildStopIndexes()
        availableRoutes = staticData.availableRoutes
        hasLoadedStaticData = true
        scheduleSearchIndexBuild(using: staticData)
        await routeIndex.rebuild(from: staticData.routeShapes)
        scheduleSuggestionRefresh()
        refreshSelectedBusDetailIfNeeded()
    }

    private func scheduleSearchIndexBuild(using staticData: GTFSStaticData) {
        searchIndexBuildTask?.cancel()
        searchIndex = nil

        searchIndexBuildTask = Task { [weak self] in
            guard let self else { return }
            let builtIndex = await self.buildSearchIndex(staticData: staticData)
            if Task.isCancelled { return }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.searchIndex = builtIndex
                self.searchIndexBuildTask = nil
            }
        }
    }

    private func buildSearchIndex(staticData: GTFSStaticData) async -> SearchIndex {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let index = SearchIndexBuilder.build(from: staticData)
                continuation.resume(returning: index)
            }
        }
    }

    private func rebuildStopIndexes() {
        var nextStopsByID: [String: BusStop] = [:]
        var nextRouteKeysByStopID: [String: Set<RouteKey>] = [:]

        for (routeKey, stops) in routeStops {
            for stop in stops {
                nextStopsByID[stop.id] = stop
                nextRouteKeysByStopID[stop.id, default: []].insert(routeKey)
            }
        }

        allStopsByID = nextStopsByID
        routeKeysByStopID = nextRouteKeysByStopID
    }

    private func recomputeDisplayedVehicles() {
        let sourceVehicles = interpolatedVehicles.isEmpty ? vehicles : interpolatedVehicles
        updateDisplayedVehicleSelection(using: sourceVehicles)
        applyDisplayedVehiclesFrame(sourceVehicles)
    }

    private func updateDisplayedVehicleSelection(using sourceVehicles: [VehiclePosition]) {
        guard let userLocation else {
            displayedVehicleIDs = nil
            return
        }

        let userPoint = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let nearby = sourceVehicles.filter { vehicle in
            let busPoint = CLLocation(latitude: vehicle.coord.latitude, longitude: vehicle.coord.longitude)
            return userPoint.distance(from: busPoint) <= nearbyVehicleDistance
        }

        displayedVehicleIDs = nearby.isEmpty ? nil : Set(nearby.map(\.id))
    }

    private func applyDisplayedVehiclesFrame(_ frameVehicles: [VehiclePosition]) {
        guard let displayedVehicleIDs else {
            displayedVehicles = frameVehicles
            return
        }
        displayedVehicles = frameVehicles.filter { displayedVehicleIDs.contains($0.id) }
    }

    private func scheduleSuggestionRefresh() {
        suggestionTask?.cancel()
        suggestionToken += 1
        let currentToken = suggestionToken

        let vehiclesSnapshot = vehicles
        let routeSnapshot = availableRoutes
        let routeStopsSnapshot = routeStops
        let routeDirectionLabelsSnapshot = routeDirectionLabels
        let locationSnapshot = userLocation
        let nearbyDistance = nearbyRouteDistance

        suggestionTask = Task {
            try? await Task.sleep(for: .milliseconds(140))
            if Task.isCancelled { return }

            let nearbyRouteKeys = await routeIndex.routeKeys(near: locationSnapshot, maxDistance: nearbyDistance)
            let nearbySuggestions = await suggestionEngine.buildSuggestions(
                vehicles: vehiclesSnapshot,
                nearbyRoutes: nearbyRouteKeys,
                allRoutes: routeSnapshot,
                routeStops: routeStopsSnapshot,
                routeDirectionLabels: routeDirectionLabelsSnapshot,
                userLocation: locationSnapshot
            )

            if Task.isCancelled { return }
            await MainActor.run {
                guard self.suggestionToken == currentToken else { return }
                self.nearbyScheduleSuggestions = nearbySuggestions
            }
        }
    }

    private func refreshSelectedBusDetailIfNeeded() {
        guard let selectedBusID,
              let bus = vehicles.first(where: { $0.id == selectedBusID }) else {
            if selectedBusID != nil {
                selectedBusDetail = nil
            }
            return
        }
        selectedBusDetail = buildBusDetail(for: bus)
    }

    private func applyRouteSearchSelection(routeID: String, preferredDirectionID: String?) -> SearchSelectionMapResponse {
        selectedBusID = nil
        selectedBusDetail = nil
        selectedRouteID = routeID

        let directionID = resolvedDirectionID(for: routeID, preferredDirectionID: preferredDirectionID)
        selectedRouteDirectionID = directionID
        if let directionID {
            selectedRouteShape = routeShapes[routeID]?[directionID] ?? []
        } else {
            selectedRouteShape = []
        }

        let detail = directionID.flatMap { routeDetail(route: routeID, directionID: $0) }
        return .route(shape: selectedRouteShape, detail: detail)
    }

    private func applyStopSearchSelection(_ stopMatch: StopSearchMatch) -> SearchSelectionMapResponse {
        selectedBusID = nil
        selectedBusDetail = nil
        selectedRouteID = nil
        selectedRouteDirectionID = nil
        selectedRouteShape = []

        let stopID = stopMatch.stop.stopId
        let coordinate = allStopsByID[stopID]?.coord ?? stopMatch.stop.coordinate
        let arrivals = stopArrivals(for: stopID)
        return .stop(coordinate: coordinate, arrivals: arrivals)
    }

    private func resolvedDirectionID(for routeID: String, preferredDirectionID: String?) -> String? {
        if let preferredDirectionID,
           routeShapes[routeID]?[preferredDirectionID] != nil ||
            routeStopSchedules[RouteKey(route: routeID, direction: preferredDirectionID)] != nil {
            return preferredDirectionID
        }

        if selectedRouteID == routeID,
           let selectedRouteDirectionID,
           routeShapes[routeID]?[selectedRouteDirectionID] != nil ||
            routeStopSchedules[RouteKey(route: routeID, direction: selectedRouteDirectionID)] != nil {
            return selectedRouteDirectionID
        }

        if let shapeDirection = routeShapes[routeID]?.keys.sorted().first {
            return shapeDirection
        }

        let scheduleDirections = routeStopSchedules.keys
            .filter { $0.route == routeID }
            .map(\.direction)
            .sorted()
        return scheduleDirections.first
    }

    private func buildBusDetail(for bus: VehiclePosition) -> BusDetailPresentation? {
        guard let route = bus.route else { return nil }
        let directionID = bus.direction.map(String.init) ?? "0"
        let key = RouteKey(route: route, direction: directionID)
        let direction = routeDirectionLabels[key] ?? frenchCardinal(for: bus.heading)

        let liveRows = liveRows(for: bus, routeKey: key)
        if !liveRows.isEmpty {
            return BusDetailPresentation(
                id: bus.id,
                route: route,
                directionText: direction,
                source: .live,
                rows: liveRows
            )
        }

        return BusDetailPresentation(
            id: bus.id,
            route: route,
            directionText: direction,
            source: .scheduled,
            rows: scheduledRows(for: key, busCoordinate: bus.coord)
        )
    }

    private func liveRows(for bus: VehiclePosition, routeKey: RouteKey) -> [BusDetailStopRow] {
        guard let tripUpdate = resolveTripUpdate(for: bus, routeKey: routeKey) else { return [] }

        let schedules = routeStopSchedules[routeKey] ?? []
        var scheduleLookupByStopID: [String: RouteStopSchedule] = [:]
        var scheduleLookupBySequence: [Int: RouteStopSchedule] = [:]
        for schedule in schedules {
            if scheduleLookupByStopID[schedule.stop.id] == nil {
                scheduleLookupByStopID[schedule.stop.id] = schedule
            }
            if scheduleLookupBySequence[schedule.sequence] == nil {
                scheduleLookupBySequence[schedule.sequence] = schedule
            }
        }
        let now = Date()

        let rows: [BusDetailStopRow] = tripUpdate.stopTimeUpdates
            .sorted { lhs, rhs in
                if let leftSequence = lhs.stopSequence, let rightSequence = rhs.stopSequence, leftSequence != rightSequence {
                    return leftSequence < rightSequence
                }
                let leftTime = lhs.arrivalTime ?? lhs.departureTime ?? .distantFuture
                let rightTime = rhs.arrivalTime ?? rhs.departureTime ?? .distantFuture
                return leftTime < rightTime
            }
            .compactMap { stopUpdate in
                let primaryTime = stopUpdate.arrivalTime ?? stopUpdate.departureTime
                if let primaryTime, primaryTime < now.addingTimeInterval(-120) {
                    return nil
                }

                let stopSchedule: RouteStopSchedule?
                if let stopID = stopUpdate.stopID, let byID = scheduleLookupByStopID[stopID] {
                    stopSchedule = byID
                } else if let sequence = stopUpdate.stopSequence {
                    stopSchedule = scheduleLookupBySequence[sequence]
                } else {
                    stopSchedule = nil
                }

                let stopName: String
                if let stopSchedule {
                    stopName = stopSchedule.stop.name
                } else if let stopID = stopUpdate.stopID {
                    stopName = "Stop \(stopID)"
                } else if let sequence = stopUpdate.stopSequence {
                    stopName = "Stop #\(sequence)"
                } else {
                    stopName = "Upcoming stop"
                }

                let rowID = "\(stopUpdate.stopID ?? "na")-\(stopUpdate.stopSequence ?? -1)-\(stopName)"
                return BusDetailStopRow(
                    id: rowID,
                    stopName: stopName,
                    arrivalText: formatRealtimeTime(stopUpdate.arrivalTime),
                    departureText: formatRealtimeTime(stopUpdate.departureTime),
                    source: .live
                )
            }

        return Array(rows.prefix(18))
    }

    private func scheduledRows(for routeKey: RouteKey, busCoordinate: CLLocationCoordinate2D) -> [BusDetailStopRow] {
        guard let schedules = routeStopSchedules[routeKey], !schedules.isEmpty else { return [] }

        let startIndex = nearestStopIndex(to: busCoordinate, in: schedules)
        let slice = schedules[startIndex...]

        let rows = slice.map { schedule in
            BusDetailStopRow(
                id: "scheduled-\(schedule.stop.id)-\(schedule.sequence)",
                stopName: schedule.stop.name,
                arrivalText: formatScheduledTime(schedule.scheduledArrival),
                departureText: formatScheduledTime(schedule.scheduledDeparture),
                source: .scheduled
            )
        }

        return Array(rows.prefix(18))
    }

    private func nearestStopIndex(to coordinate: CLLocationCoordinate2D, in schedules: [RouteStopSchedule]) -> Int {
        guard !schedules.isEmpty else { return 0 }
        let busLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        var nearestIndex = 0
        var nearestDistance = CLLocationDistance.greatestFiniteMagnitude
        for (index, schedule) in schedules.enumerated() {
            let stopLocation = CLLocation(latitude: schedule.stop.coord.latitude, longitude: schedule.stop.coord.longitude)
            let distance = busLocation.distance(from: stopLocation)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestIndex = index
            }
        }

        return nearestIndex
    }

    private func resolveTripUpdate(for bus: VehiclePosition, routeKey: RouteKey) -> TripUpdatePayload? {
        if let tripID = bus.tripID, let exact = tripUpdatesByTripID[tripID] {
            return exact
        }

        return tripUpdatesByTripID.values.first { update in
            guard let routeID = update.routeID, routeID == routeKey.route else { return false }
            if let directionID = update.directionID {
                return String(directionID) == routeKey.direction
            }
            return true
        }
    }

    private func formatRealtimeTime(_ date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func formatStopArrival(_ date: Date?, fallbackRaw: String?) -> String? {
        if let date {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return formatScheduledTime(fallbackRaw)
    }

    private func liveArrivalDate(for stopID: String, routeKey: RouteKey, now: Date) -> Date? {
        tripUpdatesByTripID.values.compactMap { update in
            guard update.routeID == routeKey.route else { return nil }
            if let directionID = update.directionID, String(directionID) != routeKey.direction {
                return nil
            }

            return update.stopTimeUpdates
                .filter { stopUpdate in stopUpdate.stopID == stopID }
                .compactMap { stopUpdate in stopUpdate.arrivalTime ?? stopUpdate.departureTime }
                .filter { $0 >= now.addingTimeInterval(-120) }
                .min()
        }
        .min()
    }

    private func formatScheduledTime(_ raw: String?) -> String? {
        if let date = scheduledTimeDate(raw) {
            return date.formatted(date: .omitted, time: .shortened)
        }

        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func scheduledTimeDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour % 24
        components.minute = minute
        components.second = 0

        guard var date = Calendar.current.date(from: components) else { return nil }
        let dayOffset = hour / 24
        if dayOffset > 0, let rolled = Calendar.current.date(byAdding: .day, value: dayOffset, to: date) {
            date = rolled
        }

        return date
    }

    private func frenchCardinal(for heading: Double) -> String {
        switch heading {
        case 45..<135:
            return "Est"
        case 135..<225:
            return "Sud"
        case 225..<315:
            return "Ouest"
        default:
            return "Nord"
        }
    }
}
