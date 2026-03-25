import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroSection

                    aboutSection(
                        title: "What",
                        icon: "🚌",
                        body: "Bus ETA is a simple app that helps you quickly check bus arrival times, see where a live bus is on the map, and keep track of your favorite trips without digging through a bigger transit app."
                    )

                    aboutSection(
                        title: "Why",
                        icon: "💡",
                        body: "This app started as an experiment using STM's open transit data during the 2025 STM worker strike. It also came from a personal reason: making it easier for my girlfriend to check her bus after work in a fast, friendly way."
                    )

                    aboutSection(
                        title: "When",
                        icon: "🗓️",
                        body: "The app was first created around mid-2025, and the source code was later committed in early 2026."
                    )

                    aboutSection(
                        title: "How",
                        icon: "⚙️",
                        body: "In simple terms, the app downloads STM transit schedules, combines them with live bus updates when available, and turns that data into easy-to-read arrival cards, maps, favorites, and service warnings. It is built so scheduled times still help even when live data or location access is not available."
                    )

                    creditSection
                }
                .padding(20)
            }
            .background(NearbyETATheme.background.ignoresSafeArea())
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bus ETA")
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.bold)
            Text("A friendly STM bus helper for quick arrivals, live bus tracking, and easier after-work transit checks.")
                .font(.subheadline)
                .foregroundStyle(NearbyETATheme.secondaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(NearbyETATheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(NearbyETATheme.panelBorder, lineWidth: 1)
        )
    }

    private var creditSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Credit")
                .font(.headline)
            Text("Transit data © STM (Société de transport de Montréal)")
                .font(.subheadline)
                .foregroundStyle(NearbyETATheme.secondaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(NearbyETATheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(NearbyETATheme.panelBorder, lineWidth: 1)
        )
    }

    private func aboutSection(title: String, icon: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(icon)  \(title)")
                .font(.headline)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(NearbyETATheme.secondaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(NearbyETATheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(NearbyETATheme.panelBorder, lineWidth: 1)
        )
    }
}
