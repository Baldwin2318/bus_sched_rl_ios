import SwiftUI
import MapKit
import Combine

private struct TraceArrowPoint: Identifiable {
    let id: Int
    let coord: CLLocationCoordinate2D
    let angle: Double
}

private struct LivePulseDot: View {
    let isActive: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(isActive ? Color.green : Color.gray)
            .frame(width: 9, height: 9)
            .scaleEffect(isActive && pulse ? 1.3 : 1.0)
            .opacity(isActive && pulse ? 0.55 : 1.0)
            .onAppear {
                pulse = isActive
            }
            .onChange(of: isActive) { _, active in
                pulse = active
            }
            .animation(
                isActive ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
                value: pulse
            )
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var vm = BusMapViewModel()
    @StateObject private var locationService = LocationService()

    @State private var mapCamera = MapCameraPosition.automatic
    @State private var didCenterToUser = false
    @State private var tracePhase = 0
    @State private var showTodaySchedules = false
    @State private var showSettings = false

    private let traceTimer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $mapCamera, interactionModes: .all) {
                    if let userLocation = locationService.location {
                        Marker("You", systemImage: "location.circle.fill", coordinate: userLocation)
                            .tint(.red)
                    }

                    if !vm.selectedRouteShape.isEmpty {
                        MapPolyline(coordinates: vm.selectedRouteShape)
                            .stroke(.blue.opacity(0.85), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

                        ForEach(traceArrowPoints()) { point in
                            Annotation("", coordinate: point.coord) {
                                Image(systemName: "arrow.forward.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white, .blue)
                                    .rotationEffect(.degrees(point.angle))
                                    .shadow(color: .blue.opacity(0.35), radius: 4, x: 0, y: 2)
                            }
                        }
                    }

                    ForEach(vm.displayedVehicles) { vehicle in
                        Annotation(vehicle.route ?? "Bus", coordinate: vehicle.coord) {
                            Button {
                                vm.selectBus(vehicle)
                            } label: {
                                VStack(spacing: 3) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.black.opacity(0.78))
                                            .frame(width: 34, height: 34)
                                        Image(systemName: "bus.fill")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(.white)
                                            .rotationEffect(.degrees(vehicle.heading))
                                    }
                                    Text(markerText(for: vehicle))
                                        .font(.system(size: 10, weight: .bold))
                                        .lineLimit(1)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(.ultraThinMaterial, in: Capsule())
                                }
                                .opacity(vm.busLayerOpacity)
                                .scaleEffect(vm.selectedBusID == vehicle.id ? 1.1 : 1.0)
                                .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .ignoresSafeArea()

                VStack(spacing: 10) {
                    nearbyBusesStrip

                    HStack(alignment: .center, spacing: 10) {
                        todaySchedulesButton
                        Spacer()
                        liveToggleButton
                        locateMeButton
                        refreshButton
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
            .navigationTitle("STM Bus Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Open settings")
                }
            }
            .safeAreaInset(edge: .top) {
                HStack(spacing: 8) {
                    statusPill
                    Spacer()
                    liveStatusPill
                }
                .padding(.horizontal, 12)
            }
        }
        .task {
            vm.loadIfNeeded()
            vm.setScenePhase(scenePhase)
            locationService.requestAccessAndStart()
        }
        .onChange(of: scenePhase) { _, newPhase in
            vm.setScenePhase(newPhase)
        }
        .onReceive(locationService.$location.compactMap { $0 }) { location in
            vm.updateUserLocation(location)
            if !didCenterToUser {
                didCenterToUser = true
                mapCamera = .region(
                    MKCoordinateRegion(
                        center: location,
                        span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
                    )
                )
            }
        }
        .onReceive(traceTimer) { _ in
            guard !vm.selectedRouteShape.isEmpty else { return }
            tracePhase = (tracePhase + 1) % 1000
        }
        .sheet(isPresented: $showTodaySchedules) {
            todaySchedulesSheet
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
                .presentationDetents([.medium, .large])
        }
        .sheet(
            isPresented: Binding(
                get: { vm.selectedBusDetail != nil },
                set: { isPresented in
                    if !isPresented {
                        vm.dismissBusDetail()
                    }
                }
            )
        ) {
            if let detail = vm.selectedBusDetail {
                busDetailSheet(for: detail)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var nearbyBusesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let nearby = Array(vm.nearbyScheduleSuggestions.prefix(6))
                if nearby.isEmpty {
                    Text("Finding nearby buses...")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                } else {
                    ForEach(nearby) { suggestion in
                        Button {
                            vm.applySuggestion(suggestion)
                        } label: {
                            Text(suggestion.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var todaySchedulesButton: some View {
        Button {
            vm.refreshSuggestionsForCurrentState()
            showTodaySchedules = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                Text("Today's Schedules")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var statusPill: some View {
        Group {
            if !vm.statusMessage.isEmpty {
                Text(vm.statusMessage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    private var liveStatusPill: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                LivePulseDot(isActive: !vm.isLiveUpdatesPaused)
                Text(liveStatusText(at: context.date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var refreshButton: some View {
        Button {
            vm.refreshLiveBuses()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: vm.isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                Text(vm.isRefreshing ? "Refreshing" : "Refresh")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(vm.isRefreshing)
    }

    private var liveToggleButton: some View {
        Button {
            vm.toggleLiveUpdatesPaused()
        } label: {
            Image(systemName: vm.isLiveUpdatesPaused ? "play.fill" : "pause.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(11)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(vm.isLiveUpdatesPaused ? "Resume live updates" : "Pause live updates")
    }

    private var locateMeButton: some View {
        Button {
            guard let location = locationService.location else { return }
            mapCamera = .region(
                MKCoordinateRegion(
                    center: location,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            )
        } label: {
            Image(systemName: "location.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(11)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go to current location")
        .disabled(locationService.location == nil)
    }

    private var todaySchedulesSheet: some View {
        NavigationStack {
            List {
                Section {
                    Text("Schedules for \(Date.now.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline)
                    Text("Times are estimated from nearby live buses and nearest stops.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if vm.nearbyScheduleSuggestions.isEmpty {
                    Section {
                        Text("No nearby bus schedules available yet.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Nearby Buses") {
                        ForEach(vm.nearbyScheduleSuggestions) { suggestion in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(suggestion.title)
                                    .font(.headline)
                                Text(scheduleDetail(for: suggestion))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let etaMinutes = suggestion.etaMinutes {
                                    Text("Estimated arrival: \(clockTime(afterMinutes: etaMinutes))")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Today's Schedules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.refreshLiveBuses()
                        vm.refreshSuggestionsForCurrentState()
                    } label: {
                        if vm.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(vm.isRefreshing)
                    .accessibilityLabel("Refresh schedules")
                }
            }
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("GTFS Data") {
                    LabeledContent("Last updated", value: formattedLastUpdated(vm.gtfsCacheMetadata.lastUpdatedAt))
                    LabeledContent("Feed validity", value: feedValidityText())
                    if let feedVersion = vm.gtfsCacheMetadata.feedInfo?.feedVersion, !feedVersion.isEmpty {
                        LabeledContent("Feed version", value: feedVersion)
                    }

                    HStack {
                        Text("Staleness")
                        Spacer()
                        Circle()
                            .fill(stalenessColor())
                            .frame(width: 10, height: 10)
                        Text(vm.gtfsStalenessLevel().label)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        vm.refreshStaticDataNow()
                    } label: {
                        HStack(spacing: 8) {
                            if vm.isRefreshingStaticData {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(vm.isRefreshingStaticData ? "Updating..." : "Update Now")
                        }
                    }
                    .disabled(vm.isRefreshingStaticData)

                    Text(cacheStatusText())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showSettings = false
                    }
                }
            }
        }
    }

    private func busDetailSheet(for detail: BusDetailPresentation) -> some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Route", value: "\(detail.route) \(detail.directionText)")
                    LabeledContent("Data source", value: detail.source.rawValue)
                }

                if detail.rows.isEmpty {
                    Section {
                        Text("No stop predictions available.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Upcoming Stops") {
                        ForEach(detail.rows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.stopName)
                                    .font(.headline)
                                Text(stopTimeText(for: row))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(row.source.rawValue)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(row.source == .live ? .green : .secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Bus Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        vm.dismissBusDetail()
                    }
                }
            }
        }
    }

    private func scheduleDetail(for suggestion: BusSuggestion) -> String {
        var chunks: [String] = []
        if let stop = suggestion.nearestStopName, !stop.isEmpty {
            chunks.append("Stop: \(stop)")
        }
        if let meters = suggestion.metersAway {
            let kmAway = Double(meters) / 1000
            chunks.append(String(format: "%.2f km away", kmAway))
        }
        if let eta = suggestion.etaMinutes {
            chunks.append("ETA \(eta) min")
        }
        return chunks.joined(separator: " • ")
    }

    private func liveStatusText(at now: Date) -> String {
        if vm.isLiveUpdatesPaused {
            return "Paused"
        }
        guard let last = vm.lastVehicleRefreshAt else {
            return "Waiting for live feed..."
        }
        let seconds = max(0, Int(now.timeIntervalSince(last)))
        return "Updated \(seconds)s ago"
    }

    private func stopTimeText(for row: BusDetailStopRow) -> String {
        var chunks: [String] = []
        if let arrival = row.arrivalText {
            chunks.append("Arrive \(arrival)")
        }
        if let departure = row.departureText {
            chunks.append("Depart \(departure)")
        }
        if chunks.isEmpty {
            return "No time available"
        }
        return chunks.joined(separator: " • ")
    }

    private func clockTime(afterMinutes minutes: Int) -> String {
        let date = Calendar.current.date(byAdding: .minute, value: minutes, to: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func markerText(for vehicle: VehiclePosition) -> String {
        let route = vehicle.route ?? "--"
        return "\(route) \(vm.directionText(for: vehicle))"
    }

    private func formattedLastUpdated(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func feedValidityText() -> String {
        guard let feedInfo = vm.gtfsCacheMetadata.feedInfo else { return "Unknown" }
        let start = feedInfo.feedStartDate?.formatted(date: .abbreviated, time: .omitted) ?? "--"
        let end = feedInfo.feedEndDate?.formatted(date: .abbreviated, time: .omitted) ?? "--"
        return "\(start) to \(end)"
    }

    private func stalenessColor() -> Color {
        switch vm.gtfsStalenessLevel() {
        case .fresh:
            return .green
        case .warning:
            return .yellow
        case .expired:
            return .red
        }
    }

    private func cacheStatusText() -> String {
        if vm.isRefreshingStaticData {
            return "Updating..."
        }
        if !vm.staticDataRefreshStatus.isEmpty {
            return vm.staticDataRefreshStatus
        }
        if vm.gtfsCacheMetadata.lastUpdatedAt == nil {
            return "No local cache found yet."
        }
        return "Up to date"
    }

    private func traceArrowPoints() -> [TraceArrowPoint] {
        let shape = vm.selectedRouteShape
        guard shape.count > 5 else { return [] }

        let spacing = max(shape.count / 7, 1)
        let offset = tracePhase % spacing

        var points: [TraceArrowPoint] = []
        var index = offset
        var id = 0
        while index + 1 < shape.count {
            let current = shape[index]
            let next = shape[min(index + 1, shape.count - 1)]
            let angle = bearing(from: current, to: next)
            points.append(TraceArrowPoint(id: id, coord: current, angle: angle))
            id += 1
            index += spacing
        }

        return points
    }

    private func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180
        let dLon = lon2 - lon1

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        return radians * 180 / .pi
    }
}
