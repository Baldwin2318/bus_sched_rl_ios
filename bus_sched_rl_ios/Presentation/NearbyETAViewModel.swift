import Foundation
import CoreLocation
import SwiftUI

@MainActor
final class NearbyETAViewModel: ObservableObject {
    private enum SearchConfig {
        static let debounceDelay: Duration = .milliseconds(180)
        static let maxResults = 20
    }

    @Published var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            handleQueryChanged()
        }
    }

    @Published private(set) var cards: [NearbyETACard] = []
    @Published private(set) var searchResults: [SearchResult] = []
    @Published private(set) var phase: NearbyETAPhase = .idle
    @Published private(set) var isRefreshing = false
    @Published private(set) var liveStatusMessage: String?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var activeScope: NearbyETAScope = .nearby
    @Published private(set) var selectedResult: SearchResult?

    private let gtfsRepository: GTFSRepository
    private let realtimeRepository: RealtimeRepository
    private let composer = NearbyETAComposer()
    private let livePollInterval: Duration

    private var staticData: GTFSStaticData?
    private var dataIndex: TransitDataIndex?
    private var searchIndex: SearchIndex?
    private var snapshot = RealtimeSnapshot(vehicles: [], tripUpdates: [])
    private var userLocation: CLLocationCoordinate2D?
    private var isSceneActive = true
    private var hasLoaded = false
    private var suppressQuerySideEffects = false
    private var livePollingTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var cardsTask: Task<Void, Never>?
    private var cardsGeneration = 0

    init(
        gtfsRepository: GTFSRepository = LiveGTFSRepository(),
        realtimeRepository: RealtimeRepository = STMRealtimeRepository(),
        livePollInterval: Duration = .seconds(30)
    ) {
        self.gtfsRepository = gtfsRepository
        self.realtimeRepository = realtimeRepository
        self.livePollInterval = livePollInterval
    }

    deinit {
        livePollingTask?.cancel()
        searchTask?.cancel()
        cardsTask?.cancel()
    }

    var titleText: String {
        if let selectedResult {
            return selectionTitle(for: selectedResult)
        }
        return "Nearby arrivals"
    }

    var subtitleText: String {
        switch activeScope {
        case .nearby:
            return userLocation == nil
                ? "Turn on location to see buses near you."
                : "Live and fallback ETAs for stops closest to you."
        case .route:
            return "Filtered to the selected route."
        case .stop:
            return "Filtered to the selected stop."
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        phase = .loading

        Task {
            do {
                let staticData = try await gtfsRepository.loadStaticData()
                await applyStaticData(staticData)
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
            let cards = composer.composeCards(
                staticData: staticData,
                index: dataIndex,
                snapshot: snapshot,
                userLocation: location,
                scope: scope
            )

            if Task.isCancelled { return }
            await MainActor.run {
                guard self.cardsGeneration == generation else { return }
                self.cards = cards
            }
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
