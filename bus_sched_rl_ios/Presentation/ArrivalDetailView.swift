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

    init(card: NearbyETACard) {
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
            sourceDescription = "This arrival time is coming from live trip updates."
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
        ArrivalDetailModel(card: currentCard)
    }

    private var liveVehicle: VehiclePosition? {
        viewModel.liveVehicle(for: currentCard)
    }

    private var liveMapModel: ArrivalLiveMapModel? {
        viewModel.arrivalLiveMapModel(
            for: currentCard,
            userLocation: locationService.location
        )
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

                if let liveMapModel {
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
