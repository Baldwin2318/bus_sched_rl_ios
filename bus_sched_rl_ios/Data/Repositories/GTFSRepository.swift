import Foundation
import CoreLocation
import ZIPFoundation

struct GTFSStaticData {
    let routeShapes: [String: [String: [CLLocationCoordinate2D]]]
    let routeStops: [RouteKey: [BusStop]]
    let routeStopSchedules: [RouteKey: [RouteStopSchedule]]
    let shapeCoordinatesByID: [String: [CLLocationCoordinate2D]]
    let routeShapeIDsByKey: [RouteKey: [String]]
    let routeDirectionLabels: [RouteKey: String]
    let routeNamesByRouteID: [String: GTFSRouteName]
    let routeStylesByRouteID: [String: GTFSRouteStyle]
    let feedInfo: GTFSFeedInfo?

    var availableRoutes: [String] {
        routeShapes.keys.sorted()
    }
}

protocol GTFSRepository {
    func loadStaticData() async throws -> GTFSStaticData
    func refreshStaticData(force: Bool) async throws -> GTFSStaticData
    func cacheMetadata() async -> GTFSCacheMetadata
}

private struct TripsParseResult {
    let routeToShapeIDs: [RouteKey: Set<String>]
    let representativeTripByRoute: [RouteKey: String]
    let routeByTripID: [String: RouteKey]
    let directionLabelByRoute: [RouteKey: String]
}

private enum GTFSParsers {
    struct RouteCatalogParseResult {
        let stylesByRouteID: [String: GTFSRouteStyle]
        let namesByRouteID: [String: GTFSRouteName]

        static let empty = RouteCatalogParseResult(stylesByRouteID: [:], namesByRouteID: [:])
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func headerIndexMap(_ headerLine: String) -> [String: Int] {
        guard let cols = try? CSVParser.parseLine(headerLine) else { return [:] }
        var result: [String: Int] = [:]
        for (idx, col) in cols.enumerated() {
            result[normalize(col)] = idx
        }
        return result
    }

    private static func extractDirectionLabel(from headsign: String, fallback directionID: String) -> String {
        let cleaned = normalize(headsign)
        let french = ["Nord", "Sud", "Est", "Ouest"]
        if let firstWord = cleaned.split(separator: " ").first {
            let token = String(firstWord)
            if french.contains(token) { return token }
        }
        if !cleaned.isEmpty { return cleaned }
        return directionID == "0" ? "Direction 0" : directionID == "1" ? "Direction 1" : "Direction \(directionID)"
    }

    static func parseTrips(_ text: String) -> TripsParseResult {
        var routeToShapeIDs: [RouteKey: Set<String>] = [:]
        var representativeTripByRoute: [RouteKey: String] = [:]
        var routeByTripID: [String: RouteKey] = [:]
        var directionLabelByRoute: [RouteKey: String] = [:]

        var isHeader = true
        var header: [String: Int] = [:]
        text.enumerateLines { line, _ in
            if isHeader {
                isHeader = false
                header = headerIndexMap(line)
                return
            }
            guard !line.isEmpty, let cols = try? CSVParser.parseLine(line) else { return }
            guard let routeIdx = header["route_id"],
                  let tripIdx = header["trip_id"],
                  let directionIdx = header["direction_id"],
                  let shapeIdx = header["shape_id"],
                  routeIdx < cols.count,
                  tripIdx < cols.count,
                  directionIdx < cols.count,
                  shapeIdx < cols.count else { return }

            let routeID = normalize(cols[routeIdx])
            let tripID = normalize(cols[tripIdx])
            let directionID = normalize(cols[directionIdx]).isEmpty ? "0" : normalize(cols[directionIdx])
            let shapeID = normalize(cols[shapeIdx])
            if routeID.isEmpty || tripID.isEmpty || shapeID.isEmpty { return }
            let routeKey = RouteKey(route: routeID, direction: directionID)

            routeToShapeIDs[routeKey, default: []].insert(shapeID)
            routeByTripID[tripID] = routeKey
            if representativeTripByRoute[routeKey] == nil {
                representativeTripByRoute[routeKey] = tripID
            }
            if directionLabelByRoute[routeKey] == nil {
                let headsign: String
                if let headsignIdx = header["trip_headsign"], headsignIdx < cols.count {
                    headsign = cols[headsignIdx]
                } else {
                    headsign = ""
                }
                directionLabelByRoute[routeKey] = extractDirectionLabel(from: headsign, fallback: directionID)
            }
        }

        return TripsParseResult(
            routeToShapeIDs: routeToShapeIDs,
            representativeTripByRoute: representativeTripByRoute,
            routeByTripID: routeByTripID,
            directionLabelByRoute: directionLabelByRoute
        )
    }

    static func parseShapes(_ text: String) -> [String: [(seq: Int, lat: Double, lon: Double)]] {
        var shapesByID: [String: [(seq: Int, lat: Double, lon: Double)]] = [:]
        var isHeader = true
        var header: [String: Int] = [:]

        text.enumerateLines { line, _ in
            if isHeader {
                isHeader = false
                header = headerIndexMap(line)
                return
            }
            guard !line.isEmpty, let cols = try? CSVParser.parseLine(line) else { return }
            guard let shapeIdx = header["shape_id"],
                  let latIdx = header["shape_pt_lat"],
                  let lonIdx = header["shape_pt_lon"],
                  let seqIdx = header["shape_pt_sequence"],
                  shapeIdx < cols.count,
                  latIdx < cols.count,
                  lonIdx < cols.count,
                  seqIdx < cols.count,
                  let lat = Double(cols[latIdx]),
                  let lon = Double(cols[lonIdx]),
                  let seq = Int(cols[seqIdx]) else { return }

            let shapeID = normalize(cols[shapeIdx])
            if shapeID.isEmpty { return }
            shapesByID[shapeID, default: []].append((seq, lat, lon))
        }

        return shapesByID
    }

    static func parseStops(_ text: String) -> [String: BusStop] {
        var stopsByID: [String: BusStop] = [:]
        var isHeader = true
        var header: [String: Int] = [:]

        text.enumerateLines { line, _ in
            if isHeader {
                isHeader = false
                header = headerIndexMap(line)
                return
            }
            guard !line.isEmpty, let cols = try? CSVParser.parseLine(line) else { return }
            guard let idIdx = header["stop_id"],
                  let nameIdx = header["stop_name"],
                  let latIdx = header["stop_lat"],
                  let lonIdx = header["stop_lon"],
                  idIdx < cols.count,
                  nameIdx < cols.count,
                  latIdx < cols.count,
                  lonIdx < cols.count,
                  let lat = Double(cols[latIdx]),
                  let lon = Double(cols[lonIdx]) else { return }
            let stopID = normalize(cols[idIdx])
            if stopID.isEmpty { return }

            let stop = BusStop(
                id: stopID,
                name: normalize(cols[nameIdx]),
                coord: CLLocationCoordinate2D(latitude: lat, longitude: lon)
            )
            stopsByID[stopID] = stop
        }

        return stopsByID
    }

    private static func normalizedColorHex(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = normalize(value).replacingOccurrences(of: "#", with: "").uppercased()
        guard trimmed.count == 6 else { return nil }
        let hexCharacters = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard trimmed.unicodeScalars.allSatisfy(hexCharacters.contains) else { return nil }
        return trimmed
    }

    static func parseRouteCatalog(_ text: String) -> RouteCatalogParseResult {
        var stylesByRouteID: [String: GTFSRouteStyle] = [:]
        var namesByRouteID: [String: GTFSRouteName] = [:]
        var isHeader = true
        var header: [String: Int] = [:]

        text.enumerateLines { line, _ in
            if isHeader {
                isHeader = false
                header = headerIndexMap(line)
                return
            }
            guard !line.isEmpty, let cols = try? CSVParser.parseLine(line) else { return }
            guard let routeIDIdx = header["route_id"], routeIDIdx < cols.count else { return }

            let routeID = normalize(cols[routeIDIdx])
            guard !routeID.isEmpty else { return }

            let shortName: String
            if let shortNameIdx = header["route_short_name"], shortNameIdx < cols.count {
                shortName = normalize(cols[shortNameIdx])
            } else {
                shortName = ""
            }

            let longName: String
            if let longNameIdx = header["route_long_name"], longNameIdx < cols.count {
                longName = normalize(cols[longNameIdx])
            } else {
                longName = ""
            }

            let resolvedShortName = shortName.isEmpty ? routeID : shortName
            let resolvedLongName = longName.isEmpty ? resolvedShortName : longName
            namesByRouteID[routeID] = GTFSRouteName(
                shortName: resolvedShortName,
                longName: resolvedLongName
            )

            let routeColorHex: String?
            if let routeColorIdx = header["route_color"], routeColorIdx < cols.count {
                routeColorHex = normalizedColorHex(cols[routeColorIdx])
            } else {
                routeColorHex = nil
            }

            let routeTextColorHex: String?
            if let routeTextColorIdx = header["route_text_color"], routeTextColorIdx < cols.count {
                routeTextColorHex = normalizedColorHex(cols[routeTextColorIdx])
            } else {
                routeTextColorHex = nil
            }

            guard routeColorHex != nil || routeTextColorHex != nil else { return }
            stylesByRouteID[routeID] = GTFSRouteStyle(
                routeColorHex: routeColorHex,
                routeTextColorHex: routeTextColorHex
            )
        }

        return RouteCatalogParseResult(
            stylesByRouteID: stylesByRouteID,
            namesByRouteID: namesByRouteID
        )
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = normalize(value)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func parseRouteStopSchedules(
        stopTimesText: String,
        representativeTripByRoute: [RouteKey: String],
        routeByTripID: [String: RouteKey],
        stopsByID: [String: BusStop]
    ) -> [RouteKey: [RouteStopSchedule]] {
        let selectedTripIDs = Set(representativeTripByRoute.values)
        var routeStopRows: [RouteKey: [(sequence: Int, stop: BusStop, arrival: String?, departure: String?)]] = [:]

        var isHeader = true
        var header: [String: Int] = [:]
        stopTimesText.enumerateLines { line, _ in
            if isHeader {
                isHeader = false
                header = headerIndexMap(line)
                return
            }
            guard !line.isEmpty, let cols = try? CSVParser.parseLine(line) else { return }
            guard let tripIdx = header["trip_id"],
                  let stopIdx = header["stop_id"],
                  let seqIdx = header["stop_sequence"],
                  tripIdx < cols.count,
                  stopIdx < cols.count,
                  seqIdx < cols.count else { return }
            let tripID = normalize(cols[tripIdx])
            guard selectedTripIDs.contains(tripID),
                  let routeKey = routeByTripID[tripID],
                  let stop = stopsByID[normalize(cols[stopIdx])],
                  let seq = Int(cols[seqIdx]) else { return }

            let arrival: String?
            if let arrivalIdx = header["arrival_time"], arrivalIdx < cols.count {
                arrival = normalizedOptional(cols[arrivalIdx])
            } else {
                arrival = nil
            }

            let departure: String?
            if let departureIdx = header["departure_time"], departureIdx < cols.count {
                departure = normalizedOptional(cols[departureIdx])
            } else {
                departure = nil
            }

            routeStopRows[routeKey, default: []].append((seq, stop, arrival, departure))
        }

        var routeStops: [RouteKey: [RouteStopSchedule]] = [:]
        for (routeKey, rows) in routeStopRows {
            let ordered = rows.sorted { $0.sequence < $1.sequence }
            var seen: Set<String> = []
            routeStops[routeKey] = ordered.compactMap { row in
                if seen.contains(row.stop.id) { return nil }
                seen.insert(row.stop.id)
                return RouteStopSchedule(
                    stop: row.stop,
                    sequence: row.sequence,
                    scheduledArrival: row.arrival,
                    scheduledDeparture: row.departure
                )
            }
        }

        return routeStops
    }

    static func parseFeedInfo(_ text: String) -> GTFSFeedInfo? {
        var isHeader = true
        var header: [String: Int] = [:]
        var parsed: GTFSFeedInfo?

        text.enumerateLines { line, stop in
            if parsed != nil {
                stop = true
                return
            }
            if isHeader {
                isHeader = false
                header = headerIndexMap(line)
                return
            }
            guard !line.isEmpty, let cols = try? CSVParser.parseLine(line) else { return }

            let feedVersion: String?
            if let versionIdx = header["feed_version"], versionIdx < cols.count {
                feedVersion = normalizedOptional(cols[versionIdx])
            } else {
                feedVersion = nil
            }

            let feedStartDate: Date?
            if let startIdx = header["feed_start_date"], startIdx < cols.count {
                feedStartDate = parseFeedDate(cols[startIdx])
            } else {
                feedStartDate = nil
            }

            let feedEndDate: Date?
            if let endIdx = header["feed_end_date"], endIdx < cols.count {
                feedEndDate = parseFeedDate(cols[endIdx])
            } else {
                feedEndDate = nil
            }

            parsed = GTFSFeedInfo(
                feedVersion: feedVersion,
                feedStartDate: feedStartDate,
                feedEndDate: feedEndDate
            )
            stop = true
        }

        return parsed
    }

    private static func parseFeedDate(_ raw: String) -> Date? {
        let normalized = normalize(raw)
        guard normalized.count == 8 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.date(from: normalized)
    }
}

private struct GTFSCacheManifest: Codable {
    let schemaVersion: Int
    let etag: String?
    let lastModified: String?
    let savedAt: Date
    let feedInfo: GTFSFeedInfo?
}

private struct CachedCoordinate: Codable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct CachedRouteShape: Codable {
    let route: String
    let direction: String
    let coordinates: [CachedCoordinate]
}

private struct CachedRouteStopSchedule: Codable {
    let id: String
    let name: String
    let coordinate: CachedCoordinate
    let sequence: Int
    let scheduledArrival: String?
    let scheduledDeparture: String?

    init(_ schedule: RouteStopSchedule) {
        id = schedule.stop.id
        name = schedule.stop.name
        coordinate = CachedCoordinate(schedule.stop.coord)
        sequence = schedule.sequence
        scheduledArrival = schedule.scheduledArrival
        scheduledDeparture = schedule.scheduledDeparture
    }

    var schedule: RouteStopSchedule {
        RouteStopSchedule(
            stop: BusStop(id: id, name: name, coord: coordinate.coordinate),
            sequence: sequence,
            scheduledArrival: scheduledArrival,
            scheduledDeparture: scheduledDeparture
        )
    }
}

private struct CachedRouteStopSchedulesEntry: Codable {
    let route: String
    let direction: String
    let schedules: [CachedRouteStopSchedule]
}

private struct CachedShapeCoordinatesEntry: Codable {
    let shapeID: String
    let coordinates: [CachedCoordinate]
}

private struct CachedRouteShapeIDsEntry: Codable {
    let route: String
    let direction: String
    let shapeIDs: [String]
}

private struct CachedRouteDirectionLabelEntry: Codable {
    let route: String
    let direction: String
    let label: String
}

private struct CachedRouteNameEntry: Codable {
    let route: String
    let shortName: String
    let longName: String
}

private struct CachedRouteStyleEntry: Codable {
    let route: String
    let routeColorHex: String?
    let routeTextColorHex: String?
}

private struct GTFSStaticCachePayload: Codable {
    let routeShapes: [CachedRouteShape]
    let routeStopSchedules: [CachedRouteStopSchedulesEntry]
    let shapeCoordinates: [CachedShapeCoordinatesEntry]
    let routeShapeIDs: [CachedRouteShapeIDsEntry]
    let routeDirectionLabels: [CachedRouteDirectionLabelEntry]
    let routeNames: [CachedRouteNameEntry]
    let routeStyles: [CachedRouteStyleEntry]
    let feedInfo: GTFSFeedInfo?

    init(staticData: GTFSStaticData) {
        routeShapes = staticData.routeShapes.flatMap { route, directions in
            directions.map { direction, coordinates in
                CachedRouteShape(
                    route: route,
                    direction: direction,
                    coordinates: coordinates.map(CachedCoordinate.init)
                )
            }
        }

        routeStopSchedules = staticData.routeStopSchedules.map { key, schedules in
            CachedRouteStopSchedulesEntry(
                route: key.route,
                direction: key.direction,
                schedules: schedules.map(CachedRouteStopSchedule.init)
            )
        }

        shapeCoordinates = staticData.shapeCoordinatesByID.map { shapeID, coordinates in
            CachedShapeCoordinatesEntry(
                shapeID: shapeID,
                coordinates: coordinates.map(CachedCoordinate.init)
            )
        }

        routeShapeIDs = staticData.routeShapeIDsByKey.map { key, shapeIDs in
            CachedRouteShapeIDsEntry(route: key.route, direction: key.direction, shapeIDs: shapeIDs)
        }

        routeDirectionLabels = staticData.routeDirectionLabels.map { key, label in
            CachedRouteDirectionLabelEntry(route: key.route, direction: key.direction, label: label)
        }

        routeNames = staticData.routeNamesByRouteID.map { routeID, routeName in
            CachedRouteNameEntry(
                route: routeID,
                shortName: routeName.shortName,
                longName: routeName.longName
            )
        }

        routeStyles = staticData.routeStylesByRouteID.map { routeID, style in
            CachedRouteStyleEntry(
                route: routeID,
                routeColorHex: style.routeColorHex,
                routeTextColorHex: style.routeTextColorHex
            )
        }

        feedInfo = staticData.feedInfo
    }

    func toStaticData() -> GTFSStaticData {
        var nextRouteShapes: [String: [String: [CLLocationCoordinate2D]]] = [:]
        for entry in routeShapes {
            nextRouteShapes[entry.route, default: [:]][entry.direction] = entry.coordinates.map(\.coordinate)
        }

        var nextRouteStopSchedules: [RouteKey: [RouteStopSchedule]] = [:]
        var nextRouteStops: [RouteKey: [BusStop]] = [:]
        for entry in routeStopSchedules {
            let key = RouteKey(route: entry.route, direction: entry.direction)
            let schedules = entry.schedules.map(\.schedule)
            nextRouteStopSchedules[key] = schedules
            nextRouteStops[key] = schedules.map(\.stop)
        }

        var nextShapeCoordinates: [String: [CLLocationCoordinate2D]] = [:]
        for entry in shapeCoordinates {
            nextShapeCoordinates[entry.shapeID] = entry.coordinates.map(\.coordinate)
        }

        var nextRouteShapeIDs: [RouteKey: [String]] = [:]
        for entry in routeShapeIDs {
            let key = RouteKey(route: entry.route, direction: entry.direction)
            nextRouteShapeIDs[key] = entry.shapeIDs
        }

        var nextDirectionLabels: [RouteKey: String] = [:]
        for entry in routeDirectionLabels {
            let key = RouteKey(route: entry.route, direction: entry.direction)
            nextDirectionLabels[key] = entry.label
        }

        var nextRouteNames: [String: GTFSRouteName] = [:]
        for entry in routeNames {
            nextRouteNames[entry.route] = GTFSRouteName(
                shortName: entry.shortName,
                longName: entry.longName
            )
        }

        var nextRouteStyles: [String: GTFSRouteStyle] = [:]
        for entry in routeStyles {
            nextRouteStyles[entry.route] = GTFSRouteStyle(
                routeColorHex: entry.routeColorHex,
                routeTextColorHex: entry.routeTextColorHex
            )
        }

        return GTFSStaticData(
            routeShapes: nextRouteShapes,
            routeStops: nextRouteStops,
            routeStopSchedules: nextRouteStopSchedules,
            shapeCoordinatesByID: nextShapeCoordinates,
            routeShapeIDsByKey: nextRouteShapeIDs,
            routeDirectionLabels: nextDirectionLabels,
            routeNamesByRouteID: nextRouteNames,
            routeStylesByRouteID: nextRouteStyles,
            feedInfo: feedInfo
        )
    }
}

actor LiveGTFSRepository: GTFSRepository {
    private enum GTFSFetchResult {
        case notModified
        case downloaded(fileURL: URL, response: HTTPURLResponse)
    }

    private enum DefaultsKey {
        static let lastUpdatedAt = "gtfs.cache.lastUpdatedAt"
        static let etag = "gtfs.cache.etag"
        static let lastModified = "gtfs.cache.lastModified"
        static let feedVersion = "gtfs.cache.feedVersion"
        static let feedStartDate = "gtfs.cache.feedStartDate"
        static let feedEndDate = "gtfs.cache.feedEndDate"
    }

    private let gtfsURL = URL(string: "https://www.stm.info/sites/default/files/gtfs/gtfs_stm.zip")!
    private let extractionDirectory: URL
    private let persistedCacheDirectory: URL
    private let session: URLSession
    private let userDefaults: UserDefaults
    private let cacheSchemaVersion = 4
    private let staleRevalidationInterval: TimeInterval = 24 * 60 * 60
    private var cachedData: GTFSStaticData?
    private var refreshTask: Task<Void, Never>?

    private var payloadURL: URL {
        persistedCacheDirectory.appendingPathComponent("static_data_v4.plist")
    }

    private var manifestURL: URL {
        persistedCacheDirectory.appendingPathComponent("manifest_v4.plist")
    }

    init(
        extractionDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gtfs_temp", isDirectory: true),
        persistedCacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gtfs_cache", isDirectory: true),
        session: URLSession = .shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.extractionDirectory = extractionDirectory
        self.persistedCacheDirectory = persistedCacheDirectory
        self.session = session
        self.userDefaults = userDefaults
    }

    func loadStaticData() async throws -> GTFSStaticData {
        if let cachedData {
            return cachedData
        }

        if let persistedData = loadPersistedStaticDataIfAvailable() {
            cachedData = persistedData
            if shouldScheduleBackgroundRevalidation() {
                scheduleBackgroundRefresh(forceRefresh: false)
            }
            return persistedData
        }

        let freshlyLoadedData = try await fetchParsePersistData(existingManifest: nil, forceRefresh: false)
        cachedData = freshlyLoadedData
        return freshlyLoadedData
    }

    func refreshStaticData(force: Bool) async throws -> GTFSStaticData {
        refreshTask?.cancel()
        refreshTask = nil

        let existingManifest = force ? nil : loadPersistedManifestIfAvailable()
        let refreshed = try await fetchParsePersistData(existingManifest: existingManifest, forceRefresh: force)
        cachedData = refreshed
        return refreshed
    }

    func cacheMetadata() async -> GTFSCacheMetadata {
        currentMetadata()
    }

    private func shouldScheduleBackgroundRevalidation() -> Bool {
        guard let manifest = loadPersistedManifestIfAvailable() else { return true }
        return Date().timeIntervalSince(manifest.savedAt) >= staleRevalidationInterval
    }

    private func scheduleBackgroundRefresh(forceRefresh: Bool) {
        guard refreshTask == nil else { return }
        refreshTask = Task(priority: .utility) { [weak self] in
            await self?.performBackgroundRefresh(forceRefresh: forceRefresh)
        }
    }

    private func performBackgroundRefresh(forceRefresh: Bool) async {
        defer { refreshTask = nil }
        do {
            let manifest = forceRefresh ? nil : loadPersistedManifestIfAvailable()
            let refreshed = try await fetchParsePersistData(existingManifest: manifest, forceRefresh: forceRefresh)
            cachedData = refreshed
        } catch {
            // Keep serving the existing cache if background refresh fails.
        }
    }

    private func fetchParsePersistData(existingManifest: GTFSCacheManifest?, forceRefresh: Bool) async throws -> GTFSStaticData {
        let fetchResult = try await fetchGTFSArchive(existingManifest: existingManifest, forceRefresh: forceRefresh)

        switch fetchResult {
        case .notModified:
            if let persisted = loadPersistedStaticDataIfAvailable() {
                return persisted
            }
            throw NSError(
                domain: "GTFSRepository",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Received 304 but no local GTFS cache is available"]
            )
        case .downloaded(let fileURL, let response):
            let parsed = try parseArchive(at: fileURL)
            try persist(staticData: parsed, response: response)
            return parsed
        }
    }

    private func fetchGTFSArchive(existingManifest: GTFSCacheManifest?, forceRefresh: Bool) async throws -> GTFSFetchResult {
        var request = URLRequest(url: gtfsURL)
        request.timeoutInterval = 45
        if !forceRefresh {
            if let etag = existingManifest?.etag, !etag.isEmpty {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }
            if let lastModified = existingManifest?.lastModified, !lastModified.isEmpty {
                request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }
        }

        let (archiveURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "GTFSRepository",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "GTFS response was not HTTP"]
            )
        }

        if httpResponse.statusCode == 304 {
            return .notModified
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "GTFSRepository",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "GTFS request failed with status code \(httpResponse.statusCode)"]
            )
        }

        return .downloaded(fileURL: archiveURL, response: httpResponse)
    }

    private func parseArchive(at archiveURL: URL) throws -> GTFSStaticData {
        try resetExtractionDirectory()
        try FileManager.default.unzipItem(at: archiveURL, to: extractionDirectory)
        defer { try? FileManager.default.removeItem(at: extractionDirectory) }

        let tripsURL = extractionDirectory.appendingPathComponent("trips.txt")
        let routesURL = extractionDirectory.appendingPathComponent("routes.txt")
        let shapesURL = extractionDirectory.appendingPathComponent("shapes.txt")
        let stopsURL = extractionDirectory.appendingPathComponent("stops.txt")
        let stopTimesURL = extractionDirectory.appendingPathComponent("stop_times.txt")
        let feedInfoURL = extractionDirectory.appendingPathComponent("feed_info.txt")

        guard FileManager.default.fileExists(atPath: tripsURL.path),
              FileManager.default.fileExists(atPath: shapesURL.path),
              FileManager.default.fileExists(atPath: stopsURL.path),
              FileManager.default.fileExists(atPath: stopTimesURL.path) else {
            throw NSError(
                domain: "GTFSRepository",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Missing GTFS files after extraction"]
            )
        }

        let feedInfoText: String?
        if FileManager.default.fileExists(atPath: feedInfoURL.path) {
            feedInfoText = try? String(contentsOf: feedInfoURL, encoding: .utf8)
        } else {
            feedInfoText = nil
        }

        return try parseStaticData(
            tripsURL: tripsURL,
            routesURL: routesURL,
            shapesURL: shapesURL,
            stopsURL: stopsURL,
            stopTimesURL: stopTimesURL,
            feedInfoText: feedInfoText
        )
    }

    private func persist(staticData: GTFSStaticData, response: HTTPURLResponse) throws {
        try FileManager.default.createDirectory(at: persistedCacheDirectory, withIntermediateDirectories: true)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        let payload = GTFSStaticCachePayload(staticData: staticData)
        let payloadData = try encoder.encode(payload)
        try payloadData.write(to: payloadURL, options: .atomic)

        let manifest = GTFSCacheManifest(
            schemaVersion: cacheSchemaVersion,
            etag: normalizedHeaderValue("ETag", from: response),
            lastModified: normalizedHeaderValue("Last-Modified", from: response),
            savedAt: Date(),
            feedInfo: staticData.feedInfo
        )
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: manifestURL, options: .atomic)
        persistMetadataToDefaults(manifest)
    }

    private func loadPersistedStaticDataIfAvailable() -> GTFSStaticData? {
        guard let manifest = loadPersistedManifestIfAvailable() else { return nil }
        guard FileManager.default.fileExists(atPath: payloadURL.path) else { return nil }

        do {
            let payloadData = try Data(contentsOf: payloadURL)
            let payload = try PropertyListDecoder().decode(GTFSStaticCachePayload.self, from: payloadData)
            let data = payload.toStaticData()
            if data.feedInfo == nil, let feedInfo = manifest.feedInfo {
                return GTFSStaticData(
                    routeShapes: data.routeShapes,
                    routeStops: data.routeStops,
                    routeStopSchedules: data.routeStopSchedules,
                    shapeCoordinatesByID: data.shapeCoordinatesByID,
                    routeShapeIDsByKey: data.routeShapeIDsByKey,
                    routeDirectionLabels: data.routeDirectionLabels,
                    routeNamesByRouteID: data.routeNamesByRouteID,
                    routeStylesByRouteID: data.routeStylesByRouteID,
                    feedInfo: feedInfo
                )
            }
            return data
        } catch {
            try? clearPersistedCache()
            return nil
        }
    }

    private func loadPersistedManifestIfAvailable() -> GTFSCacheManifest? {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try PropertyListDecoder().decode(GTFSCacheManifest.self, from: data)
            guard manifest.schemaVersion == cacheSchemaVersion else {
                try? clearPersistedCache()
                return nil
            }
            persistMetadataToDefaults(manifest)
            return manifest
        } catch {
            try? clearPersistedCache()
            return nil
        }
    }

    private func clearPersistedCache() throws {
        if FileManager.default.fileExists(atPath: persistedCacheDirectory.path) {
            try FileManager.default.removeItem(at: persistedCacheDirectory)
        }
        clearMetadataInDefaults()
    }

    private func currentMetadata() -> GTFSCacheMetadata {
        if let manifest = loadPersistedManifestIfAvailable() {
            return GTFSCacheMetadata(
                lastUpdatedAt: manifest.savedAt,
                etag: manifest.etag,
                lastModified: manifest.lastModified,
                feedInfo: manifest.feedInfo
            )
        }

        let feedVersion = userDefaults.string(forKey: DefaultsKey.feedVersion)
        let feedStartDate = userDefaults.object(forKey: DefaultsKey.feedStartDate) as? Date
        let feedEndDate = userDefaults.object(forKey: DefaultsKey.feedEndDate) as? Date
        let feedInfo: GTFSFeedInfo?
        if feedVersion != nil || feedStartDate != nil || feedEndDate != nil {
            feedInfo = GTFSFeedInfo(feedVersion: feedVersion, feedStartDate: feedStartDate, feedEndDate: feedEndDate)
        } else {
            feedInfo = nil
        }

        return GTFSCacheMetadata(
            lastUpdatedAt: userDefaults.object(forKey: DefaultsKey.lastUpdatedAt) as? Date,
            etag: userDefaults.string(forKey: DefaultsKey.etag),
            lastModified: userDefaults.string(forKey: DefaultsKey.lastModified),
            feedInfo: feedInfo
        )
    }

    private func persistMetadataToDefaults(_ manifest: GTFSCacheManifest) {
        userDefaults.set(manifest.savedAt, forKey: DefaultsKey.lastUpdatedAt)
        if let etag = manifest.etag {
            userDefaults.set(etag, forKey: DefaultsKey.etag)
        } else {
            userDefaults.removeObject(forKey: DefaultsKey.etag)
        }
        if let lastModified = manifest.lastModified {
            userDefaults.set(lastModified, forKey: DefaultsKey.lastModified)
        } else {
            userDefaults.removeObject(forKey: DefaultsKey.lastModified)
        }

        if let feedInfo = manifest.feedInfo {
            if let feedVersion = feedInfo.feedVersion {
                userDefaults.set(feedVersion, forKey: DefaultsKey.feedVersion)
            } else {
                userDefaults.removeObject(forKey: DefaultsKey.feedVersion)
            }
            if let start = feedInfo.feedStartDate {
                userDefaults.set(start, forKey: DefaultsKey.feedStartDate)
            } else {
                userDefaults.removeObject(forKey: DefaultsKey.feedStartDate)
            }
            if let end = feedInfo.feedEndDate {
                userDefaults.set(end, forKey: DefaultsKey.feedEndDate)
            } else {
                userDefaults.removeObject(forKey: DefaultsKey.feedEndDate)
            }
        } else {
            userDefaults.removeObject(forKey: DefaultsKey.feedVersion)
            userDefaults.removeObject(forKey: DefaultsKey.feedStartDate)
            userDefaults.removeObject(forKey: DefaultsKey.feedEndDate)
        }
    }

    private func clearMetadataInDefaults() {
        userDefaults.removeObject(forKey: DefaultsKey.lastUpdatedAt)
        userDefaults.removeObject(forKey: DefaultsKey.etag)
        userDefaults.removeObject(forKey: DefaultsKey.lastModified)
        userDefaults.removeObject(forKey: DefaultsKey.feedVersion)
        userDefaults.removeObject(forKey: DefaultsKey.feedStartDate)
        userDefaults.removeObject(forKey: DefaultsKey.feedEndDate)
    }

    private func normalizedHeaderValue(_ key: String, from response: HTTPURLResponse) -> String? {
        guard let raw = response.value(forHTTPHeaderField: key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resetExtractionDirectory() throws {
        if FileManager.default.fileExists(atPath: extractionDirectory.path) {
            try FileManager.default.removeItem(at: extractionDirectory)
        }
        try FileManager.default.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
    }

    private func parseStaticData(
        tripsURL: URL,
        routesURL: URL,
        shapesURL: URL,
        stopsURL: URL,
        stopTimesURL: URL,
        feedInfoText: String?
    ) throws -> GTFSStaticData {
        let tripsText = try String(contentsOf: tripsURL, encoding: .utf8)
        let routesText: String?
        if FileManager.default.fileExists(atPath: routesURL.path) {
            routesText = try String(contentsOf: routesURL, encoding: .utf8)
        } else {
            routesText = nil
        }
        let shapesText = try String(contentsOf: shapesURL, encoding: .utf8)
        let stopsText = try String(contentsOf: stopsURL, encoding: .utf8)
        let stopTimesText = try String(contentsOf: stopTimesURL, encoding: .utf8)

        let trips = GTFSParsers.parseTrips(tripsText)
        let routeCatalog = routesText.map(GTFSParsers.parseRouteCatalog) ?? .empty
        let routeStylesByRouteID = routeCatalog.stylesByRouteID
        let routeNamesByRouteID = routeCatalog.namesByRouteID
        let shapesByID = GTFSParsers.parseShapes(shapesText)
        let stopsByID = GTFSParsers.parseStops(stopsText)
        let routeStopSchedules = GTFSParsers.parseRouteStopSchedules(
            stopTimesText: stopTimesText,
            representativeTripByRoute: trips.representativeTripByRoute,
            routeByTripID: trips.routeByTripID,
            stopsByID: stopsByID
        )
        var routeStops: [RouteKey: [BusStop]] = [:]
        for (routeKey, schedules) in routeStopSchedules {
            routeStops[routeKey] = schedules.map(\.stop)
        }

        var routeShapes: [String: [String: [CLLocationCoordinate2D]]] = [:]
        var shapeCoordinatesByID: [String: [CLLocationCoordinate2D]] = [:]
        var routeShapeIDsByKey: [RouteKey: [String]] = [:]
        for (key, shapeIDs) in trips.routeToShapeIDs {
            let sortedShapeIDs = Array(shapeIDs).sorted()
            routeShapeIDsByKey[key] = sortedShapeIDs
            guard let sid = sortedShapeIDs.first, let points = shapesByID[sid] else { continue }
            let primaryCoords = points.sorted(by: { $0.seq < $1.seq }).map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
            }
            routeShapes[key.route, default: [:]][key.direction] = primaryCoords
        }
        for (shapeID, points) in shapesByID {
            let coords = points.sorted(by: { $0.seq < $1.seq }).map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
            }
            shapeCoordinatesByID[shapeID] = coords
        }

        return GTFSStaticData(
            routeShapes: routeShapes,
            routeStops: routeStops,
            routeStopSchedules: routeStopSchedules,
            shapeCoordinatesByID: shapeCoordinatesByID,
            routeShapeIDsByKey: routeShapeIDsByKey,
            routeDirectionLabels: trips.directionLabelByRoute,
            routeNamesByRouteID: routeNamesByRouteID,
            routeStylesByRouteID: routeStylesByRouteID,
            feedInfo: feedInfoText.flatMap(GTFSParsers.parseFeedInfo)
        )
    }
}
