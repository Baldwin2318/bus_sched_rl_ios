import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel = NearbyETAViewModel()
    @StateObject private var locationService = LocationService()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                NearbyETATheme.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        header
                        searchBar

                        if shouldShowLocationBanner {
                            locationBanner
                        }

                        if let liveStatusMessage = viewModel.liveStatusMessage {
                            statusBanner(text: liveStatusMessage, tint: .orange)
                        }

                        if !viewModel.searchResults.isEmpty {
                            searchResultsPanel
                        }

                        cardsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
                .refreshable {
                    viewModel.refreshManually()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .topBarTrailing) {
//                    Button {
//                        viewModel.refreshManually()
//                    } label: {
//                        if viewModel.isRefreshing {
//                            ProgressView()
//                                .controlSize(.small)
//                        } else {
//                            Image(systemName: "arrow.clockwise")
//                                .font(.headline.weight(.semibold))
//                        }
//                    }
//                    .disabled(viewModel.isRefreshing)
//                    .accessibilityLabel("Refresh arrivals")
//                }
//            }
        }
        .task {
            viewModel.loadIfNeeded()
            viewModel.setScenePhase(scenePhase)
            locationService.requestAccessAndStart()
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.setScenePhase(newPhase)
        }
        .onChange(of: locationService.authorizationState) { _, newState in
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
            return "Location is currently unavailable. Search still works, but the nearby ETA feed cannot center on your actual position."
        case .authorized:
            return ""
        }
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

    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.titleText)
                        .font(.title3.weight(.semibold))
                    if let lastUpdatedAt = viewModel.lastUpdatedAt {
                        Text("Updated \(lastUpdatedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(NearbyETATheme.secondaryText)
                    }
                }
                Spacer(minLength: 12)
                if !viewModel.cards.isEmpty {
                    Text("\(viewModel.cards.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NearbyETATheme.secondaryText)
                }
            }

            switch viewModel.phase {
            case .idle, .loading where viewModel.cards.isEmpty:
                loadingPanel
            case .error(let message):
                statusBanner(text: message, tint: .red)
            case .ready, .loading, .idle:
                if viewModel.cards.isEmpty {
                    emptyStatePanel
                } else {
                    ForEach(viewModel.cards) { card in
                        NavigationLink {
                            ArrivalDetailView(viewModel: viewModel, initialCard: card)
                        } label: {
                            ETACardView(card: card, showsDisclosureIndicator: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var loadingPanel: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading transit data...")
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
