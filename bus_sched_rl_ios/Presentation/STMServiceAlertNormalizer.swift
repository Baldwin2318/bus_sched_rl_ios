import Foundation

struct STMServiceAlertNormalizer {
    static func normalize(
        _ alerts: [ServiceAlert],
        staticData: GTFSStaticData,
        index: TransitDataIndex
    ) -> [ServiceAlert] {
        let context = Context(staticData: staticData, index: index)

        return alerts.map { alert in
            guard alert.source == .stmServiceStatus else { return alert }

            let normalizedScopes = alert.scopes.flatMap { context.normalize(scope: $0) }
            let finalScopes = normalizedScopes.isEmpty ? alert.scopes : Array(Set(normalizedScopes)).sorted {
                ($0.routeID ?? "", $0.directionID ?? "", $0.stopID ?? "") <
                    ($1.routeID ?? "", $1.directionID ?? "", $1.stopID ?? "")
            }

            return ServiceAlert(
                id: alert.id,
                source: alert.source,
                title: alert.title,
                message: alert.message,
                severity: alert.severity,
                causeText: alert.causeText,
                effectText: alert.effectText,
                url: alert.url,
                activePeriods: alert.activePeriods,
                scopes: finalScopes
            )
        }
    }
}

private extension STMServiceAlertNormalizer {
    struct Context {
        let routeIDsByShortName: [String: [String]]
        let routeKeysByRouteID: [String: [RouteKey]]
        let directionLabelsByRouteKey: [RouteKey: String]
        let stopIDsByCode: [String: [String]]
        let stopIDs: Set<String>

        init(staticData: GTFSStaticData, index: TransitDataIndex) {
            routeIDsByShortName = Dictionary(grouping: staticData.routeNamesByRouteID.keys) { routeID in
                Self.normalized(staticData.routeNamesByRouteID[routeID]?.shortName)
            }
            .reduce(into: [:]) { partialResult, entry in
                guard let key = entry.key else { return }
                partialResult[key] = entry.value.sorted {
                    $0.localizedStandardCompare($1) == .orderedAscending
                }
            }

            let routeKeys = Set(staticData.routeStops.keys)
                .union(staticData.routeStopSchedules.keys)
                .union(staticData.routeDirectionLabels.keys)
            routeKeysByRouteID = Dictionary(grouping: routeKeys, by: \.route)
                .mapValues { keys in
                    keys.sorted { lhs, rhs in
                        lhs.direction.localizedStandardCompare(rhs.direction) == .orderedAscending
                    }
                }

            directionLabelsByRouteKey = staticData.routeDirectionLabels
            stopIDsByCode = index.stopIDsByCode
            stopIDs = Set(index.allStopsByID.keys)
        }

        func normalize(scope: AlertScopeSelector) -> [AlertScopeSelector] {
            let routeIDs = resolveRouteIDs(from: scope.routeID)
            let stopIDs = resolveStopIDs(from: scope.stopID)

            let routeValues: [String?] = routeIDs.isEmpty ? [scope.routeID] : routeIDs.map(Optional.some)
            let stopValues: [String?] = stopIDs.isEmpty ? [scope.stopID] : stopIDs.map(Optional.some)

            let directionValues: [String?]
            if let rawDirectionID = scope.directionID {
                let resolvedDirectionIDs = routeValues
                    .compactMap { $0 }
                    .flatMap { resolveDirectionIDs(for: $0, rawDirectionID: rawDirectionID) }
                if resolvedDirectionIDs.isEmpty {
                    directionValues = [scope.directionID]
                } else {
                    directionValues = Array(Set(resolvedDirectionIDs))
                        .sorted()
                        .map(Optional.some)
                }
            } else {
                directionValues = [nil]
            }

            return routeValues.flatMap { routeID in
                directionValues.flatMap { directionID in
                    stopValues.map { stopID in
                        AlertScopeSelector(
                            routeID: routeID,
                            directionID: directionID,
                            stopID: stopID,
                            tripID: nil
                        )
                    }
                }
            }
        }

        private func resolveRouteIDs(from rawRouteID: String?) -> [String] {
            guard let rawRouteID = Self.normalized(rawRouteID) else { return [] }
            if routeKeysByRouteID[rawRouteID] != nil {
                return [rawRouteID]
            }
            return routeIDsByShortName[rawRouteID] ?? []
        }

        private func resolveStopIDs(from rawStopCode: String?) -> [String] {
            guard let rawStopCode = Self.normalized(rawStopCode) else { return [] }
            if stopIDs.contains(rawStopCode) {
                return [rawStopCode]
            }
            return stopIDsByCode[rawStopCode] ?? []
        }

        private func resolveDirectionIDs(for routeID: String, rawDirectionID: String) -> [String] {
            guard let rawDirectionID = Self.normalized(rawDirectionID),
                  let routeKeys = routeKeysByRouteID[routeID],
                  !routeKeys.isEmpty else {
                return []
            }

            if routeKeys.contains(where: { $0.direction == rawDirectionID }) {
                return [rawDirectionID]
            }

            guard let targetToken = Self.directionToken(for: rawDirectionID) else {
                return []
            }

            return routeKeys.filter { routeKey in
                guard let label = directionLabelsByRouteKey[routeKey] else { return false }
                return Self.directionToken(for: label) == targetToken
            }
            .map(\.direction)
        }

        private static func normalized(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        private static func directionToken(for value: String) -> String? {
            let normalizedValue = value
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            if normalizedValue == "n" || normalizedValue.contains("north") || normalizedValue.contains("nord") {
                return "n"
            }
            if normalizedValue == "s" || normalizedValue.contains("south") || normalizedValue.contains("sud") {
                return "s"
            }
            if normalizedValue == "e" || normalizedValue == "est" || normalizedValue.contains("east") {
                return "e"
            }
            if normalizedValue == "w" || normalizedValue == "o" || normalizedValue.contains("west") || normalizedValue.contains("ouest") {
                return "w"
            }
            return nil
        }
    }
}
