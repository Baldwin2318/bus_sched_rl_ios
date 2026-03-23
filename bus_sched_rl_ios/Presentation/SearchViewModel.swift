import Foundation
import CoreLocation
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    private enum SearchConfig {
        static let debounceDelay: Duration = .milliseconds(150)
        static let loadingIndicatorDelay: Duration = .milliseconds(300)
        static let maxResults = 20
    }

    @Published var query: String = "" {
        didSet {
            scheduleQueryRefresh()
        }
    }

    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var nearbyRoutes: [RouteSearchMatch] = []
    @Published private(set) var isSearching = false
    @Published private(set) var hasSearchIndex = false
    @Published var isPresented = false {
        didSet {
            if isPresented {
                refreshCurrentState()
            } else {
                cancelAllTasks()
                isSearching = false
            }
        }
    }
    @Published private(set) var selectedResult: SearchResult?

    private var lookupActor: SearchLookupActor?
    private var userLocation: CLLocationCoordinate2D?
    private var searchTask: Task<Void, Never>?
    private var loadingTask: Task<Void, Never>?
    private var nearbyTask: Task<Void, Never>?
    private var searchGeneration = 0

    var isQueryEmpty: Bool {
        trimmedQuery.isEmpty
    }

    func setSearchIndex(_ index: SearchIndex?) {
        lookupActor = index.map(SearchLookupActor.init)
        hasSearchIndex = index != nil
        results = []
        nearbyRoutes = []
        refreshCurrentState()
    }

    func updateUserLocation(_ location: CLLocationCoordinate2D?) {
        userLocation = location
        guard isPresented, isQueryEmpty else { return }
        refreshNearbyRoutes()
    }

    func present() {
        isPresented = true
    }

    func dismiss(clearQuery: Bool) {
        isPresented = false
        if clearQuery {
            query = ""
        }
    }

    func select(_ result: SearchResult) {
        selectedResult = result
    }

    func clearSelection() {
        selectedResult = nil
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refreshCurrentState() {
        guard isPresented else { return }
        if isQueryEmpty {
            results = []
            isSearching = false
            refreshNearbyRoutes()
        } else {
            scheduleQueryRefresh()
        }
    }

    private func scheduleQueryRefresh() {
        guard isPresented else { return }

        cancelQueryTasks()

        if isQueryEmpty {
            results = []
            isSearching = false
            refreshNearbyRoutes()
            return
        }

        nearbyRoutes = []
        let localGeneration = nextGeneration()

        searchTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: SearchConfig.debounceDelay)
            } catch {
                return
            }

            if Task.isCancelled { return }
            guard let actor = self.lookupActor else {
                await MainActor.run {
                    guard self.searchGeneration == localGeneration else { return }
                    self.results = []
                    self.isSearching = false
                }
                return
            }

            await self.startLoadingIndicator(for: localGeneration)
            let results = await actor.search(
                query: self.trimmedQuery,
                userLocation: self.userLocation,
                limit: SearchConfig.maxResults
            )
            if Task.isCancelled { return }

            await MainActor.run {
                guard self.searchGeneration == localGeneration else { return }
                self.loadingTask?.cancel()
                self.loadingTask = nil
                self.isSearching = false
                self.results = results
            }
        }
    }

    private func refreshNearbyRoutes() {
        nearbyTask?.cancel()

        guard let actor = lookupActor else {
            nearbyRoutes = []
            return
        }

        let location = userLocation
        nearbyTask = Task { [weak self] in
            guard let self else { return }
            let nearby = await actor.nearbyRoutes(around: location, limit: SearchConfig.maxResults)
            if Task.isCancelled { return }

            await MainActor.run {
                guard self.isPresented, self.isQueryEmpty else { return }
                self.nearbyRoutes = nearby
            }
        }
    }

    private func startLoadingIndicator(for generation: Int) async {
        loadingTask?.cancel()
        loadingTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: SearchConfig.loadingIndicatorDelay)
            } catch {
                return
            }

            if Task.isCancelled { return }
            await MainActor.run {
                guard self.searchGeneration == generation else { return }
                self.isSearching = true
            }
        }
    }

    private func nextGeneration() -> Int {
        searchGeneration += 1
        return searchGeneration
    }

    private func cancelQueryTasks() {
        searchTask?.cancel()
        searchTask = nil
        loadingTask?.cancel()
        loadingTask = nil
    }

    private func cancelAllTasks() {
        cancelQueryTasks()
        nearbyTask?.cancel()
        nearbyTask = nil
    }
}
