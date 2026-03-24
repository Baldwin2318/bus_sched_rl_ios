import Foundation
import CoreLocation
import ZIPFoundation

protocol GTFSRepository {
    func loadStaticData() async throws -> GTFSStaticData
    func refreshStaticData(force: Bool) async throws -> GTFSStaticData
    func cacheMetadata() async -> GTFSCacheMetadata
}

private struct TripsParseResult {
    let representativeTripByRoute: [RouteKey: String]
    let routeByTripID: [String: RouteKey]
    let directionLabelByRoute: [RouteKey: String]
    let shapeIDByTripID: [String: String]
    let routeShapeIDByRouteKey: [RouteKey: String]
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

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = normalize(value)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func headerIndexMap(_ headerLine: String) -> [String: Int] {
        guard let cols = try? CSVParser.parseLine(headerLine) else { return [:] }
        var result: [String: Int] = [:]
        for (index, column) in cols.enumerated() {
            result[normalize(column)] = index
        }
        return result
    }

    private static func extractDirectionLabel(from headsign: String, fallback directionID: String) -> String {
        let cleaned = normalize(headsign)
        if !cleaned.isEmpty {
            return cleaned
        }
        return TransitText.fallbackDirectionText(directionID)
    }

    static func parseTrips(_ text: String) -> TripsParseResult {
        var representativeTripByRoute: [RouteKey: String] = [:]
        var routeByTripID: [String: RouteKey] = [:]
        var directionLabelByRoute: [RouteKey: String] = [:]
        var shapeIDByTripID: [String: String] = [:]
        var routeShapeIDByRouteKey: [RouteKey: String] = [:]

        var isHeader = true
        var header: [String: Int] = [:]
        text.enumerateLines { line, _ in
            if isHeader {
                isHeader = false
                header = headerIndexMap(line)
                return
            }

            guard !line.isEmpty, let cols = try? CSVParser.parseLine(line) else { return }
            guard let routeIndex = header["route_id"],
                  let tripIndex = header["trip_id"],
                  let directionIndex = header["direction_id"],
                  routeIndex < cols.count,
                  tripIndex < cols.count,
                  directionIndex < cols.count else {
                return
            }

            let routeID = normalize(cols[routeIndex])
            let tripID = normalize(cols[tripIndex])
            let directionID = normalize(cols[directionIndex]).isEmpty ? "0" : normalize(cols[directionIndex])
            guard !routeID.isEmpty, !tripID.isEmpty else { return }

            let routeKey = RouteKey(route: routeID, direction: directionID)
            routeByTripID[tripID] = routeKey
            if representativeTripByRoute[routeKey] == nil {
                representativeTripByRoute[routeKey] = tripID
            }

            if let shapeIndex = header["shape_id"],
               shapeIndex < cols.count {
                let shapeID = normalize(cols[shapeIndex])
                if !shapeID.isEmpty {
                    shapeIDByTripID[tripID] = shapeID
                    if routeShapeIDByRouteKey[routeKey] == nil {
                        routeShapeIDByRouteKey[routeKey] = shapeID
                    }
                }
            }

            if directionLabelByRoute[routeKey] == nil {
                let headsign: String
                if let headsignIndex = header["trip_headsign"], headsignIndex < cols.count {
                    headsign = cols[headsignIndex]
                } else {
                    headsign = ""
                }
                directionLabelByRoute[routeKey] = extractDirectionLabel(
                    from: headsign,
                    fallback: directionID
                )
            }
        }

        return TripsParseResult(
            representativeTripByRoute: representativeTripByRoute,
            routeByTripID: routeByTripID,
            directionLabelByRoute: directionLabelByRoute,
            shapeIDByTripID: shapeIDByTripID,
            routeShapeIDByRouteKey: routeShapeIDByRouteKey
        )
    }

    static func parseShapes(_ text: String) -> [String: [CLLocationCoordinate2D]] {
        var pointsByShapeID: [String: [(sequence: Int, coordinate: CLLocationCoordinate2D)]] = [:]
        var isHeader = true
        var header: [String: Int] = [:]

        text.enumerateLines { line, _ in
            if isHeader {
                isHeader = false
                header = headerIndexMap(line)
                return
            }

            guard !line.isEmpty, let cols = try? CSVParser.parseLine(line) else { return }
            guard let shapeIDIndex = header["shape_id"],
                  let latitudeIndex = header["shape_pt_lat"],
                  let longitudeIndex = header["shape_pt_lon"],
                  let sequenceIndex = header["shape_pt_sequence"],
                  shapeIDIndex < cols.count,
                  latitudeIndex < cols.count,
                  longitudeIndex < cols.count,
                  sequenceIndex < cols.count,
                  let latitude = Double(cols[latitudeIndex]),
                  let longitude = Double(cols[longitudeIndex]),
                  let sequence = Int(cols[sequenceIndex]) else {
                return
            }

            let shapeID = normalize(cols[shapeIDIndex])
            guard !shapeID.isEmpty else { return }

            pointsByShapeID[shapeID, default: []].append(
                (
                    sequence: sequence,
                    coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                )
            )
        }

        return pointsByShapeID.mapValues { points in
            points
                .sorted { $0.sequence < $1.sequence }
                .map(\.coordinate)
        }
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
            guard let idIndex = header["stop_id"],
                  let nameIndex = header["stop_name"],
                  let latIndex = header["stop_lat"],
                  let lonIndex = header["stop_lon"],
                  idIndex < cols.count,
                  nameIndex < cols.count,
                  latIndex < cols.count,
                  lonIndex < cols.count,
                  let latitude = Double(cols[latIndex]),
                  let longitude = Double(cols[lonIndex]) else {
                return
            }

            let stopID = normalize(cols[idIndex])
            guard !stopID.isEmpty else { return }

            stopsByID[stopID] = BusStop(
                id: stopID,
                name: normalize(cols[nameIndex]),
                coord: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            )
        }

        return stopsByID
    }

    private static func normalizedColorHex(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = normalize(value).replacingOccurrences(of: "#", with: "").uppercased()
        guard trimmed.count == 6 else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard trimmed.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
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
            guard let routeIDIndex = header["route_id"], routeIDIndex < cols.count else { return }

            let routeID = normalize(cols[routeIDIndex])
            guard !routeID.isEmpty else { return }

            let shortName = header["route_short_name"].flatMap { index in
                index < cols.count ? normalizedOptional(cols[index]) : nil
            } ?? routeID
            let longName = header["route_long_name"].flatMap { index in
                index < cols.count ? normalizedOptional(cols[index]) : nil
            } ?? shortName

            namesByRouteID[routeID] = GTFSRouteName(shortName: shortName, longName: longName)

            let routeColorHex = header["route_color"].flatMap { index in
                index < cols.count ? normalizedColorHex(cols[index]) : nil
            }
            let routeTextColorHex = header["route_text_color"].flatMap { index in
                index < cols.count ? normalizedColorHex(cols[index]) : nil
            }

            if routeColorHex != nil || routeTextColorHex != nil {
                stylesByRouteID[routeID] = GTFSRouteStyle(
                    routeColorHex: routeColorHex,
                    routeTextColorHex: routeTextColorHex
                )
            }
        }

        return RouteCatalogParseResult(
            stylesByRouteID: stylesByRouteID,
            namesByRouteID: namesByRouteID
        )
    }

    static func parseRouteStopSchedules(
        stopTimesText: String,
        representativeTripByRoute: [RouteKey: String],
        routeByTripID: [String: RouteKey],
        stopsByID: [String: BusStop]
    ) -> [RouteKey: [RouteStopSchedule]] {
        let selectedTripIDs = Set(representativeTripByRoute.values)
        var rowsByRoute: [RouteKey: [(sequence: Int, stop: BusStop, arrival: String?, departure: String?)]] = [:]

        var isHeader = true
        var header: [String: Int] = [:]
        stopTimesText.enumerateLines { line, _ in
            if isHeader {
                isHeader = false
                header = headerIndexMap(line)
                return
            }

            guard !line.isEmpty, let cols = try? CSVParser.parseLine(line) else { return }
            guard let tripIndex = header["trip_id"],
                  let stopIndex = header["stop_id"],
                  let sequenceIndex = header["stop_sequence"],
                  tripIndex < cols.count,
                  stopIndex < cols.count,
                  sequenceIndex < cols.count else {
                return
            }

            let tripID = normalize(cols[tripIndex])
            guard selectedTripIDs.contains(tripID),
                  let routeKey = routeByTripID[tripID],
                  let stop = stopsByID[normalize(cols[stopIndex])],
                  let sequence = Int(cols[sequenceIndex]) else {
                return
            }

            let arrival = header["arrival_time"].flatMap { index in
                index < cols.count ? normalizedOptional(cols[index]) : nil
            }
            let departure = header["departure_time"].flatMap { index in
                index < cols.count ? normalizedOptional(cols[index]) : nil
            }

            rowsByRoute[routeKey, default: []].append(
                (sequence: sequence, stop: stop, arrival: arrival, departure: departure)
            )
        }

        var schedulesByRoute: [RouteKey: [RouteStopSchedule]] = [:]
        for (routeKey, rows) in rowsByRoute {
            let orderedRows = rows.sorted { $0.sequence < $1.sequence }
            var seenStopIDs: Set<String> = []
            schedulesByRoute[routeKey] = orderedRows.compactMap { row in
                guard seenStopIDs.insert(row.stop.id).inserted else { return nil }
                return RouteStopSchedule(
                    stop: row.stop,
                    sequence: row.sequence,
                    scheduledArrival: row.arrival,
                    scheduledDeparture: row.departure
                )
            }
        }

        return schedulesByRoute
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
            let feedVersion = header["feed_version"].flatMap { index in
                index < cols.count ? normalizedOptional(cols[index]) : nil
            }
            let feedStartDate = header["feed_start_date"].flatMap { index in
                index < cols.count ? parseFeedDate(cols[index]) : nil
            }
            let feedEndDate = header["feed_end_date"].flatMap { index in
                index < cols.count ? parseFeedDate(cols[index]) : nil
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

private struct CachedRouteShapeEntry: Codable {
    let route: String
    let direction: String
    let shapeID: String
}

private struct CachedTripShapeEntry: Codable {
    let tripID: String
    let shapeID: String
}

private struct CachedShapePointsEntry: Codable {
    let shapeID: String
    let points: [CachedCoordinate]
}

private struct GTFSStaticCachePayload: Codable {
    let routeStopSchedules: [CachedRouteStopSchedulesEntry]
    let routeDirectionLabels: [CachedRouteDirectionLabelEntry]
    let routeNames: [CachedRouteNameEntry]
    let routeStyles: [CachedRouteStyleEntry]
    let routeShapes: [CachedRouteShapeEntry]
    let tripShapes: [CachedTripShapeEntry]
    let shapePoints: [CachedShapePointsEntry]
    let feedInfo: GTFSFeedInfo?

    init(staticData: GTFSStaticData) {
        routeStopSchedules = staticData.routeStopSchedules.map { key, schedules in
            CachedRouteStopSchedulesEntry(
                route: key.route,
                direction: key.direction,
                schedules: schedules.map(CachedRouteStopSchedule.init)
            )
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
        routeShapes = staticData.routeShapeIDByRouteKey.map { key, shapeID in
            CachedRouteShapeEntry(route: key.route, direction: key.direction, shapeID: shapeID)
        }
        tripShapes = staticData.shapeIDByTripID.map { tripID, shapeID in
            CachedTripShapeEntry(tripID: tripID, shapeID: shapeID)
        }
        shapePoints = staticData.shapePointsByShapeID.map { shapeID, points in
            CachedShapePointsEntry(shapeID: shapeID, points: points.map(CachedCoordinate.init))
        }
        feedInfo = staticData.feedInfo
    }

    func toStaticData() -> GTFSStaticData {
        var nextRouteStopSchedules: [RouteKey: [RouteStopSchedule]] = [:]
        var nextRouteStops: [RouteKey: [BusStop]] = [:]
        for entry in self.routeStopSchedules {
            let key = RouteKey(route: entry.route, direction: entry.direction)
            let schedules = entry.schedules.map(\.schedule)
            nextRouteStopSchedules[key] = schedules
            nextRouteStops[key] = schedules.map(\.stop)
        }

        var nextRouteDirectionLabels: [RouteKey: String] = [:]
        for entry in self.routeDirectionLabels {
            nextRouteDirectionLabels[RouteKey(route: entry.route, direction: entry.direction)] = entry.label
        }

        var nextRouteNamesByRouteID: [String: GTFSRouteName] = [:]
        for entry in self.routeNames {
            nextRouteNamesByRouteID[entry.route] = GTFSRouteName(
                shortName: entry.shortName,
                longName: entry.longName
            )
        }

        var nextRouteStylesByRouteID: [String: GTFSRouteStyle] = [:]
        for entry in self.routeStyles {
            nextRouteStylesByRouteID[entry.route] = GTFSRouteStyle(
                routeColorHex: entry.routeColorHex,
                routeTextColorHex: entry.routeTextColorHex
            )
        }

        var nextRouteShapeIDByRouteKey: [RouteKey: String] = [:]
        for entry in self.routeShapes {
            nextRouteShapeIDByRouteKey[RouteKey(route: entry.route, direction: entry.direction)] = entry.shapeID
        }

        let nextShapeIDByTripID = Dictionary(uniqueKeysWithValues: tripShapes.map { ($0.tripID, $0.shapeID) })
        let nextShapePointsByShapeID = Dictionary(
            uniqueKeysWithValues: shapePoints.map { ($0.shapeID, $0.points.map(\.coordinate)) }
        )

        return GTFSStaticData(
            routeStops: nextRouteStops,
            routeStopSchedules: nextRouteStopSchedules,
            routeDirectionLabels: nextRouteDirectionLabels,
            routeNamesByRouteID: nextRouteNamesByRouteID,
            routeStylesByRouteID: nextRouteStylesByRouteID,
            routeShapeIDByRouteKey: nextRouteShapeIDByRouteKey,
            shapeIDByTripID: nextShapeIDByTripID,
            shapePointsByShapeID: nextShapePointsByShapeID,
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
    private let cacheSchemaVersion = 6
    private let staleRevalidationInterval: TimeInterval = 24 * 60 * 60
    private var cachedData: GTFSStaticData?
    private var refreshTask: Task<Void, Never>?

    private var payloadURL: URL {
        persistedCacheDirectory.appendingPathComponent("static_data_v6.plist")
    }

    private var manifestURL: URL {
        persistedCacheDirectory.appendingPathComponent("manifest_v6.plist")
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

    private func fetchParsePersistData(
        existingManifest: GTFSCacheManifest?,
        forceRefresh: Bool
    ) async throws -> GTFSStaticData {
        let fetchResult = try await fetchGTFSArchive(
            existingManifest: existingManifest,
            forceRefresh: forceRefresh
        )

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

    private func fetchGTFSArchive(
        existingManifest: GTFSCacheManifest?,
        forceRefresh: Bool
    ) async throws -> GTFSFetchResult {
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
        let stopsURL = extractionDirectory.appendingPathComponent("stops.txt")
        let stopTimesURL = extractionDirectory.appendingPathComponent("stop_times.txt")
        let shapesURL = extractionDirectory.appendingPathComponent("shapes.txt")
        let feedInfoURL = extractionDirectory.appendingPathComponent("feed_info.txt")

        guard FileManager.default.fileExists(atPath: tripsURL.path),
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
            stopsURL: stopsURL,
            stopTimesURL: stopTimesURL,
            shapesURL: shapesURL,
            feedInfoText: feedInfoText
        )
    }

    private func persist(staticData: GTFSStaticData, response: HTTPURLResponse) throws {
        try FileManager.default.createDirectory(at: persistedCacheDirectory, withIntermediateDirectories: true)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        let payload = GTFSStaticCachePayload(staticData: staticData)
        try encoder.encode(payload).write(to: payloadURL, options: .atomic)

        let manifest = GTFSCacheManifest(
            schemaVersion: cacheSchemaVersion,
            etag: normalizedHeaderValue("ETag", from: response),
            lastModified: normalizedHeaderValue("Last-Modified", from: response),
            savedAt: Date(),
            feedInfo: staticData.feedInfo
        )
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
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
                    routeStops: data.routeStops,
                    routeStopSchedules: data.routeStopSchedules,
                    routeDirectionLabels: data.routeDirectionLabels,
                    routeNamesByRouteID: data.routeNamesByRouteID,
                    routeStylesByRouteID: data.routeStylesByRouteID,
                    routeShapeIDByRouteKey: data.routeShapeIDByRouteKey,
                    shapeIDByTripID: data.shapeIDByTripID,
                    shapePointsByShapeID: data.shapePointsByShapeID,
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
            feedInfo = GTFSFeedInfo(
                feedVersion: feedVersion,
                feedStartDate: feedStartDate,
                feedEndDate: feedEndDate
            )
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
        try FileManager.default.createDirectory(
            at: extractionDirectory,
            withIntermediateDirectories: true
        )
    }

    private func parseStaticData(
        tripsURL: URL,
        routesURL: URL,
        stopsURL: URL,
        stopTimesURL: URL,
        shapesURL: URL,
        feedInfoText: String?
    ) throws -> GTFSStaticData {
        let tripsText = try String(contentsOf: tripsURL, encoding: .utf8)
        let routesText: String?
        if FileManager.default.fileExists(atPath: routesURL.path) {
            routesText = try String(contentsOf: routesURL, encoding: .utf8)
        } else {
            routesText = nil
        }
        let stopsText = try String(contentsOf: stopsURL, encoding: .utf8)
        let stopTimesText = try String(contentsOf: stopTimesURL, encoding: .utf8)
        let shapesText: String?
        if FileManager.default.fileExists(atPath: shapesURL.path) {
            shapesText = try String(contentsOf: shapesURL, encoding: .utf8)
        } else {
            shapesText = nil
        }

        let trips = GTFSParsers.parseTrips(tripsText)
        let routeCatalog = routesText.map(GTFSParsers.parseRouteCatalog) ?? .empty
        let stopsByID = GTFSParsers.parseStops(stopsText)
        let shapePointsByShapeID = shapesText.map(GTFSParsers.parseShapes) ?? [:]
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

        return GTFSStaticData(
            routeStops: routeStops,
            routeStopSchedules: routeStopSchedules,
            routeDirectionLabels: trips.directionLabelByRoute,
            routeNamesByRouteID: routeCatalog.namesByRouteID,
            routeStylesByRouteID: routeCatalog.stylesByRouteID,
            routeShapeIDByRouteKey: trips.routeShapeIDByRouteKey,
            shapeIDByTripID: trips.shapeIDByTripID,
            shapePointsByShapeID: shapePointsByShapeID,
            feedInfo: feedInfoText.flatMap(GTFSParsers.parseFeedInfo)
        )
    }
}
