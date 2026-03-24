import Foundation

struct FavoriteArrivalID: Codable, Hashable, Identifiable {
    let routeID: String
    let directionID: String
    let stopID: String

    init(routeID: String, directionID: String, stopID: String) {
        self.routeID = routeID
        self.directionID = directionID
        self.stopID = stopID
    }

    init(card: NearbyETACard) {
        self.init(
            routeID: card.routeID,
            directionID: card.directionID,
            stopID: card.stopID
        )
    }

    var id: String {
        "\(routeID):\(directionID):\(stopID)"
    }
}
