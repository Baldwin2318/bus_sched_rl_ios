import Foundation
import CoreLocation
import SwiftUI

@MainActor
final class NearbyETAViewModel: ObservableObject {
    private enum SearchConfig {
        static let debounceDelay: Duration = .milliseconds(180)
        static let maxResults = 20
    }

    private enum AlertConfig {
        static let maxMainAlerts = 3
        static let maxDetailAlerts = 4
    }

    private enum StaticDataConfig {
        static let refreshIntervalMonths = 6
    }

    @Published var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            handleQueryChanged()
        }
    }

    @Published private(set) var cards: [NearbyETACard] = []
    @Published private(set) var favoriteCards: [NearbyETACard] = []
    @Published private(set) var nearbyCards: [NearbyETACard] = []
    @Published private(set) var mainAlerts: [ServiceAlert] = []
    @Published private(set) var searchResults: [SearchResult] = []
    @Published private(set) var phase: NearbyETAPhase = .idle
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRefreshingStaticData = false
    @Published private(set) var liveStatusMessage: String?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var staticCacheMetadata: GTFSCacheMetadata = .empty
    @Published private(set) var activeScope: NearbyETAScope = .nearby
    @Published private(set) var selectedResult: SearchResult?

    private let gtfsRepository: GTFSRepository
    private let realtimeRepository: RealtimeRepository
    private let favoritesRepository: FavoritesRepository
    private let composer = NearbyETAComposer()
    private let livePollInterval: Duration
    private let detailRefreshInterval: Duration = .seconds(10)

    private var staticData: GTFSStaticData?
    private var dataIndex: TransitDataIndex?
    private var searchIndex: SearchIndex?
    private var snapshot = RealtimeSnapshot(vehicles: [], tripUpdates: [])
    private var userLocation: CLLocationCoordinate2D?
    private var locationAuthorizationState: LocationAuthorizationState = .notDetermined
    private var isSceneActive = true
    private var hasLoaded = false
    private var suppressQuerySideEffects = false
    private var livePollingTask: Task<Void, Never>?
    private var detailRefreshTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var cardsTask: Task<Void, Never>?
    private var cardsGeneration = 0
    private var detailRefreshObservers = 0
    private var favoriteIDs: [FavoriteArrivalID]
    private var favoriteFallbackCardsByID: [String: NearbyETACard] = [:]

    init(
        gtfsRepository: GTFSRepository = LiveGTFSRepository(),
        realtimeRepository: RealtimeRepository = STMRealtimeRepository(),
        favoritesRepository: FavoritesRepository = UserDefaultsFavoritesRepository(),
        livePollInterval: Duration = .seconds(30)
    ) {
        self.gtfsRepository = gtfsRepository
        self.realtimeRepository = realtimeRepository
        self.favoritesRepository = favoritesRepository
        self.livePollInterval = livePollInterval
        self.favoriteIDs = favoritesRepository.loadFavorites()
    }

    deinit {
        livePollingTask?.cancel()
        detailRefreshTask?.cancel()
        searchTask?.cancel()
        cardsTask?.cancel()
    }

    var titleText: String {
        if let selectedResult {
            return selectionTitle(for: selectedResult)
        }
        switch feedMode {
        case .standard:
            return "Nearby arrivals"
        case .scheduledList:
            return "Scheduled buses"
        }
    }

    var subtitleText: String {
        switch activeScope {
        case .nearby:
            switch feedMode {
            case .standard:
                return "Live and fallback ETAs for stops closest to you."
            case .scheduledList:
                return "Showing all scheduled buses until location access is turned on."
            }
        case .route:
            return "Filtered to the selected route."
        case .stop:
            return "Filtered to the selected stop."
        }
    }

    var staticDataNeedsRefresh: Bool {
        guard let lastUpdatedAt = staticCacheMetadata.lastUpdatedAt else { return false }
        guard let refreshThreshold = Calendar.current.date(
            byAdding: .month,
            value: -StaticDataConfig.refreshIntervalMonths,
            to: Date()
        ) else {
            return false
        }
        return lastUpdatedAt < refreshThreshold
    }

    var showsStaticDataUpdatePrompt: Bool {
        staticDataNeedsRefresh
    }

    var staticDataStatusTitle: String {
        "Transit data update available"
    }

    var staticDataStatusBody: String {
        guard let lastUpdatedAt = staticCacheMetadata.lastUpdatedAt else {
            return "You can redownload the GTFS dataset here every 6 months."
        }
        return "Last downloaded \(lastUpdatedAt.formatted(date: .abbreviated, time: .omitted)). Redownload the GTFS dataset to refresh schedule data."
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        phase = .loading

        Task {
            do {
                let staticData = try await gtfsRepository.loadStaticData()
                await applyStaticData(staticData)
                await refreshStaticCacheMetadata()
                phase = .ready
                refreshCards()
                startLivePollingIfNeeded()
                refreshNow(trigger: .initial)
            } catch {
                phase = .error("Failed to load transit data: \(error.localizedDescription)")
            }
        }
    }

    func setScenePhase(_ phase: ScenePhase) {
        isSceneActive = phase == .active
        if isSceneActive {
            startLivePollingIfNeeded()
        } else {
            stopLivePolling()
        }
    }

    func updateUserLocation(_ location: CLLocationCoordinate2D?) {
        userLocation = location
        refreshCards()
        scheduleSearch()
    }

    func updateLocationAuthorization(_ authorizationState: LocationAuthorizationState) {
        guard locationAuthorizationState != authorizationState else { return }
        locationAuthorizationState = authorizationState
        if authorizationState != .authorized {
            userLocation = nil
        }
        refreshCards()
        scheduleSearch()
    }

    func selectSearchResult(_ result: SearchResult) {
        selectedResult = result
        activeScope = scope(for: result)
        searchResults = []

        suppressQuerySideEffects = true
        query = selectionTitle(for: result)
        suppressQuerySideEffects = false

        refreshCards()
    }

    func clearSearch() {
        suppressQuerySideEffects = true
        query = ""
        suppressQuerySideEffects = false
        selectedResult = nil
        activeScope = .nearby
        searchResults = []
        refreshCards()
    }

    func refreshManually() {
        refreshNow(trigger: .manual)
    }

    func redownloadStaticData() {
        guard !isRefreshingStaticData else { return }
        isRefreshingStaticData = true

        Task {
            do {
                let staticData = try await gtfsRepository.refreshStaticData(force: true)
                await applyStaticData(staticData)
                await refreshStaticCacheMetadata()
                await MainActor.run {
                    self.liveStatusMessage = nil
                    self.refreshCards()
                }
            } catch {
                await MainActor.run {
                    self.liveStatusMessage = "Transit data update failed. Please try again."
                }
            }

            await MainActor.run {
                self.isRefreshingStaticData = false
            }
        }
    }

    func beginDetailRefresh() {
        detailRefreshObservers += 1
        guard detailRefreshTask == nil else { return }

        detailRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: self.detailRefreshInterval)
                } catch {
                    break
                }
                self.refreshNow(trigger: .detail)
            }

            await MainActor.run {
                self.detailRefreshTask = nil
            }
        }
    }

    func endDetailRefresh() {
        detailRefreshObservers = max(0, detailRefreshObservers - 1)
        guard detailRefreshObservers == 0 else { return }
        detailRefreshTask?.cancel()
        detailRefreshTask = nil
    }

    func cardDetail(for initialCard: NearbyETACard) -> NearbyETACard {
        favoriteCards.first(where: { $0.id == initialCard.id }) ??
            cards.first(where: { $0.id == initialCard.id }) ??
            initialCard
    }

    func isFavorite(_ card: NearbyETACard) -> Bool {
        favoriteIDs.contains(FavoriteArrivalID(card: card))
    }

    func toggleFavorite(_ card: NearbyETACard) {
        let favoriteID = FavoriteArrivalID(card: card)

        if let index = favoriteIDs.firstIndex(of: favoriteID) {
            favoriteIDs.remove(at: index)
            favoriteFallbackCardsByID[favoriteID.id] = nil
        } else {
            favoriteIDs.append(favoriteID)
            favoriteFallbackCardsByID[favoriteID.id] = card
        }

        favoritesRepository.saveFavorites(favoriteIDs)
        rebuildPresentationLists(referenceDate: Date())
    }

    func liveVehicle(for card: NearbyETACard) -> VehiclePosition? {
        guard card.source == .live else { return nil }

        if let liveVehicleID = card.liveVehicleID,
           let vehicle = snapshot.vehicles.first(where: { $0.id == liveVehicleID }) {
            return vehicle
        }

        if let tripID = card.tripID,
           let vehicle = snapshot.vehicles.first(where: { $0.tripID == tripID }) {
            return vehicle
        }

        let routeMatches = snapshot.vehicles.filter {
            $0.route == card.routeID && String($0.direction ?? 0) == card.directionID
        }
        if routeMatches.count == 1 {
            return routeMatches[0]
        }

        return nil
    }

    func tripUpdate(for card: NearbyETACard) -> TripUpdatePayload? {
        if let tripID = card.tripID,
           let update = snapshot.tripUpdates.first(where: { $0.tripID == tripID }) {
            return update
        }

        let routeMatches = snapshot.tripUpdates.filter {
            $0.routeID == card.routeID && String($0.directionID ?? 0) == card.directionID
        }
        if routeMatches.count == 1 {
            return routeMatches[0]
        }

        return nil
    }

    func assignedStop(for card: NearbyETACard) -> BusStop? {
        guard let tripUpdate = tripUpdate(for: card),
              let assignedStopID = tripUpdate.stopTimeUpdates.first(where: {
                  ($0.stopID ?? card.stopID) == card.stopID && $0.assignedStopID != nil
              })?.assignedStopID ?? tripUpdate.stopTimeUpdates.first(where: { $0.assignedStopID != nil })?.assignedStopID
        else {
            return nil
        }

        return dataIndex?.allStopsByID[assignedStopID]
    }

    func alerts(for card: NearbyETACard) -> [ServiceAlert] {
        scopedAlerts(
            for: [card],
            limit: AlertConfig.maxDetailAlerts,
            referenceDate: Date()
        )
    }

    func arrivalLiveMapModel(
        for card: NearbyETACard,
        userLocation: CLLocationCoordinate2D?
    ) -> ArrivalLiveMapModel? {
        guard let vehicle = liveVehicle(for: card),
              let stop = dataIndex?.allStopsByID[card.stopID] else {
            return nil
        }

        let pathCoordinates = routePathCoordinates(
            for: card,
            vehicleCoordinate: vehicle.coord,
            stopCoordinate: stop.coord
        )

        return ArrivalLiveMapModel(
            vehicle: vehicle,
            stopName: stop.name,
            stopCoordinate: stop.coord,
            userLocation: userLocation,
            pathCoordinates: pathCoordinates
        )
    }

    private func handleQueryChanged() {
        guard !suppressQuerySideEffects else { return }
        selectedResult = nil
        activeScope = .nearby
        refreshCards()
        scheduleSearch()
    }

    private func scope(for result: SearchResult) -> NearbyETAScope {
        switch result {
        case .route(let routeMatch):
            return .route(routeID: routeMatch.route.routeId, directionID: routeMatch.directionId)
        case .stop(let stopMatch):
            return .stop(stopID: stopMatch.stop.stopId)
        }
    }

    private func selectionTitle(for result: SearchResult) -> String {
        switch result {
        case .route(let routeMatch):
            if let directionText = routeMatch.directionText {
                return "\(routeMatch.route.routeShortName) \(directionText)"
            }
            return routeMatch.route.routeShortName
        case .stop(let stopMatch):
            return stopMatch.stop.stopName
        }
    }

    private func routePathCoordinates(
        for card: NearbyETACard,
        vehicleCoordinate: CLLocationCoordinate2D,
        stopCoordinate: CLLocationCoordinate2D
    ) -> [CLLocationCoordinate2D] {
        guard let staticData else {
            return [vehicleCoordinate, stopCoordinate]
        }

        let routeKey = RouteKey(route: card.routeID, direction: card.directionID)
        let shapeID = card.tripID.flatMap { staticData.shapeIDByTripID[$0] } ??
            staticData.routeShapeIDByRouteKey[routeKey]

        guard let shapeID,
              let shapePoints = staticData.shapePointsByShapeID[shapeID],
              shapePoints.count >= 2 else {
            return [vehicleCoordinate, stopCoordinate]
        }

        guard let vehicleIndex = nearestShapePointIndex(to: vehicleCoordinate, in: shapePoints),
              let stopIndex = nearestShapePointIndex(to: stopCoordinate, in: shapePoints) else {
            return [vehicleCoordinate, stopCoordinate]
        }

        if vehicleIndex <= stopIndex {
            return Array(shapePoints[vehicleIndex...stopIndex])
        }
        return Array(shapePoints[stopIndex...vehicleIndex].reversed())
    }

    private func nearestShapePointIndex(
        to coordinate: CLLocationCoordinate2D,
        in points: [CLLocationCoordinate2D]
    ) -> Int? {
        points.indices.min {
            TransitMath.planarDistanceMeters(from: points[$0], to: coordinate) <
                TransitMath.planarDistanceMeters(from: points[$1], to: coordinate)
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, let searchIndex else {
            searchResults = []
            return
        }

        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: SearchConfig.debounceDelay)
            } catch {
                return
            }

            if Task.isCancelled { return }
            let results = searchIndex.search(
                query: trimmedQuery,
                userLocation: self.userLocation,
                limit: SearchConfig.maxResults
            )
            if Task.isCancelled { return }

            await MainActor.run {
                guard self.query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuery else {
                    return
                }
                self.searchResults = results
            }
        }
    }

    private func refreshCards() {
        guard let staticData, let dataIndex else {
            cards = []
            favoriteCards = []
            nearbyCards = []
            mainAlerts = []
            return
        }

        cardsTask?.cancel()
        cardsGeneration += 1
        let generation = cardsGeneration
        let snapshot = snapshot
        let location = userLocation
        let scope = activeScope

        cardsTask = Task { [weak self] in
            guard let self else { return }
            let feedMode = self.feedMode
            let cards = composer.composeCards(
                staticData: staticData,
                index: dataIndex,
                snapshot: snapshot,
                userLocation: location,
                scope: scope,
                feedMode: feedMode
            )

            if Task.isCancelled { return }
            await MainActor.run {
                guard self.cardsGeneration == generation else { return }
                self.cards = cards
                self.rebuildPresentationLists(referenceDate: Date())
            }
        }
    }

    private func rebuildPresentationLists(referenceDate: Date) {
        let resolvedFavoriteCards = resolveFavoriteCards(referenceDate: referenceDate)
        let favoriteCardIDs = Set(resolvedFavoriteCards.map(\.id))
        let visibleCards = resolvedFavoriteCards + cards.filter { !favoriteCardIDs.contains($0.id) }

        favoriteCards = resolvedFavoriteCards
        nearbyCards = cards.filter { !favoriteCardIDs.contains($0.id) }
        mainAlerts = scopedAlerts(
            for: visibleCards,
            limit: AlertConfig.maxMainAlerts,
            referenceDate: referenceDate
        )
    }

    private func resolveFavoriteCards(referenceDate: Date) -> [NearbyETACard] {
        guard let staticData, let dataIndex else {
            return favoriteIDs.compactMap { favoriteFallbackCardsByID[$0.id] }
        }

        let resolvedCards = composer.composeFavoriteCards(
            staticData: staticData,
            index: dataIndex,
            snapshot: snapshot,
            userLocation: userLocation,
            favorites: favoriteIDs,
            feedMode: feedMode,
            referenceDate: referenceDate
        )

        for card in resolvedCards {
            favoriteFallbackCardsByID[FavoriteArrivalID(card: card).id] = card
        }

        let resolvedByID = Dictionary(uniqueKeysWithValues: resolvedCards.map { (FavoriteArrivalID(card: $0).id, $0) })
        return favoriteIDs.compactMap { favoriteID in
            resolvedByID[favoriteID.id] ?? favoriteFallbackCardsByID[favoriteID.id]
        }
    }

    private func scopedAlerts(
        for cards: [NearbyETACard],
        limit: Int?,
        referenceDate: Date
    ) -> [ServiceAlert] {
        let matchedAlerts: [ServiceAlert]
        if cards.isEmpty {
            matchedAlerts = snapshot.alerts.filter {
                $0.isGlobal && $0.isActive(at: referenceDate)
            }
        } else {
            matchedAlerts = snapshot.alerts.filter { alert in
                cards.contains { alert.matches(card: $0, at: referenceDate) }
            }
        }

        let sortedAlerts = matchedAlerts
            .reduce(into: [String: ServiceAlert]()) { partialResult, alert in
                partialResult[alert.id] = alert
            }
            .values
            .sorted { lhs, rhs in
                let lhsRank = severityRank(lhs.severity)
                let rhsRank = severityRank(rhs.severity)
                if lhsRank != rhsRank {
                    return lhsRank > rhsRank
                }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }

        if let limit {
            return Array(sortedAlerts.prefix(limit))
        }
        return sortedAlerts
    }

    private func severityRank(_ severity: AlertSeverity) -> Int {
        switch severity {
        case .severe:
            return 3
        case .warning:
            return 2
        case .info:
            return 1
        }
    }

    private var feedMode: NearbyETAFeedMode {
        guard selectedResult == nil, activeScope == .nearby else {
            return .standard
        }

        switch locationAuthorizationState {
        case .authorized:
            return .standard
        case .notDetermined, .denied, .restricted:
            return .scheduledList
        }
    }

    private func applyStaticData(_ staticData: GTFSStaticData) async {
        self.staticData = staticData
        dataIndex = TransitDataIndex(staticData: staticData)
        searchIndex = await Task.detached(priority: .userInitiated) {
            SearchIndexBuilder.build(from: staticData)
        }.value
        scheduleSearch()
    }

    private func refreshStaticCacheMetadata() async {
        let metadata = await gtfsRepository.cacheMetadata()
        await MainActor.run {
            self.staticCacheMetadata = metadata
        }
    }

    private func startLivePollingIfNeeded() {
        guard hasLoaded, isSceneActive, livePollingTask == nil else { return }
        livePollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.refreshNow(trigger: .polling)
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

    private enum RefreshTrigger {
        case initial
        case polling
        case manual
        case detail
    }

    private func refreshNow(trigger: RefreshTrigger) {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task {
            do {
                let snapshot = try await realtimeRepository.fetchSnapshot()
                await MainActor.run {
                    self.snapshot = snapshot
                    self.lastUpdatedAt = Date()
                    self.liveStatusMessage = nil
                    self.refreshCards()
                }
            } catch {
                await MainActor.run {
                    self.liveStatusMessage = "Live arrivals are temporarily unavailable."
                    if case .loading = self.phase, trigger == .initial {
                        self.phase = .ready
                    }
                    self.refreshCards()
                }
            }

            await MainActor.run {
                self.isRefreshing = false
            }
        }
    }
}
