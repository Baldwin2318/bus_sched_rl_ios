# Bus ETA (iOS)

`Bus ETA` is a SwiftUI iPhone app for checking STM bus arrivals with a schedule-first fallback model and live data when STM realtime feeds are available.

The app is built around a simple flow:
- load and cache STM GTFS static data locally
- poll STM realtime feeds for vehicles, trip updates, and service alerts
- compose nearby, route-scoped, or stop-scoped arrival cards
- show detail views with live vehicle context, route path rendering, and warning sheets

## Current Feature Set

- Nearby arrivals list powered by location when permission is granted
- Schedule-only fallback mode when location is unavailable or denied
- Search across the full indexed route and stop dataset
- Favorites for commonly used arrival cards
- Arrival detail screen with:
  - live / estimated / scheduled ETA source labeling
  - live bus map for supported arrivals
  - bus status, delay, assigned stop, occupancy, congestion, and freshness details
  - warning sheet for scoped service alerts
- STM service notice parsing and normalization
- GTFS-Realtime alert parsing
- Static GTFS cache persistence with metadata and stale-data prompting
- Background revalidation of cached GTFS data

## Data Sources

The app uses STM open data endpoints for:
- GTFS static schedules
- GTFS-Realtime vehicle positions
- GTFS-Realtime trip updates
- GTFS-Realtime service alerts
- STM service status / message notices

## Tech Stack

- Swift 5
- SwiftUI
- MapKit
- CoreLocation
- Swift Concurrency with `async` / `await`
- [SwiftProtobuf](https://github.com/apple/swift-protobuf) for GTFS-Realtime parsing
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) for GTFS archive extraction
- [GTFS](https://github.com/emma-k-alexandra/GTFS.git) package helpers

## App Behavior

### Home Screen

- Shows nearby arrivals when location is available
- Falls back to scheduled arrivals when location access is off
- Supports pull-to-refresh
- Shows search matches above the main arrival list
- Shows favorite cards in a dedicated section
- Shows static data update prompts when cached GTFS data is old
- Shows a generic live-data warning banner when realtime fetching fails

### Search

- Searches all indexed routes and stops from the static dataset
- Supports route number, route name, direction text, and stop name matching
- Selecting a search result switches the main list into route or stop scope

### Arrival Details

- Shows the selected ETA card at the top
- Shows a live map when there is a fresh enough rendered vehicle position
- Shows warning access in the navigation bar only when that arrival has active alerts
- Presents route/stop scoped warnings in a sheet

## Architecture Overview

### Presentation Layer

- [ContentView.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/ContentView.swift)
  Main list-based app shell, search UI, favorites section, refresh handling, and navigation.
- [NearbyETAViewModel.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/Presentation/NearbyETAViewModel.swift)
  Main application state, live polling, search scheduling, card rebuilding, and alert scoping.
- [ArrivalDetailView.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/Presentation/ArrivalDetailView.swift)
  Detail presentation for a selected arrival.
- [ArrivalLiveMapView.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/Presentation/ArrivalLiveMapView.swift)
  MapKit bridge for live arrival map rendering.
- [ETACardView.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/Presentation/ETACardView.swift)
  Shared ETA card UI.
- [WarningsSheetView.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/Presentation/WarningsSheetView.swift)
  Warning list sheet for arrival-scoped alerts.

### Domain Layer

- [BusModels.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/Domain/BusModels.swift)
  Core GTFS, realtime, card, and scope models.
- [AlertModels.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/Domain/AlertModels.swift)
  Service alert models and scope matching rules.
- [SearchModels.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/Domain/SearchModels.swift)
  Search result and index entry models.

### Data / Repository Layer

- [GTFSRepository.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/Data/Repositories/GTFSRepository.swift)
  Downloads, caches, parses, and revalidates GTFS static data.
- [RealtimeRepository.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/Data/Repositories/RealtimeRepository.swift)
  Fetches STM realtime feeds and parses vehicles, trip updates, alerts, and service status notices.
- [STMServiceStatusParser.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/Data/Repositories/STMServiceStatusParser.swift)
  Parses STM JSON service notices and extracts readable text and links from embedded HTML.
- [FavoritesRepository.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/Data/Repositories/FavoritesRepository.swift)
  Persists favorite arrivals.

### Supporting Presentation Logic

- [NearbyETAComposer.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/Presentation/NearbyETAComposer.swift)
  Builds ETA cards from static + realtime inputs.
- [SearchIndex.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/Presentation/SearchIndex.swift)
  Search indexing and ranking.
- [RoutePathResolver.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/Presentation/RoutePathResolver.swift)
  Chooses route path geometry for maps.
- [VehicleRenderState.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/Presentation/VehicleRenderState.swift)
  Interpolates and grades live vehicle freshness.
- [STMServiceAlertNormalizer.swift](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_ios/Presentation/STMServiceAlertNormalizer.swift)
  Normalizes STM notices into scoped service alerts aligned with card matching.

## Setup

1. Clone the repository.
2. Open `bus_sched_rl_ios.xcodeproj` in Xcode.
3. Copy `Config/Secrets.example.xcconfig` to a local config file used by your project setup.
4. Provide your STM API key.
5. Ensure the build injects `STMApiKey` into the app `Info.plist`.
6. Build and run on a simulator or device.

The example secret file is:

```xcconfig
STM_API_KEY = your_stm_api_key_here
```

The runtime configuration reader expects `STMApiKey` in the app bundle info dictionary.

## Build

Example simulator build:

```bash
xcodebuild build -project bus_sched_rl_ios.xcodeproj -scheme bus_sched_rl_ios -destination 'platform=iOS Simulator,id=3EA34D8D-39B9-453F-BD65-68CEEF230425'
```

If your machine uses a different simulator, replace the destination with one installed locally.

## Tests

The repository includes unit tests under [bus_sched_rl_iosTests](/Users/baldwinkielmalabanan/writable_projs_for_codex/bus_sched_rl_ios/bus_sched_rl_iosTests), including coverage for:
- search indexing
- ETA composition
- arrival detail modeling
- route path resolution
- vehicle render state
- STM service alert normalization
- STM service status parsing

Note: the current shared Xcode scheme is not configured with a runnable test action, so `xcodebuild test` may require scheme/project updates before it works from the command line.

## Repository Layout

- `bus_sched_rl_ios/`
  App source
- `bus_sched_rl_iosTests/`
  Unit tests
- `Config/`
  Build configuration and secrets template
- `SCREENSHOTS/`
  App screenshots

## Limitations and Notes

- Realtime trip updates and service alerts are treated as optional inputs; the app keeps working with reduced fidelity when some feeds fail.
- Vehicle feed failure triggers the generic banner: `Live arrivals are temporarily unavailable.`
- Search results can be large because they now cover the full indexed dataset.
- This app is not affiliated with or endorsed by STM.

## Data Attribution

Transit data is provided by Societe de transport de Montreal (STM) through its open data services.

- Developer portal: [https://www.stm.info/en/about/developers](https://www.stm.info/en/about/developers)

Use the data according to STM’s licensing and attribution requirements.
