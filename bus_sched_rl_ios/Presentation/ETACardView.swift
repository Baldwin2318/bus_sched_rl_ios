import SwiftUI

struct ETACardView: View {
    let card: NearbyETACard
    var showsDisclosureIndicator: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 8) {
                Text(card.routeShortName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(routeTextColor)
                    .frame(minWidth: 62)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(routeColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(card.source.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(routeColor)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(card.directionText)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(card.stopName)
                    .font(.subheadline)
                    .foregroundStyle(NearbyETATheme.secondaryText)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let distanceText {
                        Label(distanceText, systemImage: "location")
                            .labelStyle(.titleAndIcon)
                    }
                    Text(card.arrivalTime?.formatted(date: .omitted, time: .shortened) ?? "No time")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(NearbyETATheme.secondaryText)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                if let etaMinutes = card.etaMinutes {
                    Text("\(etaMinutes)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("min")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NearbyETATheme.secondaryText)
                } else {
                    Text("--")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("ETA")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NearbyETATheme.secondaryText)
                }
            }
            .frame(minWidth: 58)

            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(NearbyETATheme.secondaryText)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(NearbyETATheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(NearbyETATheme.panelBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel)
        .accessibilityIdentifier("arrival-card-\(card.id)")
    }

    private var routeColor: Color {
        Color(hex: card.routeStyle?.routeColorHex) ?? NearbyETATheme.accentFallback
    }

    private var routeTextColor: Color {
        Color(hex: card.routeStyle?.routeTextColorHex) ?? .white
    }

    private var distanceText: String? {
        guard let distanceMeters = card.distanceMeters else { return nil }
        if distanceMeters < 1000 {
            return "\(distanceMeters)m"
        }
        return String(format: "%.1fkm", Double(distanceMeters) / 1000)
    }
}
