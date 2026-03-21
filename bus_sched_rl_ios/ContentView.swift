import SwiftUI
import MapKit
import Combine

private struct TraceArrowPoint: Identifiable {
    let id: Int
    let coord: CLLocationCoordinate2D
    let angle: Double
}

struct ContentView: View {
    @StateObject private var vm = BusMapViewModel()
    @StateObject private var locationService = LocationService()

    @State private var mapCamera = MapCameraPosition.automatic
    @State private var didCenterToUser = false
    @State private var tracePhase = 0
    @State private var showTodaySchedules = false

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
                        locateMeButton
                        refreshButton
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
            .navigationTitle("STM Bus Map")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                HStack {
                    statusPill
                    Spacer()
                }
                .padding(.horizontal, 12)
            }
        }
        .task {
            vm.loadIfNeeded()
            locationService.requestAccessAndStart()
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

    private func clockTime(afterMinutes minutes: Int) -> String {
        let date = Calendar.current.date(byAdding: .minute, value: minutes, to: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func markerText(for vehicle: VehiclePosition) -> String {
        let route = vehicle.route ?? "--"
        return "\(route) \(vm.directionText(for: vehicle))"
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
