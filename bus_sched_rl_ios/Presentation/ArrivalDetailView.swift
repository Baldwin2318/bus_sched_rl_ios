import SwiftUI

struct ArrivalDetailModel: Equatable {
    let routeShortName: String
    let routeLongName: String
    let directionText: String
    let stopName: String
    let sourceTitle: String
    let sourceDescription: String
    let etaText: String
    let arrivalTimeText: String
    let distanceText: String?
    let statusText: String?
    let delayText: String?
    let assignedStopText: String?
    let occupancyText: String?
    let congestionText: String?
    let freshnessText: String?

    init(
        card: NearbyETACard,
        vehicle: VehiclePosition?,
        vehicleRender: RenderedVehiclePosition?,
        tripUpdate: TripUpdatePayload?,
        assignedStopName: String?
    ) {
        routeShortName = card.routeShortName
        routeLongName = card.routeLongName
        directionText = card.directionText
        stopName = card.stopName
        arrivalTimeText = card.arrivalTime?.formatted(date: .omitted, time: .shortened) ?? "No time available"
        if let etaMinutes = card.etaMinutes {
            etaText = "\(etaMinutes) min"
        } else {
            etaText = "ETA unavailable"
        }

        switch card.source {
        case .live:
            sourceTitle = "Live ETA"
            switch vehicleRender?.freshness {
            case .aging:
                sourceDescription = "This arrival time is live, but the latest vehicle update is aging."
            case .stale:
                sourceDescription = "This arrival time is live, but the vehicle position may be stale."
            case .none, .some(.fresh):
                sourceDescription = "This arrival time is coming from live trip updates."
            }
        case .estimated:
            sourceTitle = "Estimated ETA"
            sourceDescription = "This arrival time is estimated from the latest vehicle position."
        case .scheduled:
            sourceTitle = "Scheduled ETA"
            sourceDescription = "Live data is unavailable for this card, so the schedule is shown."
        }

        if let distanceMeters = card.distanceMeters {
            if distanceMeters < 1000 {
                distanceText = "\(distanceMeters)m"
            } else {
                distanceText = String(format: "%.1fkm", Double(distanceMeters) / 1000)
            }
        } else {
            distanceText = nil
        }

        statusText = vehicle?.currentStatus?.title

        let stopDelaySeconds = tripUpdate?.stopTimeUpdates.first(where: {
            ($0.assignedStopID ?? $0.stopID) == card.stopID || $0.stopID == card.stopID
        })?.delaySeconds
        let effectiveDelay = stopDelaySeconds ?? tripUpdate?.delaySeconds
        delayText = effectiveDelay.map(TransitText.delayText(seconds:))

        if let assignedStopName, assignedStopName != card.stopName {
            assignedStopText = assignedStopName
        } else {
            assignedStopText = nil
        }

        if let percentage = vehicle?.occupancyPercentage {
            occupancyText = "\(percentage)% occupied"
        } else {
            occupancyText = vehicle?.occupancyStatus?.title
        }
        congestionText = vehicle?.congestionLevel?.title
        freshnessText = vehicleRender?.freshness.title
    }
}

struct ArrivalDetailView: View {
    @ObservedObject var viewModel: NearbyETAViewModel
    @ObservedObject var locationService: LocationService
    let initialCard: NearbyETACard
    @State private var isDetailRefreshActive = false

    private var currentCard: NearbyETACard {
        viewModel.cardDetail(for: initialCard)
    }

    private var model: ArrivalDetailModel {
        ArrivalDetailModel(
            card: currentCard,
            vehicle: liveVehicle,
            vehicleRender: liveVehicleRender,
            tripUpdate: tripUpdate,
            assignedStopName: assignedStop?.name
        )
    }

    private var liveVehicleRender: RenderedVehiclePosition? {
        viewModel.liveVehicleRender(for: currentCard)
    }

    private var liveVehicle: VehiclePosition? {
        liveVehicleRender?.vehicle ?? viewModel.liveVehicle(for: currentCard)
    }

    private var tripUpdate: TripUpdatePayload? {
        viewModel.tripUpdate(for: currentCard)
    }

    private var assignedStop: BusStop? {
        viewModel.assignedStop(for: currentCard)
    }

    private var alerts: [ServiceAlert] {
        viewModel.alerts(for: currentCard)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ETACardView(card: currentCard)

                if !alerts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Warnings")
                            .font(.title3.weight(.semibold))
                        ForEach(alerts) { alert in
                            ServiceAlertView(alert: alert, compact: false)
                        }
                    }
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let liveMapModel = viewModel.arrivalLiveMapModel(
                        for: currentCard,
                        userLocation: locationService.location,
                        referenceDate: context.date
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Live map")
                                .font(.title3.weight(.semibold))
                            Text("Shows your live location, this stop, and the live bus path. Only the bus refreshes every 10 seconds.")
                                .font(.subheadline)
                                .foregroundStyle(NearbyETATheme.secondaryText)
                            ArrivalLiveMapView(model: liveMapModel)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(NearbyETATheme.panel)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(NearbyETATheme.panelBorder, lineWidth: 1)
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(model.sourceTitle)
                        .font(.title3.weight(.semibold))
                    Text(model.etaText)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text(model.sourceDescription)
                        .font(.subheadline)
                        .foregroundStyle(NearbyETATheme.secondaryText)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(NearbyETATheme.panel)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(NearbyETATheme.panelBorder, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 12) {
                    detailRow(title: "Route", value: "\(model.routeShortName) \(model.routeLongName)")
                    detailRow(title: "Direction", value: model.directionText)
                    detailRow(title: "Stop", value: model.stopName)
                    if let statusText = model.statusText {
                        detailRow(title: "Bus status", value: statusText)
                    }
                    if let delayText = model.delayText {
                        detailRow(title: "Delay", value: delayText)
                    }
                    if let assignedStopText = model.assignedStopText {
                        detailRow(title: "Assigned stop", value: assignedStopText)
                    }
                    if let occupancyText = model.occupancyText {
                        detailRow(title: "Occupancy", value: occupancyText)
                    }
                    if let congestionText = model.congestionText {
                        detailRow(title: "Traffic", value: congestionText)
                    }
                    if let freshnessText = model.freshnessText {
                        detailRow(title: "Position freshness", value: freshnessText)
                    }
                    detailRow(title: "Arrival time", value: model.arrivalTimeText)
                    if let distanceText = model.distanceText {
                        detailRow(title: "Distance", value: distanceText)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(NearbyETATheme.panel)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(NearbyETATheme.panelBorder, lineWidth: 1)
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(NearbyETATheme.background.ignoresSafeArea())
        .navigationTitle("Arrival details")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("arrival-detail-screen")
        .onAppear {
            syncDetailRefreshState()
        }
        .onDisappear {
            if isDetailRefreshActive {
                viewModel.endDetailRefresh()
                isDetailRefreshActive = false
            }
        }
        .onChange(of: currentCard.source) { _, _ in
            syncDetailRefreshState()
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NearbyETATheme.secondaryText)
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func syncDetailRefreshState() {
        let shouldRefresh = currentCard.source == .live
        guard shouldRefresh != isDetailRefreshActive else { return }

        if shouldRefresh {
            viewModel.beginDetailRefresh()
        } else {
            viewModel.endDetailRefresh()
        }
        isDetailRefreshActive = shouldRefresh
    }
}
