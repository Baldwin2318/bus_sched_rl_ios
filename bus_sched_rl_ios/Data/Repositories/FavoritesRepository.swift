import Foundation

protocol FavoritesRepository {
    func loadFavorites() -> [FavoriteArrivalID]
    func saveFavorites(_ favorites: [FavoriteArrivalID])
}

final class UserDefaultsFavoritesRepository: FavoritesRepository {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "favorite_arrival_ids"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func loadFavorites() -> [FavoriteArrivalID] {
        guard let data = userDefaults.data(forKey: storageKey),
              let favorites = try? decoder.decode([FavoriteArrivalID].self, from: data) else {
            return []
        }

        var seen: Set<FavoriteArrivalID> = []
        return favorites.filter { seen.insert($0).inserted }
    }

    func saveFavorites(_ favorites: [FavoriteArrivalID]) {
        var seen: Set<FavoriteArrivalID> = []
        let deduped = favorites.filter { seen.insert($0).inserted }

        guard let data = try? encoder.encode(deduped) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
