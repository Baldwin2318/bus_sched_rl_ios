import SwiftUI

struct WarningsSheetView: View {
    let alerts: [ServiceAlert]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                NearbyETATheme.background.ignoresSafeArea()

                if alerts.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No warnings right now")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("STM notices and realtime service warnings will appear here when they are active.")
                            .font(.subheadline)
                            .foregroundStyle(NearbyETATheme.secondaryText)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(NearbyETATheme.panel)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(NearbyETATheme.panelBorder, lineWidth: 1)
                    )
                    .padding(20)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(alerts) { alert in
                                ServiceAlertView(alert: alert, compact: false)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("Warnings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .accessibilityIdentifier("warnings-sheet")
    }
}
