import SwiftUI
import UIKit

struct ContentView: View {
    private let loadingSkeletonCount = 4

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @StateObject private var viewModel = NearbyETAViewModel()
    @StateObject private var locationService = LocationService()
    @State private var navigationPath: [NearbyETACard] = []
    @State private var isShowingAboutSheet = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                NearbyETATheme.background.ignoresSafeArea()

                List {
                    Section {
                        header
                            .listRowStyling()

                        searchBar
                            .listRowStyling()

                        if shouldShowLocationBanner {
                            locationBanner
                                .listRowStyling()
                        }

                        if viewModel.showsStaticDataUpdatePrompt {
                            staticDataUpdatePanel
                                .listRowStyling()
                                .accessibilityIdentifier("static-data-update-panel")
                        }

                        if let liveStatusMessage = viewModel.liveStatusMessage {
                            statusBanner(text: liveStatusMessage, tint: .orange)
                                .listRowStyling()
                        }

                        if !viewModel.searchResults.isEmpty {
                            searchResultsPanel
                                .listRowStyling()
                                .accessibilityIdentifier("search-results-section")
                        }
                    }

                    if !viewModel.favoriteCards.isEmpty {
                        Section {
                            ForEach(viewModel.favoriteCards) { card in
                                cardLink(card)
                                    .listRowStyling()
                            }
                        } header: {
                            sectionHeader(
                                title: "Favorites",
                                count: viewModel.favoriteCards.count
                            )
                        }
                    }

                    Section {
                        switch viewModel.phase {
                        case .idle, .loading where viewModel.nearbyCards.isEmpty:
                            ForEach(0..<loadingSkeletonCount, id: \.self) { index in
                                SkeletonETACardView()
                                    .listRowStyling()
                                    .accessibilityIdentifier("loading-skeleton-\(index)")
                            }
                        case .error(let message):
                            statusBanner(text: message, tint: .red)
                                .listRowStyling()
                        case .ready, .loading, .idle:
                            if viewModel.nearbyCards.isEmpty {
                                emptyStatePanel
                                    .listRowStyling()
                            } else {
                                ForEach(viewModel.nearbyCards) { card in
                                    cardLink(card)
                                        .listRowStyling()
                                }
                            }
                        }
                    } header: {
                        sectionHeader(
                            title: viewModel.titleText,
                            count: viewModel.nearbyCards.isEmpty ? nil : viewModel.nearbyCards.count,
                            subtitle: viewModel.lastUpdatedAt.map {
                                "Updated \($0.formatted(date: .omitted, time: .shortened))"
                            }
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .refreshable {
                    viewModel.refreshManually()
                }
                .scrollDismissesKeyboard(.interactively)
                .navigationDestination(for: NearbyETACard.self) { card in
                    ArrivalDetailView(
                        viewModel: viewModel,
                        locationService: locationService,
                        initialCard: card
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isShowingAboutSheet = true
                        } label: {
                            Label("About", systemImage: "info.circle")
                        }
                        .accessibilityIdentifier("about-menu-item")
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("settings-menu-button")
                }
            }
        }
        .sheet(isPresented: $isShowingAboutSheet) {
            AboutView()
                .accessibilityIdentifier("about-sheet")
        }
        .task {
            viewModel.loadIfNeeded()
            viewModel.setScenePhase(scenePhase)
            viewModel.updateLocationAuthorization(locationService.authorizationState)
            locationService.requestAccessAndStart()
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.setScenePhase(newPhase)
        }
        .onChange(of: locationService.authorizationState) { _, newState in
            viewModel.updateLocationAuthorization(newState)
            if newState.isAuthorized {
                locationService.requestAccessAndStart()
            }
        }
        .onReceive(locationService.$location) { location in
            viewModel.updateUserLocation(location)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bus ETA")
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            Text(viewModel.subtitleText)
                .font(.subheadline)
                .foregroundStyle(NearbyETATheme.secondaryText)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(NearbyETATheme.secondaryText)

            TextField("Search route or stop", text: $viewModel.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isSearchFocused)

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.clearSearch()
                    isSearchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(NearbyETATheme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(NearbyETATheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(NearbyETATheme.panelBorder, lineWidth: 1)
        )
    }

    private var shouldShowLocationBanner: Bool {
        switch locationService.authorizationState {
        case .authorized:
            return false
        case .notDetermined, .denied, .restricted:
            return true
        }
    }

    private var locationBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location unlocks nearby arrivals.")
                .font(.headline)
            Text(locationBannerBody)
                .font(.subheadline)
                .foregroundStyle(NearbyETATheme.secondaryText)

            if locationService.authorizationState == .notDetermined {
                Button("Allow Location Access") {
                    locationService.requestAccessAndStart()
                }
                .buttonStyle(.borderedProminent)
            } else if locationService.authorizationState == .denied || locationService.authorizationState == .restricted {
                Button("Open Settings") {
                    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(settingsURL)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NearbyETATheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(NearbyETATheme.panelBorder, lineWidth: 1)
        )
    }

    private var locationBannerBody: String {
        switch locationService.authorizationState {
        case .notDetermined:
            return "The home screen uses your current location to load routes and stops closest to you."
        case .denied, .restricted:
            return "Location is off. The app is showing schedule-only arrivals without using your location until you turn access back on."
        case .authorized:
            return ""
        }
    }

    private var staticDataUpdatePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.staticDataStatusTitle)
                .font(.headline)
            Text(viewModel.staticDataStatusBody)
                .font(.subheadline)
                .foregroundStyle(NearbyETATheme.secondaryText)

            Button {
                viewModel.redownloadStaticData()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isRefreshingStaticData {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                    Text("Redownload transit data")
                }
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isRefreshingStaticData)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NearbyETATheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(NearbyETATheme.panelBorder, lineWidth: 1)
        )
    }

    private func statusBanner(text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(NearbyETATheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
    }

    private var searchResultsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Search Matches")
                .font(.headline)
            ForEach(viewModel.searchResults) { result in
                Button {
                    viewModel.selectSearchResult(result)
                    isSearchFocused = false
                } label: {
                    SearchResultRow(result: result)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NearbyETATheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(NearbyETATheme.panelBorder, lineWidth: 1)
        )
    }

    private func cardLink(_ card: NearbyETACard) -> some View {
        Button {
            navigationPath.append(card)
        } label: {
            ETACardView(
                card: card,
                quality: viewModel.cardQuality(for: card),
                showsDisclosureIndicator: true
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                viewModel.toggleFavorite(card)
            } label: {
                Label(
                    viewModel.isFavorite(card) ? "Remove Favorite" : "Save Favorite",
                    systemImage: viewModel.isFavorite(card) ? "star.slash" : "star.fill"
                )
            }
            .tint(.yellow)
        }
    }

    private func sectionHeader(
        title: String,
        count: Int? = nil,
        subtitle: String? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .textCase(nil)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(NearbyETATheme.secondaryText)
                        .textCase(nil)
                }
            }
            Spacer(minLength: 12)
            if let count {
                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NearbyETATheme.secondaryText)
                    .textCase(nil)
            }
        }
        .padding(.top, 8)
    }

    private var emptyStatePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(emptyStateTitle)
                .font(.headline)
            Text(emptyStateBody)
                .font(.subheadline)
                .foregroundStyle(NearbyETATheme.secondaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NearbyETATheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(NearbyETATheme.panelBorder, lineWidth: 1)
        )
    }

    private var emptyStateTitle: String {
        switch locationService.authorizationState {
        case .notDetermined, .denied, .restricted where viewModel.query.isEmpty:
            return "Waiting for location"
        default:
            return "No arrivals found"
        }
    }

    private var emptyStateBody: String {
        switch locationService.authorizationState {
        case .notDetermined, .denied, .restricted where viewModel.query.isEmpty:
            return "Allow location access or search for a stop or route to load arrivals."
        default:
            return "Try a different route or stop, or refresh to pull the latest realtime data."
        }
    }
}

private extension View {
    func listRowStyling() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 7, leading: 0, bottom: 7, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

private struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                switch result {
                case .route(let route):
                    Text(route.route.routeShortName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(routeChipColor(hex: route.route.routeColor), in: Capsule())
                case .stop:
                    Image(systemName: "mappin.and.ellipse")
                        .font(.headline)
                        .foregroundStyle(NearbyETATheme.accentFallback)
                        .frame(width: 36, height: 36)
                        .background(NearbyETATheme.accentFallback.opacity(0.12), in: Circle())
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(primaryText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(NearbyETATheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var primaryText: String {
        switch result {
        case .route(let route):
            if let directionText = route.directionText {
                return "\(route.route.routeLongName) • \(directionText)"
            }
            return route.route.routeLongName
        case .stop(let stop):
            return stop.stop.stopName
        }
    }

    private var secondaryText: String {
        switch result {
        case .route:
            return "Show arrivals for this route"
        case .stop(let stop):
            let routes = stop.stop.nearbyRouteIds.prefix(4).joined(separator: ", ")
            return routes.isEmpty ? "Show arrivals for this stop" : "Routes \(routes)"
        }
    }
}
