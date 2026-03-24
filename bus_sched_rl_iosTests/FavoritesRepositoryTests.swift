import XCTest
@testable import bus_sched_rl_ios

final class FavoritesRepositoryTests: XCTestCase {
    func testRepositoryPersistsFavoritesInOrderWithoutDuplicates() {
        let suiteName = "FavoritesRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let repository = UserDefaultsFavoritesRepository(
            userDefaults: defaults,
            storageKey: "favorites"
        )
        let first = FavoriteArrivalID(routeID: "55", directionID: "0", stopID: "stop-1")
        let second = FavoriteArrivalID(routeID: "80", directionID: "1", stopID: "stop-9")

        repository.saveFavorites([first, second, first])

        let reloaded = UserDefaultsFavoritesRepository(
            userDefaults: defaults,
            storageKey: "favorites"
        )

        XCTAssertEqual(reloaded.loadFavorites(), [first, second])
    }

    func testRepositoryCanClearFavorites() {
        let suiteName = "FavoritesRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let repository = UserDefaultsFavoritesRepository(
            userDefaults: defaults,
            storageKey: "favorites"
        )
        repository.saveFavorites([
            FavoriteArrivalID(routeID: "55", directionID: "0", stopID: "stop-1")
        ])

        repository.saveFavorites([])

        XCTAssertTrue(repository.loadFavorites().isEmpty)
    }
}
