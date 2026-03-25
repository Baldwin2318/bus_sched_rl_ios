import Foundation

struct ETACardQuality: Equatable {
    let statusText: String?
    let freshness: VehicleFreshness?
    let delayText: String?

    var freshnessText: String? {
        freshness?.title
    }

    var isStale: Bool {
        freshness == .stale
    }
}
