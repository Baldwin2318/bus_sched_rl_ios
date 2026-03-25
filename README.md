# STM Bus Tracker (iOS)

Real-time STM bus tracking app built with SwiftUI and MapKit.

The app combines:
- GTFS static data (routes, stop sequences, schedules)
- GTFS-Realtime vehicle positions
- GTFS-Realtime trip updates (when available)

## What It Does

- Shows live bus markers on the map with route-aware styling.
- Polls live vehicle positions automatically while the app is active.
- Lets users pause/resume live polling from the map UI.
- Animates bus movement between updates for smoother motion.
- Displays a "Next Bus" glance card and nearby arrivals.
- Supports fallback from live ETAs to scheduled times when needed.
- Highlights route traces and shows stop-level details in sheets.
- Provides first-launch location onboarding and in-app help tips.
- Caches GTFS static data locally for faster subsequent launches.
- Includes GTFS cache metadata, staleness status, and manual update in Settings.

## Tech Stack

- Swift 5
- SwiftUI + MapKit
- Swift Concurrency (`async/await`, `Task`)
- SwiftProtobuf (GTFS-Realtime parsing)
- ZIPFoundation (GTFS zip extraction)
- GTFS package (static feed helpers)

## Requirements

- macOS with Xcode 17+
- iOS deployment target: 18.2

## Setup

1. Clone the repository.
2. Open `bus_sched_rl_ios.xcodeproj` in Xcode.
3. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.local.xcconfig`.
4. Put your STM key in `STM_API_KEY` inside `Config/Secrets.local.xcconfig`.
5. Select the `bus_sched_rl_ios` scheme.
6. Build and run on simulator or device.

`Config/Secrets.local.xcconfig` is ignored by Git and should not be committed.

## Build and Test

Build:

```bash
xcodebuild -project bus_sched_rl_ios.xcodeproj -scheme bus_sched_rl_ios -destination 'generic/platform=iOS' build
```

Run tests:

```bash
xcodebuild test -project bus_sched_rl_ios.xcodeproj -scheme bus_sched_rl_ios -destination 'platform=iOS Simulator,name=iPhone 16'
```

Note: update the simulator destination to one installed on your machine.

## Project Structure

- `bus_sched_rl_ios/ContentView.swift`  
  Main map UI, sheets, onboarding overlays, settings/help/about screens.
- `bus_sched_rl_ios/Presentation/BusMapViewModel.swift`  
  App state, live polling loop, route/ETA presentation, refresh logic.
- `bus_sched_rl_ios/Presentation/LocationService.swift`  
  Location permission and location updates.
- `bus_sched_rl_ios/Data/Repositories/GTFSRepository.swift`  
  GTFS static fetch/parse/cache and metadata handling.
- `bus_sched_rl_ios/Data/Repositories/RealtimeRepository.swift`  
  GTFS-Realtime vehicle and trip updates fetch/parse.
- `bus_sched_rl_iosTests/`  
  Unit tests for polling behavior, interpolation, marker scaling, route resolution, and UX contracts.

## Data Attribution and Legal

Transit data is provided by the Societe de transport de Montreal (STM) under Creative Commons Attribution 4.0 (CC-BY) licence.

Developer portal:
- https://stm.info/en/about/developers

Disclaimer:
- Schedule and position data is for informational purposes only.
- This app is not affiliated with or endorsed by the STM.
