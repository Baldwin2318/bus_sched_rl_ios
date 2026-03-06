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

actor LiveGTFSRepository: GTFSRepository {
    private let gtfsURL = URL(string: "https://www.stm.info/sites/default/files/gtfs/gtfs_stm.zip")!
    private let cacheDirectory: URL
    private var cachedData: GTFSStaticData?

    init(cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("gtfs_temp", isDirectory: true)) {
        self.cacheDirectory = cacheDirectory
    }

    func loadStaticData() async throws -> GTFSStaticData {
        if let cachedData {
            return cachedData
        }

        let (tempURL, _) = try await URLSession.shared.download(from: gtfsURL)
        try resetDirectory()
        try FileManager.default.unzipItem(at: tempURL, to: cacheDirectory)

        let tripsURL = cacheDirectory.appendingPathComponent("trips.txt")
        let shapesURL = cacheDirectory.appendingPathComponent("shapes.txt")
        let stopsURL = cacheDirectory.appendingPathComponent("stops.txt")
        let stopTimesURL = cacheDirectory.appendingPathComponent("stop_times.txt")

        guard FileManager.default.fileExists(atPath: tripsURL.path),
              FileManager.default.fileExists(atPath: shapesURL.path),
              FileManager.default.fileExists(atPath: stopsURL.path),
              FileManager.default.fileExists(atPath: stopTimesURL.path) else {
            throw NSError(domain: "GTFSRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing GTFS files after extraction"])
        }

        let parsed = try parseStaticData(
            tripsURL: tripsURL,
            shapesURL: shapesURL,
            stopsURL: stopsURL,
            stopTimesURL: stopTimesURL
        )
        cachedData = parsed
        return parsed
    }

    private func resetDirectory() throws {
        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try FileManager.default.removeItem(at: cacheDirectory)
        }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
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
