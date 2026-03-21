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
    let nearestStopName: String?

    var title: String {
        "\(route) \(displayDirection)"
    }

    var subtitle: String {
        var chunks: [String] = []
        if let metersAway {
            chunks.append("\(metersAway)m away")
        }
        if let etaMinutes {
            chunks.append("ETA \(etaMinutes) min")
        }
        if let nearestStopName, !nearestStopName.isEmpty {
            chunks.append("Stop: \(nearestStopName)")
        }
        return chunks.joined(separator: " • ")
    }
}

@MainActor
final class BusMapViewModel: ObservableObject {
    @Published private(set) var vehicles: [VehiclePosition] = []
    @Published private(set) var displayedVehicles: [VehiclePosition] = []
    @Published private(set) var nearbyScheduleSuggestions: [BusSuggestion] = []
    @Published private(set) var selectedRouteShape: [CLLocationCoordinate2D] = []
    @Published private(set) var selectedBusID: String?
    @Published private(set) var availableRoutes: [String] = []
    @Published private(set) var phase: BusMapPhase = .idle
    @Published private(set) var isRefreshing = false
    @Published private(set) var busLayerOpacity = 1.0
    @Published private(set) var lastTraceSource: String = "none"

    private let gtfsRepository: GTFSRepository
    private let realtimeRepository: RealtimeRepository
    private let suggestionEngine = SearchSuggestionEngine()
    private let routeIndex = NearbyRouteIndex()
    private let traceResolver = RouteTraceResolver()

    private var routeShapes: [String: [String: [CLLocationCoordinate2D]]] = [:]
    private var routeStops: [RouteKey: [BusStop]] = [:]
    private var shapeCoordinatesByID: [String: [CLLocationCoordinate2D]] = [:]
    private var routeShapeIDsByKey: [RouteKey: [String]] = [:]
    private var routeDirectionLabels: [RouteKey: String] = [:]
    private var userLocation: CLLocationCoordinate2D?
    private var hasLoadedStaticData = false
    private var refreshTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    private var suggestionToken = 0

    private let nearbyVehicleDistance: CLLocationDistance = 2500
    private let nearbyRouteDistance: CLLocationDistance = 600

    var statusMessage: String {
        switch phase {
        case .idle:
            return ""
        case .loading(let message):
            return message
        case .ready:
            return isRefreshing ? "Refreshing live buses..." : "Ready"
        case .error(let message):
            return message
        }
    }

    init(
        gtfsRepository: GTFSRepository = LiveGTFSRepository(),
        realtimeRepository: RealtimeRepository = STMRealtimeRepository()
    ) {
        self.gtfsRepository = gtfsRepository
        self.realtimeRepository = realtimeRepository
    }

    deinit {
        refreshTask?.cancel()
        suggestionTask?.cancel()
    }

    func loadIfNeeded() {
        guard !hasLoadedStaticData else { return }
        phase = .loading("Loading route data...")

        Task {
            do {
                let staticData = try await gtfsRepository.loadStaticData()
                routeShapes = staticData.routeShapes
                routeStops = staticData.routeStops
                shapeCoordinatesByID = staticData.shapeCoordinatesByID
                routeShapeIDsByKey = staticData.routeShapeIDsByKey
                routeDirectionLabels = staticData.routeDirectionLabels
                availableRoutes = staticData.availableRoutes
                hasLoadedStaticData = true
                await routeIndex.rebuild(from: staticData.routeShapes)
                phase = .ready
                recomputeDisplayedVehicles()
                scheduleSuggestionRefresh()
                refreshLiveBuses()
            } catch {
                phase = .error("Failed to load routes: \(error.localizedDescription)")
            }
        }
    }

    func updateUserLocation(_ location: CLLocationCoordinate2D) {
        userLocation = location
        recomputeDisplayedVehicles()
        scheduleSuggestionRefresh()
    }

    func refreshLiveBuses() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.performSingleRefresh()
            await MainActor.run {
                self.refreshTask = nil
            }
        }
    }

    func selectBus(_ bus: VehiclePosition) {
        selectedBusID = bus.id
        let result = traceResolver.resolveTrace(
            bus: bus,
            routeShapes: routeShapes,
            routeShapeIDsByKey: routeShapeIDsByKey,
            shapeCoordinatesByID: shapeCoordinatesByID
        )
        selectedRouteShape = result.trace
        lastTraceSource = result.source
    }

    func applySuggestion(_ suggestion: BusSuggestion) {
        selectedBusID = nil
        if let direction = suggestion.directionID {
            selectedRouteShape = routeShapes[suggestion.route]?[direction] ?? []
        } else {
            selectedRouteShape = []
        }
    }

    func directionText(for vehicle: VehiclePosition) -> String {
        guard let route = vehicle.route else { return frenchCardinal(for: vehicle.heading) }
        let key = RouteKey(route: route, direction: vehicle.direction.map(String.init) ?? "0")
        return routeDirectionLabels[key] ?? frenchCardinal(for: vehicle.heading)
    }

    func refreshSuggestionsForCurrentState() {
        scheduleSuggestionRefresh()
    }

    private func performSingleRefresh() async {
        await MainActor.run {
            isRefreshing = true
            withAnimation(.easeOut(duration: 0.16)) {
                busLayerOpacity = 0.2
            }
        }

        do {
            let latest = try await realtimeRepository.fetchVehicles()
            await MainActor.run {
                vehicles = latest
                recomputeDisplayedVehicles()
                scheduleSuggestionRefresh()
                phase = .ready
            }
        } catch {
            await MainActor.run {
                phase = .error("Refresh failed: \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            withAnimation(.easeIn(duration: 0.24)) {
                busLayerOpacity = 1
            }
            isRefreshing = false
        }
    }

    private func recomputeDisplayedVehicles() {
        guard let userLocation else {
            displayedVehicles = vehicles
            return
        }

        let userPoint = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let nearby = vehicles.filter { vehicle in
            let busPoint = CLLocation(latitude: vehicle.coord.latitude, longitude: vehicle.coord.longitude)
            return userPoint.distance(from: busPoint) <= nearbyVehicleDistance
        }

        displayedVehicles = nearby.isEmpty ? vehicles : nearby
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
