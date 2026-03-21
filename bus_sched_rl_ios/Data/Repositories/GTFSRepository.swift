import Foundation
import CoreLocation
import ZIPFoundation

struct GTFSStaticData {
    let routeShapes: [String: [String: [CLLocationCoordinate2D]]]
    let routeStops: [RouteKey: [BusStop]]
    let shapeCoordinatesByID: [String: [CLLocationCoordinate2D]]
    let routeShapeIDsByKey: [RouteKey: [String]]
    let routeDirectionLabels: [RouteKey: String]

    var availableRoutes: [String] {
        routeShapes.keys.sorted()
    }
}

protocol GTFSRepository {
    func loadStaticData() async throws -> GTFSStaticData
}

private struct TripsParseResult {
    let routeToShapeIDs: [RouteKey: Set<String>]
    let representativeTripByRoute: [RouteKey: String]
    let routeByTripID: [String: RouteKey]
    let directionLabelByRoute: [RouteKey: String]
}

private enum GTFSParsers {
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

    static func parseRouteStops(
        stopTimesText: String,
        representativeTripByRoute: [RouteKey: String],
        routeByTripID: [String: RouteKey],
        stopsByID: [String: BusStop]
    ) -> [RouteKey: [BusStop]] {
        let selectedTripIDs = Set(representativeTripByRoute.values)
        var routeStopRows: [RouteKey: [(sequence: Int, stop: BusStop)]] = [:]

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

            routeStopRows[routeKey, default: []].append((seq, stop))
        }

        var routeStops: [RouteKey: [BusStop]] = [:]
        for (routeKey, rows) in routeStopRows {
            let ordered = rows.sorted { $0.sequence < $1.sequence }
            var seen: Set<String> = []
            routeStops[routeKey] = ordered.compactMap { row in
                if seen.contains(row.stop.id) { return nil }
                seen.insert(row.stop.id)
                return row.stop
            }
        }

        return routeStops
    }
}

private struct GTFSCacheManifest: Codable {
    let schemaVersion: Int
    let etag: String?
    let lastModified: String?
    let savedAt: Date
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

private struct CachedRouteStop: Codable {
    let id: String
    let name: String
    let coordinate: CachedCoordinate

    init(_ stop: BusStop) {
        id = stop.id
        name = stop.name
        coordinate = CachedCoordinate(stop.coord)
    }

    var stop: BusStop {
        BusStop(id: id, name: name, coord: coordinate.coordinate)
    }
}

private struct CachedRouteStopsEntry: Codable {
    let route: String
    let direction: String
    let stops: [CachedRouteStop]
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

private struct GTFSStaticCachePayload: Codable {
    let routeShapes: [CachedRouteShape]
    let routeStops: [CachedRouteStopsEntry]
    let shapeCoordinates: [CachedShapeCoordinatesEntry]
    let routeShapeIDs: [CachedRouteShapeIDsEntry]
    let routeDirectionLabels: [CachedRouteDirectionLabelEntry]

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

        routeStops = staticData.routeStops.map { key, stops in
            CachedRouteStopsEntry(
                route: key.route,
                direction: key.direction,
                stops: stops.map(CachedRouteStop.init)
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
    }

    func toStaticData() -> GTFSStaticData {
        var nextRouteShapes: [String: [String: [CLLocationCoordinate2D]]] = [:]
        for entry in routeShapes {
            nextRouteShapes[entry.route, default: [:]][entry.direction] = entry.coordinates.map(\.coordinate)
        }

        var nextRouteStops: [RouteKey: [BusStop]] = [:]
        for entry in routeStops {
            let key = RouteKey(route: entry.route, direction: entry.direction)
            nextRouteStops[key] = entry.stops.map(\.stop)
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

        return GTFSStaticData(
            routeShapes: nextRouteShapes,
            routeStops: nextRouteStops,
            shapeCoordinatesByID: nextShapeCoordinates,
            routeShapeIDsByKey: nextRouteShapeIDs,
            routeDirectionLabels: nextDirectionLabels
        )
    }
}

actor LiveGTFSRepository: GTFSRepository {
    private enum GTFSFetchResult {
        case notModified
        case downloaded(fileURL: URL, response: HTTPURLResponse)
    }

    private let gtfsURL = URL(string: "https://www.stm.info/sites/default/files/gtfs/gtfs_stm.zip")!
    private let extractionDirectory: URL
    private let persistedCacheDirectory: URL
    private let session: URLSession
    private let cacheSchemaVersion = 1
    private var cachedData: GTFSStaticData?
    private var refreshTask: Task<Void, Never>?

    private var payloadURL: URL {
        persistedCacheDirectory.appendingPathComponent("static_data_v1.plist")
    }

    private var manifestURL: URL {
        persistedCacheDirectory.appendingPathComponent("manifest_v1.plist")
    }

    init(
        extractionDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gtfs_temp", isDirectory: true),
        persistedCacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gtfs_cache", isDirectory: true),
        session: URLSession = .shared
    ) {
        self.extractionDirectory = extractionDirectory
        self.persistedCacheDirectory = persistedCacheDirectory
        self.session = session
    }

    func loadStaticData() async throws -> GTFSStaticData {
        if let cachedData {
            return cachedData
        }

        if let persistedData = loadPersistedStaticDataIfAvailable() {
            cachedData = persistedData
            scheduleBackgroundRefresh()
            return persistedData
        }

        let freshlyLoadedData = try await fetchParsePersistData(existingManifest: nil)
        cachedData = freshlyLoadedData
        return freshlyLoadedData
    }

    private func scheduleBackgroundRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task(priority: .utility) { [weak self] in
            await self?.performBackgroundRefresh()
        }
    }

    private func performBackgroundRefresh() async {
        defer { refreshTask = nil }
        do {
            let manifest = loadPersistedManifestIfAvailable()
            let refreshed = try await fetchParsePersistData(existingManifest: manifest)
            cachedData = refreshed
        } catch {
            // Keep serving the existing cache if background refresh fails.
        }
    }

    private func fetchParsePersistData(existingManifest: GTFSCacheManifest?) async throws -> GTFSStaticData {
        let fetchResult = try await fetchGTFSArchive(existingManifest: existingManifest)

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

    private func fetchGTFSArchive(existingManifest: GTFSCacheManifest?) async throws -> GTFSFetchResult {
        var request = URLRequest(url: gtfsURL)
        request.timeoutInterval = 45
        if let etag = existingManifest?.etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = existingManifest?.lastModified, !lastModified.isEmpty {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
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
        let shapesURL = extractionDirectory.appendingPathComponent("shapes.txt")
        let stopsURL = extractionDirectory.appendingPathComponent("stops.txt")
        let stopTimesURL = extractionDirectory.appendingPathComponent("stop_times.txt")

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

        return try parseStaticData(
            tripsURL: tripsURL,
            shapesURL: shapesURL,
            stopsURL: stopsURL,
            stopTimesURL: stopTimesURL
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
            savedAt: Date()
        )
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: manifestURL, options: .atomic)
    }

    private func loadPersistedStaticDataIfAvailable() -> GTFSStaticData? {
        guard loadPersistedManifestIfAvailable() != nil else { return nil }
        guard FileManager.default.fileExists(atPath: payloadURL.path) else { return nil }

        do {
            let payloadData = try Data(contentsOf: payloadURL)
            let payload = try PropertyListDecoder().decode(GTFSStaticCachePayload.self, from: payloadData)
            return payload.toStaticData()
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
        shapesURL: URL,
        stopsURL: URL,
        stopTimesURL: URL
    ) throws -> GTFSStaticData {
        let tripsText = try String(contentsOf: tripsURL, encoding: .utf8)
        let shapesText = try String(contentsOf: shapesURL, encoding: .utf8)
        let stopsText = try String(contentsOf: stopsURL, encoding: .utf8)
        let stopTimesText = try String(contentsOf: stopTimesURL, encoding: .utf8)

        let trips = GTFSParsers.parseTrips(tripsText)
        let shapesByID = GTFSParsers.parseShapes(shapesText)
        let stopsByID = GTFSParsers.parseStops(stopsText)
        let routeStops = GTFSParsers.parseRouteStops(
            stopTimesText: stopTimesText,
            representativeTripByRoute: trips.representativeTripByRoute,
            routeByTripID: trips.routeByTripID,
            stopsByID: stopsByID
        )

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
            shapeCoordinatesByID: shapeCoordinatesByID,
            routeShapeIDsByKey: routeShapeIDsByKey,
            routeDirectionLabels: trips.directionLabelByRoute
        )
    }
}
