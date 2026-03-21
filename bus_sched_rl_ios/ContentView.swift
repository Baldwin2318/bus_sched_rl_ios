import SwiftUI
import MapKit
import Combine
import UIKit

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

struct MarkerScalePolicy {
    let minAltitude: CLLocationDistance
    let maxAltitude: CLLocationDistance
    let minScale: CGFloat
    let maxScale: CGFloat
    let selectedScaleBoost: CGFloat
    let scaleUpdateThreshold: CGFloat
    let animationDuration: TimeInterval

    private let logMinAltitude: Double
    private let logAltitudeRange: Double

    static let `default` = MarkerScalePolicy(
        minAltitude: 250,
        maxAltitude: 24_000,
        minScale: 0.7,
        maxScale: 1.45,
        selectedScaleBoost: 1.1,
        scaleUpdateThreshold: 0.01,
        animationDuration: 0.2
    )

    var initialScale: CGFloat {
        scale(forAltitude: maxAltitude)
    }

    init(
        minAltitude: CLLocationDistance,
        maxAltitude: CLLocationDistance,
        minScale: CGFloat,
        maxScale: CGFloat,
        selectedScaleBoost: CGFloat,
        scaleUpdateThreshold: CGFloat,
        animationDuration: TimeInterval
    ) {
        self.minAltitude = minAltitude
        self.maxAltitude = maxAltitude
        self.minScale = minScale
        self.maxScale = maxScale
        self.selectedScaleBoost = selectedScaleBoost
        self.scaleUpdateThreshold = scaleUpdateThreshold
        self.animationDuration = animationDuration

        let safeMinAltitude = max(minAltitude, 1)
        let safeMaxAltitude = max(maxAltitude, safeMinAltitude + 1)
        let minLogValue = log(safeMinAltitude)
        let maxLogValue = log(safeMaxAltitude)
        logMinAltitude = minLogValue
        logAltitudeRange = max(maxLogValue - minLogValue, .leastNonzeroMagnitude)
    }

    func scale(forAltitude altitude: CLLocationDistance) -> CGFloat {
        let clampedAltitude = min(max(altitude, minAltitude), maxAltitude)
        let clampedScaleMin = min(minScale, maxScale)
        let clampedScaleMax = max(minScale, maxScale)
        let logValue = log(max(clampedAltitude, 1))
        let normalized = (logValue - logMinAltitude) / logAltitudeRange
        let clampedNormalized = min(max(normalized, 0), 1)

        let nextScale = Double(clampedScaleMax) - clampedNormalized * Double(clampedScaleMax - clampedScaleMin)
        return CGFloat(nextScale)
    }

    func composedScale(baseScale: CGFloat, isSelected: Bool) -> CGFloat {
        if isSelected {
            return baseScale * selectedScaleBoost
        }
        return baseScale
    }

    func shouldApplyScale(current: CGFloat, next: CGFloat) -> Bool {
        abs(current - next) >= scaleUpdateThreshold
    }
}

private enum TransitSemanticPalette {
    static let liveSource = Color.green.opacity(0.92)
    static let scheduledSource = Color.orange.opacity(0.9)
    static let liveFreshness = Color.green.opacity(0.85)
    static let agingFreshness = Color.yellow.opacity(0.82)
    static let staleFreshness = Color.red.opacity(0.74)
    static let fallbackRoute = Color.blue.opacity(0.9)
    static let fallbackRouteText = Color.white
}

private enum TransitColorResolver {
    static func routeColor(style: GTFSRouteStyle?) -> Color {
        if let color = color(fromHex: style?.routeColorHex) {
            return color
        }
        return TransitSemanticPalette.fallbackRoute
    }

    static func routeTextColor(style: GTFSRouteStyle?) -> Color {
        if let color = color(fromHex: style?.routeTextColorHex) {
            return color
        }
        return TransitSemanticPalette.fallbackRouteText
    }

    private static func color(fromHex hex: String?) -> Color? {
        guard let hex else { return nil }
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
        guard normalized.count == 6, let value = Int(normalized, radix: 16) else { return nil }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }
}

private enum ContrastAccessibility {
    static let minimumContrastRatio = 4.5

    static func readableTextColor(preferred: Color, on background: Color) -> Color {
        if contrastRatio(preferred, background) >= minimumContrastRatio {
            return preferred
        }

        let whiteContrast = contrastRatio(.white, background)
        let blackContrast = contrastRatio(.black, background)
        return whiteContrast >= blackContrast ? .white : .black
    }

    private static func contrastRatio(_ foreground: Color, _ background: Color) -> Double {
        let foregroundLuminance = relativeLuminance(of: foreground)
        let backgroundLuminance = relativeLuminance(of: background)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(of color: Color) -> Double {
        let components = rgbComponents(for: color)
        let r = linearized(components.red)
        let g = linearized(components.green)
        let b = linearized(components.blue)
        return (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
    }

    private static func linearized(_ component: Double) -> Double {
        if component <= 0.03928 {
            return component / 12.92
        }
        return pow((component + 0.055) / 1.055, 2.4)
    }

    private static func rgbComponents(for color: Color) -> (red: Double, green: Double, blue: Double) {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (Double(red), Double(green), Double(blue))
        }

        var white: CGFloat = 0
        if uiColor.getWhite(&white, alpha: &alpha) {
            let value = Double(white)
            return (value, value, value)
        }

        return (0, 0, 0)
    }
}

private enum MapSheetRoute: Identifiable, Equatable {
    case todaySchedules
    case settings
    case stopArrivals(StopArrivalsPresentation)
    case routeDetail(BusDetailPresentation)
    case busDetail(BusDetailPresentation)

    var id: String {
        switch self {
        case .todaySchedules:
            return "todaySchedules"
        case .settings:
            return "settings"
        case .stopArrivals(let stop):
            return "stopArrivals:\(stop.id)"
        case .routeDetail(let detail):
            return "routeDetail:\(detail.id)"
        case .busDetail(let detail):
            return "busDetail:\(detail.id)"
        }
    }

    var isBusDetail: Bool {
        if case .busDetail = self {
            return true
        }
        return false
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var vm = BusMapViewModel()
    @StateObject private var locationService = LocationService()

    @State private var mapCamera = MapCameraPosition.automatic
    @State private var didCenterToUser = false
    @State private var tracePhase = 0
    @State private var activeSheet: MapSheetRoute?
    @State private var markerZoomScale = MarkerScalePolicy.default.initialScale
    @State private var mapCenterCoordinate: CLLocationCoordinate2D?
    @State private var mapCameraDistance: CLLocationDistance = 0
    @State private var freshnessReferenceDate = Date()

    private let markerScalePolicy = MarkerScalePolicy.default
    private let stopMarkerMaxVisibleDistance: CLLocationDistance = 5_500
    private let stopMarkerRadiusMeters: CLLocationDistance = 2_200
    private let stopMarkerMaxCount = 80
    private let recenterVisibilityThresholdMeters: CLLocationDistance = 75
    private let traceTimer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()
    private let freshnessTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

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
                            .stroke(Color.white.opacity(0.92), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))

                        MapPolyline(coordinates: vm.selectedRouteShape)
                            .stroke(selectedRouteColor.opacity(0.9), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

                        ForEach(traceArrowPoints()) { point in
                            Annotation("", coordinate: point.coord) {
                                Image(systemName: "arrow.forward.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(selectedRouteTextColor, selectedRouteColor)
                                    .rotationEffect(.degrees(point.angle))
                                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                            }
                        }
                    }

                    ForEach(visibleStopAnnotations) { stop in
                        Annotation(stop.name, coordinate: stop.coord) {
                            StopMarkerView(name: stop.name) {
                                if let arrivals = vm.stopArrivals(for: stop.id) {
                                    activeSheet = .stopArrivals(arrivals)
                                }
                            }
                        }
                    }

                    ForEach(vm.displayedVehicles) { vehicle in
                        Annotation(vehicle.route ?? "Bus", coordinate: vehicle.coord) {
                            BusMarkerView(
                                title: markerText(for: vehicle),
                                heading: vehicle.heading,
                                fillColor: markerFillColor(for: vehicle),
                                strokeColor: markerStrokeColor(for: vehicle),
                                glyphColor: markerGlyphColor(for: vehicle),
                                labelTextColor: markerLabelTextColor(for: vehicle),
                                labelBackgroundColor: markerLabelBackgroundColor(for: vehicle),
                                opacity: vm.busLayerOpacity * markerOpacityMultiplier(for: vehicle),
                                scale: markerScale(for: vehicle),
                                scaleAnimationDuration: markerScalePolicy.animationDuration
                            ) {
                                vm.selectBus(vehicle)
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .onMapCameraChange { context in
                    mapCenterCoordinate = context.camera.centerCoordinate
                    mapCameraDistance = context.camera.distance
                    updateMarkerScale(for: context.camera.distance)
                }
                .ignoresSafeArea()

                VStack(spacing: 10) {
                    nextArrivalGlanceCard

                    HStack(alignment: .center, spacing: 10) {
                        Spacer()
                        if shouldShowLocateMeButton {
                            locateMeButton
                                .transition(.scale(scale: 0.92).combined(with: .opacity))
                        }
                        refreshButton
                    }
                    .animation(.easeInOut(duration: 0.2), value: shouldShowLocateMeButton)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
            .navigationTitle("STM Bus Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .settings
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
        .onReceive(freshnessTimer) { now in
            freshnessReferenceDate = now
        }
        .onChange(of: vm.selectedBusDetail) { _, detail in
            syncBusDetailSheet(with: detail)
        }
        .sheet(item: activeSheetBinding) { route in
            sheetView(for: route)
        }
    }

    private var activeSheetBinding: Binding<MapSheetRoute?> {
        Binding(
            get: { activeSheet },
            set: { next in
                if next == nil, activeSheet?.isBusDetail == true {
                    vm.dismissBusDetail()
                }
                activeSheet = next
            }
        )
    }

    @ViewBuilder
    private func sheetView(for route: MapSheetRoute) -> some View {
        switch route {
        case .todaySchedules:
            todaySchedulesSheet
                .presentationDetents([.medium, .large])
        case .settings:
            settingsSheet
                .presentationDetents([.medium, .large])
        case .stopArrivals(let stopArrivals):
            stopArrivalsSheet(for: stopArrivals)
                .presentationDetents([.fraction(0.25), .medium, .large])
        case .routeDetail(let detail):
            busDetailSheet(for: detail)
                .presentationDetents([.medium, .large])
        case .busDetail(let detail):
            busDetailSheet(for: detail)
                .presentationDetents([.medium, .large])
        }
    }

    private func presentTodaySchedules() {
        vm.refreshSuggestionsForCurrentState()
        activeSheet = .todaySchedules
    }

    private func syncBusDetailSheet(with detail: BusDetailPresentation?) {
        guard let detail else {
            if activeSheet?.isBusDetail == true {
                activeSheet = nil
            }
            return
        }

        if activeSheet == nil || activeSheet?.isBusDetail == true {
            activeSheet = .busDetail(detail)
        }
    }

    private var nextArrivalGlanceCard: some View {
        Button {
            presentTodaySchedules()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next Bus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if let glance = vm.nextBusGlance {
                        Text("\(glance.route) \(glance.directionText)")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(routeColor(for: glance.route))
                            .lineLimit(1)
                        Text(nextBusSupplementalLine(for: glance))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Finding nearby arrivals...")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("Live ETA will appear here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                VStack(spacing: 0) {
                    if let etaMinutes = vm.nextBusGlance?.etaMinutes {
                        Text("\(etaMinutes)")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(routeColor(for: vm.nextBusGlance?.route))
                            .lineLimit(1)
                        Text("min")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("--")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("ETA")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 56)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(nextBusAccessibilityLabel())
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

    private var visibleStopAnnotations: [MapStopPresentation] {
        guard mapCameraDistance > 0, mapCameraDistance <= stopMarkerMaxVisibleDistance else { return [] }
        let center = mapCenterCoordinate ?? locationService.location
        return vm.visibleStops(
            around: center,
            maxDistanceMeters: stopMarkerRadiusMeters,
            maxCount: stopMarkerMaxCount
        )
    }

    private var shouldShowLocateMeButton: Bool {
        guard let userLocation = locationService.location else { return false }
        guard let mapCenterCoordinate else { return false }
        let userPoint = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let centerPoint = CLLocation(latitude: mapCenterCoordinate.latitude, longitude: mapCenterCoordinate.longitude)
        return centerPoint.distance(from: userPoint) > recenterVisibilityThresholdMeters
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
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go to current location")
        .disabled(locationService.location == nil)
    }

    private func stopArrivalsSheet(for presentation: StopArrivalsPresentation) -> some View {
        NavigationStack {
            List {
                Section {
                    Text("Tap a route to view the full stop sequence and ETAs.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if presentation.arrivals.isEmpty {
                    Section {
                        Text("No arrivals available for this stop.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Next Arrivals") {
                        ForEach(presentation.arrivals) { arrival in
                            Button {
                                openRouteDetailFromStop(arrival)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(arrival.route) \(arrival.directionText)")
                                            .font(.headline)
                                        Text(arrival.source.rawValue)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(sourceColor(arrival.source))
                                    }
                                    Spacer()
                                    Text(arrival.arrivalText ?? "--")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(presentation.stopName)
            .navigationBarTitleDisplayMode(.inline)
        }
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
                        activeSheet = nil
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
                                    .foregroundStyle(sourceColor(row.source))
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
                        if vm.selectedBusDetail?.id == detail.id {
                            vm.dismissBusDetail()
                        }
                        activeSheet = nil
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

    private func nextBusSupplementalLine(for glance: NextBusGlance) -> String {
        var chunks: [String] = []
        if let stop = glance.nearestStopName, !stop.isEmpty {
            chunks.append(stop)
        }
        if let metersAway = glance.metersAway {
            chunks.append("\(metersAway)m away")
        }
        if chunks.isEmpty {
            return "Tap for full arrivals"
        }
        return chunks.joined(separator: " • ")
    }

    private func nextBusAccessibilityLabel() -> String {
        guard let glance = vm.nextBusGlance else {
            return "Next bus ETA loading"
        }

        if let eta = glance.etaMinutes {
            return "Next bus route \(glance.route), \(glance.directionText), arriving in \(eta) minutes"
        }
        return "Next bus route \(glance.route), \(glance.directionText), ETA unavailable"
    }

    private func openRouteDetailFromStop(_ arrival: StopArrivalPresentation) {
        guard let detail = vm.routeDetail(route: arrival.route, directionID: arrival.directionID) else { return }
        activeSheet = .routeDetail(detail)
    }

    private func markerScale(for vehicle: VehiclePosition) -> CGFloat {
        markerScalePolicy.composedScale(
            baseScale: markerZoomScale,
            isSelected: vm.selectedBusID == vehicle.id
        )
    }

    private var selectedRouteColor: Color {
        routeColor(for: vm.selectedRouteID)
    }

    private var selectedRouteTextColor: Color {
        let preferred = routeTextColor(for: vm.selectedRouteID)
        return ContrastAccessibility.readableTextColor(preferred: preferred, on: selectedRouteColor)
    }

    private func routeColor(for routeID: String?) -> Color {
        TransitColorResolver.routeColor(style: vm.routeStyle(for: routeID))
    }

    private func routeTextColor(for routeID: String?) -> Color {
        TransitColorResolver.routeTextColor(style: vm.routeStyle(for: routeID))
    }

    private func sourceColor(_ source: StopTimeSourceLabel) -> Color {
        switch source {
        case .live:
            return TransitSemanticPalette.liveSource
        case .scheduled:
            return TransitSemanticPalette.scheduledSource
        }
    }

    private func markerFillColor(for vehicle: VehiclePosition) -> Color {
        let routeColor = routeColor(for: vehicle.route)
        switch vm.freshnessLevel(for: vehicle, referenceDate: freshnessReferenceDate) {
        case .live:
            return routeColor.opacity(0.94)
        case .aging:
            return routeColor.opacity(0.78)
        case .stale:
            return routeColor.opacity(0.58)
        }
    }

    private func markerStrokeColor(for vehicle: VehiclePosition) -> Color {
        switch vm.freshnessLevel(for: vehicle, referenceDate: freshnessReferenceDate) {
        case .live:
            return TransitSemanticPalette.liveFreshness
        case .aging:
            return TransitSemanticPalette.agingFreshness
        case .stale:
            return TransitSemanticPalette.staleFreshness
        }
    }

    private func markerGlyphColor(for vehicle: VehiclePosition) -> Color {
        let preferred = routeTextColor(for: vehicle.route)
        return ContrastAccessibility.readableTextColor(
            preferred: preferred,
            on: markerFillColor(for: vehicle)
        )
    }

    private func markerLabelTextColor(for vehicle: VehiclePosition) -> Color {
        let preferred = routeTextColor(for: vehicle.route)
        return ContrastAccessibility.readableTextColor(
            preferred: preferred,
            on: markerLabelBackgroundColor(for: vehicle)
        )
    }

    private func markerLabelBackgroundColor(for vehicle: VehiclePosition) -> Color {
        let routeColor = routeColor(for: vehicle.route)
        switch vm.freshnessLevel(for: vehicle, referenceDate: freshnessReferenceDate) {
        case .live:
            return routeColor.opacity(0.94)
        case .aging:
            return routeColor.opacity(0.78)
        case .stale:
            return routeColor.opacity(0.62)
        }
    }

    private func markerOpacityMultiplier(for vehicle: VehiclePosition) -> Double {
        switch vm.freshnessLevel(for: vehicle, referenceDate: freshnessReferenceDate) {
        case .live:
            return 1.0
        case .aging:
            return 0.8
        case .stale:
            return 0.62
        }
    }

    private func updateMarkerScale(for distance: CLLocationDistance) {
        let nextScale = markerScalePolicy.scale(forAltitude: distance)
        guard markerScalePolicy.shouldApplyScale(current: markerZoomScale, next: nextScale) else { return }
        markerZoomScale = nextScale
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
