import SwiftUI

struct ServiceAlertView: View {
    let alert: ServiceAlert
    var compact: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(iconTint)
                    .font(.headline.weight(.semibold))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(alert.severity.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(iconTint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(iconTint.opacity(0.12), in: Capsule())

                        Text(alert.scopeSummary)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NearbyETATheme.secondaryText)
                    }

                    Text(alert.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if alert.effectText != nil || alert.causeText != nil {
                        HStack(spacing: 8) {
                            if let effectText = alert.effectText {
                                alertTag(effectText, tint: iconTint)
                            }
                            if let causeText = alert.causeText {
                                alertTag(causeText, tint: NearbyETATheme.secondaryText)
                            }
                        }
                    }

                    if let message = alert.message, !message.isEmpty {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(NearbyETATheme.secondaryText)
                            .lineLimit(compact ? 3 : nil)
                    }
                }

                Spacer(minLength: 0)
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
                .stroke(iconTint.opacity(0.28), lineWidth: 1)
        )
    }

    private func alertTag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private var iconName: String {
        switch alert.severity {
        case .severe:
            return "exclamationmark.octagon.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    private var iconTint: Color {
        switch alert.severity {
        case .severe:
            return .red
        case .warning:
            return .orange
        case .info:
            return NearbyETATheme.accentFallback
        }
    }
}
