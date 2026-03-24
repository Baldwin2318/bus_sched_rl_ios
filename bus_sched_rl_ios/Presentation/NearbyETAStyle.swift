import SwiftUI

enum NearbyETATheme {
    static let background = Color(.systemBackground)
    static let panel = Color(.secondarySystemBackground)
    static let panelBorder = Color(.separator)
    static let secondaryText = Color(.secondaryLabel)
    static let accentFallback = Color(red: 0.12, green: 0.34, blue: 0.68)
    static let skeletonBase = Color(.systemGray5)
    static let skeletonHighlight = Color.white.opacity(0.42)
}

func routeChipColor(hex: String?) -> Color {
    Color(hex: hex) ?? NearbyETATheme.accentFallback
}

extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let normalized = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
        guard normalized.count == 6, let value = Int(normalized, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
