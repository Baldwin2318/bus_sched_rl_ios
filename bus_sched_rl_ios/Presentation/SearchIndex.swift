import Foundation
import CoreLocation

struct SearchIndex {
    private struct SearchBucket {
        let routeIndexes: [Int]
        let stopIndexes: [Int]
    }

    private struct RouteMatchEvaluation {
        let tier: Int
        let direction: RouteDirectionSearchEntry?
    }

    private struct CandidateIndexes {
        let routeIndexes: Set<Int>
        let stopIndexes: Set<Int>
    }

    private struct NormalizedDirection {
        let direction: RouteDirectionSearchEntry
        let normalizedText: String
    }

    private struct NormalizedRoute {
        let shortName: String
        let longName: String
        let directions: [NormalizedDirection]
    }

    private let routes: [RouteSearchEntry]
    private let stops: [StopSearchEntry]
    private let normalizedRoutes: [NormalizedRoute]
    private let normalizedStops: [String]
    private let routeIndexesByStopIndex: [[Int]]
    private let prefixBuckets: [String: SearchBucket]

    init(routes: [RouteSearchEntry], stops: [StopSearchEntry]) {
        self.routes = routes
        self.stops = stops
        self.normalizedRoutes = routes.map { route in
            NormalizedRoute(
                shortName: Self.normalize(route.routeShortName),
                longName: Self.normalize(route.routeLongName),
                directions: route.directionOptions.map { direction in
                    NormalizedDirection(
                        direction: direction,
                        normalizedText: Self.normalize(direction.directionText)
                    )
                }
            )
        }
        self.normalizedStops = stops.map { Self.normalize($0.stopName) }

        var routeIndexByRouteID: [String: Int] = [:]
        for (index, route) in routes.enumerated() {
            routeIndexByRouteID[route.routeId] = index
        }

        self.routeIndexesByStopIndex = stops.map { stop in
            stop.nearbyRouteIds.compactMap { routeIndexByRouteID[$0] }
        }

        var routeBuckets: [String: Set<Int>] = [:]
        var stopBuckets: [String: Set<Int>] = [:]

        for (routeIndex, route) in routes.enumerated() {
            let searchableValues = [route.routeId, route.routeShortName, route.routeLongName] + route.directionOptions.map(\.directionText)
            let tokens = Self.prefixTokens(for: searchableValues)
            for token in tokens {
                routeBuckets[token, default: []].insert(routeIndex)
            }
        }

        for (stopIndex, stop) in stops.enumerated() {
            let tokens = Self.prefixTokens(for: [stop.stopName])
            for token in tokens {
                stopBuckets[token, default: []].insert(stopIndex)
            }
        }

        var buckets: [String: SearchBucket] = [:]
        let allKeys = Set(routeBuckets.keys).union(stopBuckets.keys)
        for key in allKeys {
            let routeIndexes = Array(routeBuckets[key] ?? []).sorted()
            let stopIndexes = Array(stopBuckets[key] ?? []).sorted()
            buckets[key] = SearchBucket(routeIndexes: routeIndexes, stopIndexes: stopIndexes)
        }

        prefixBuckets = buckets
    }

    func search(query: String, userLocation _: CLLocationCoordinate2D?, limit: Int) -> [SearchResult] {
        let normalizedQuery = Self.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let queryTokens = Self.queryTokens(from: normalizedQuery)
        guard !queryTokens.isEmpty else { return [] }
        guard let candidates = candidateIndexes(for: queryTokens) else { return [] }

        let routeIndexes = candidates.routeIndexes.sorted()
        var rankedRoutesByIdentity: [String: (tier: Int, route: RouteSearchMatch)] = [:]
        rankedRoutesByIdentity.reserveCapacity(routeIndexes.count)

        for routeIndex in routeIndexes {
            let route = routes[routeIndex]
            let normalizedRoute = normalizedRoutes[routeIndex]
            let evaluations = Self.evaluateRouteMatches(tokens: queryTokens, route: normalizedRoute)
            guard !evaluations.isEmpty else {
                continue
            }

            for evaluation in evaluations {
                let routeMatch = RouteSearchMatch(
                    route: route,
                    directionId: evaluation.direction?.directionId,
                    directionText: evaluation.direction?.directionText,
                    distanceMeters: nil
                )
                let identity = Self.routeMatchIdentity(
                    routeID: route.routeId,
                    directionID: routeMatch.directionId
                )
                if let existing = rankedRoutesByIdentity[identity],
                   existing.tier <= evaluation.tier {
                    continue
                }
                rankedRoutesByIdentity[identity] = (tier: evaluation.tier, route: routeMatch)
            }
        }

        var rankedRoutes = Array(rankedRoutesByIdentity.values)
        rankedRoutes.sort { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            let routeNumberComparison = lhs.route.route.routeShortName
                .localizedStandardCompare(rhs.route.route.routeShortName)
            if routeNumberComparison != .orderedSame {
                return routeNumberComparison == .orderedAscending
            }
            let routeIDComparison = lhs.route.route.routeId
                .localizedStandardCompare(rhs.route.route.routeId)
            if routeIDComparison != .orderedSame {
                return routeIDComparison == .orderedAscending
            }
            let lhsDirection = lhs.route.directionText?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let rhsDirection = rhs.route.directionText?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let directionComparison = lhsDirection.localizedStandardCompare(rhsDirection)
            if directionComparison != .orderedSame {
                return directionComparison == .orderedAscending
            }
            return (lhs.route.directionId ?? "")
                .localizedStandardCompare(rhs.route.directionId ?? "") == .orderedAscending
        }

        let stopIndexes = candidates.stopIndexes.sorted()
        var stopMatches: [(tier: Int, stop: StopSearchMatch)] = []
        stopMatches.reserveCapacity(stopIndexes.count)
        for stopIndex in stopIndexes {
            let normalizedStopName = normalizedStops[stopIndex]
            guard let tier = Self.evaluateStopMatch(tokens: queryTokens, stopName: normalizedStopName) else {
                continue
            }
            stopMatches.append((tier: tier, stop: StopSearchMatch(stop: stops[stopIndex], distanceMeters: nil)))
        }

        stopMatches.sort { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            return lhs.stop.stop.stopName.localizedStandardCompare(rhs.stop.stop.stopName) == .orderedAscending
        }

        var results: [SearchResult] = rankedRoutes.map { .route($0.route) }
        results.append(contentsOf: stopMatches.map { .stop($0.stop) })
        if results.count > limit {
            return Array(results.prefix(limit))
        }
        return results
    }

    func nearbyRoutes(around location: CLLocationCoordinate2D?, limit: Int) -> [RouteSearchMatch] {
        guard let location else { return [] }

        var minDistanceByRouteIndex: [Int: CLLocationDistance] = [:]
        minDistanceByRouteIndex.reserveCapacity(routes.count)

        for (stopIndex, stop) in stops.enumerated() {
            let distance = Self.planarDistanceMeters(from: location, to: stop.coordinate)
            let routeIndexes = routeIndexesByStopIndex[stopIndex]
            for routeIndex in routeIndexes {
                if let current = minDistanceByRouteIndex[routeIndex], current <= distance {
                    continue
                }
                minDistanceByRouteIndex[routeIndex] = distance
            }
        }

        var nearby: [RouteSearchMatch] = []
        nearby.reserveCapacity(minDistanceByRouteIndex.count)

        for (routeIndex, distance) in minDistanceByRouteIndex {
            guard routes.indices.contains(routeIndex) else { continue }
            let route = routes[routeIndex]
            let distanceMeters = max(0, Int(round(distance)))

            if route.directionOptions.isEmpty {
                nearby.append(
                    RouteSearchMatch(
                        route: route,
                        directionId: nil,
                        directionText: nil,
                        distanceMeters: distanceMeters
                    )
                )
                continue
            }

            for direction in route.directionOptions {
                nearby.append(
                    RouteSearchMatch(
                        route: route,
                        directionId: direction.directionId,
                        directionText: direction.directionText,
                        distanceMeters: distanceMeters
                    )
                )
            }
        }

        nearby.sort { lhs, rhs in
            let lhsDistance = lhs.distanceMeters ?? Int.max
            let rhsDistance = rhs.distanceMeters ?? Int.max
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            let routeNumberComparison = lhs.route.routeShortName.localizedStandardCompare(rhs.route.routeShortName)
            if routeNumberComparison != .orderedSame {
                return routeNumberComparison == .orderedAscending
            }
            let routeIDComparison = lhs.route.routeId.localizedStandardCompare(rhs.route.routeId)
            if routeIDComparison != .orderedSame {
                return routeIDComparison == .orderedAscending
            }
            let lhsDirection = lhs.directionText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let rhsDirection = rhs.directionText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let directionComparison = lhsDirection.localizedStandardCompare(rhsDirection)
            if directionComparison != .orderedSame {
                return directionComparison == .orderedAscending
            }
            return (lhs.directionId ?? "").localizedStandardCompare(rhs.directionId ?? "") == .orderedAscending
        }

        var deduplicatedNearby: [RouteSearchMatch] = []
        deduplicatedNearby.reserveCapacity(nearby.count)
        var seenIdentities: Set<String> = []
        for match in nearby {
            let identity = Self.routeMatchIdentity(
                routeID: match.route.routeId,
                directionID: match.directionId
            )
            guard seenIdentities.insert(identity).inserted else {
                continue
            }
            deduplicatedNearby.append(match)
        }

        if deduplicatedNearby.count > limit {
            return Array(deduplicatedNearby.prefix(limit))
        }
        return deduplicatedNearby
    }

    private func candidateIndexes(for tokens: [String]) -> CandidateIndexes? {
        var routeCandidates: Set<Int>?
        var stopCandidates: Set<Int>?

        for token in tokens {
            let prefixKey = String(token.prefix(min(3, token.count)))
            guard let bucket = prefixBuckets[prefixKey] else {
                return nil
            }

            let routeSet = Set(bucket.routeIndexes)
            let stopSet = Set(bucket.stopIndexes)

            if let existingRouteCandidates = routeCandidates {
                routeCandidates = existingRouteCandidates.intersection(routeSet)
            } else {
                routeCandidates = routeSet
            }

            if let existingStopCandidates = stopCandidates {
                stopCandidates = existingStopCandidates.intersection(stopSet)
            } else {
                stopCandidates = stopSet
            }

            if (routeCandidates?.isEmpty ?? true) && (stopCandidates?.isEmpty ?? true) {
                return nil
            }
        }

        return CandidateIndexes(
            routeIndexes: routeCandidates ?? [],
            stopIndexes: stopCandidates ?? []
        )
    }

    private static func evaluateRouteMatches(tokens: [String], route: NormalizedRoute) -> [RouteMatchEvaluation] {
        let directionCandidates: [NormalizedDirection?] = route.directions.isEmpty
            ? [nil]
            : route.directions.map(Optional.some)

        var evaluations: [RouteMatchEvaluation] = []
        evaluations.reserveCapacity(directionCandidates.count)

        for directionCandidate in directionCandidates {
            var bestTier: Int?
            var matchesAllTokens = true

            for token in tokens {
                if route.shortName == token {
                    bestTier = min(bestTier ?? 1, 1)
                    continue
                }

                if route.shortName.hasPrefix(token) {
                    bestTier = min(bestTier ?? 2, 2)
                    continue
                }

                if route.longName.hasPrefix(token) {
                    bestTier = min(bestTier ?? 3, 3)
                    continue
                }

                if route.longName.contains(token) {
                    bestTier = min(bestTier ?? 4, 4)
                    continue
                }

                if let directionCandidate,
                   directionCandidate.normalizedText.contains(token) {
                    bestTier = min(bestTier ?? 5, 5)
                    continue
                }

                matchesAllTokens = false
                break
            }

            guard matchesAllTokens, let tier = bestTier else {
                continue
            }

            evaluations.append(
                RouteMatchEvaluation(
                    tier: tier,
                    direction: directionCandidate?.direction
                )
            )
        }

        return evaluations
    }

    private static func routeMatchIdentity(routeID: String, directionID: String?) -> String {
        "\(routeID):\(directionID ?? "_")"
    }

    private static func evaluateStopMatch(tokens: [String], stopName: String) -> Int? {
        var bestTier: Int?

        for token in tokens {
            if stopName.hasPrefix(token) {
                bestTier = min(bestTier ?? 6, 6)
                continue
            }

            if stopName.contains(token) {
                bestTier = min(bestTier ?? 7, 7)
                continue
            }

            return nil
        }

        return bestTier
    }

    private static func normalize(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func queryTokens(from normalizedQuery: String) -> [String] {
        normalizedQuery
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func prefixTokens(for values: [String]) -> Set<String> {
        var tokens: Set<String> = []

        for value in values {
            let normalizedValue = normalize(value)
            guard !normalizedValue.isEmpty else { continue }

            let parts = normalizedValue
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)

            for part in parts where !part.isEmpty {
                addSearchPrefixes(from: part, into: &tokens)
            }
        }

        return tokens
    }

    private static func addSearchPrefixes(from part: String, into tokens: inout Set<String>) {
        var start = part.startIndex
        while start < part.endIndex {
            for length in 1...3 {
                guard let end = part.index(start, offsetBy: length, limitedBy: part.endIndex) else {
                    break
                }
                tokens.insert(String(part[start..<end]))
            }
            start = part.index(after: start)
        }
    }

    private static func planarDistanceMeters(
        from lhs: CLLocationCoordinate2D,
        to rhs: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let latMeters = 111_132.92
        let avgLatitude = (lhs.latitude + rhs.latitude) * 0.5
        let lonMeters = max(1.0, 111_412.84 * cos(avgLatitude * .pi / 180))
        let dx = (rhs.longitude - lhs.longitude) * lonMeters
        let dy = (rhs.latitude - lhs.latitude) * latMeters
        return sqrt(dx * dx + dy * dy)
    }
}

actor SearchLookupActor {
    private let index: SearchIndex

    init(index: SearchIndex) {
        self.index = index
    }

    func search(query: String, userLocation: CLLocationCoordinate2D?, limit: Int) -> [SearchResult] {
        index.search(query: query, userLocation: userLocation, limit: limit)
    }

    func nearbyRoutes(around location: CLLocationCoordinate2D?, limit: Int) -> [RouteSearchMatch] {
        index.nearbyRoutes(around: location, limit: limit)
    }
}

struct SearchIndexBuilder {
    static func build(from staticData: GTFSStaticData) -> SearchIndex {
        var routeIDs: Set<String> = Set(staticData.availableRoutes)
        routeIDs.formUnion(staticData.routeNamesByRouteID.keys)
        routeIDs.formUnion(staticData.routeStylesByRouteID.keys)
        routeIDs.formUnion(staticData.routeStops.keys.map(\.route))
        routeIDs.formUnion(staticData.routeDirectionLabels.keys.map(\.route))

        var routeDirectionTextByRouteID: [String: [String: String]] = [:]
        for (routeKey, directionLabel) in staticData.routeDirectionLabels {
            let normalizedLabel = directionLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedLabel.isEmpty else { continue }
            var labelsByDirection = routeDirectionTextByRouteID[routeKey.route] ?? [:]
            if labelsByDirection[routeKey.direction] == nil {
                labelsByDirection[routeKey.direction] = normalizedLabel
            }
            routeDirectionTextByRouteID[routeKey.route] = labelsByDirection
        }

        let sortedRouteIDs = routeIDs.sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        let routes: [RouteSearchEntry] = sortedRouteIDs.map { routeID in
            let metadata = staticData.routeNamesByRouteID[routeID]
            let shortName = metadata?.shortName.trimmingCharacters(in: .whitespacesAndNewlines)
            let longName = metadata?.longName.trimmingCharacters(in: .whitespacesAndNewlines)
            let directionOptions = (routeDirectionTextByRouteID[routeID] ?? [:])
                .map { directionID, directionText in
                    RouteDirectionSearchEntry(
                        directionId: directionID,
                        directionText: directionText
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.directionId != rhs.directionId {
                        return lhs.directionId.localizedStandardCompare(rhs.directionId) == .orderedAscending
                    }
                    return lhs.directionText.localizedStandardCompare(rhs.directionText) == .orderedAscending
                }

            return RouteSearchEntry(
                routeId: routeID,
                routeShortName: (shortName?.isEmpty == false ? shortName! : routeID),
                routeLongName: (longName?.isEmpty == false ? longName! : routeID),
                routeColor: staticData.routeStylesByRouteID[routeID]?.routeColorHex,
                directionOptions: directionOptions
            )
        }

        var stopsByID: [String: BusStop] = [:]
        var nearbyRouteIDsByStopID: [String: Set<String>] = [:]

        for (routeKey, stops) in staticData.routeStops {
            for stop in stops {
                stopsByID[stop.id] = stop
                nearbyRouteIDsByStopID[stop.id, default: []].insert(routeKey.route)
            }
        }

        let stops: [StopSearchEntry] = stopsByID.values
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .map { stop in
                let nearbyRouteIDs = Array(nearbyRouteIDsByStopID[stop.id] ?? [])
                    .sorted { lhs, rhs in
                        lhs.localizedStandardCompare(rhs) == .orderedAscending
                    }

                return StopSearchEntry(
                    stopId: stop.id,
                    stopName: stop.name,
                    coordinate: stop.coord,
                    nearbyRouteIds: nearbyRouteIDs
                )
            }

        return SearchIndex(routes: routes, stops: stops)
    }
}
