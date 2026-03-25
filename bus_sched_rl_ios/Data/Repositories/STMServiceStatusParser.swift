import Foundation

struct STMServiceStatusParser {
    static func parseAlerts(from data: Data, referenceDate: Date = Date()) -> [ServiceAlert] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }

        return extractRecords(from: json).compactMap { record in
            parseAlert(from: record, referenceDate: referenceDate)
        }
    }

    private static func parseAlert(
        from record: [String: Any],
        referenceDate: Date
    ) -> ServiceAlert? {
        let title = firstString(
            in: record,
            keys: ["title", "titre", "subject", "objet", "nom", "name", "status", "etat"]
        ) ?? "STM service notice"

        let message = firstString(
            in: record,
            keys: ["message", "texte", "description", "detail", "details", "contenu", "body", "resume"]
        )

        let activePeriods = parseActivePeriods(from: record)
        let alert = ServiceAlert(
            id: firstString(in: record, keys: ["id", "identifiant", "messageId", "code", "uid"])
                ?? derivedID(title: title, message: message, activePeriods: activePeriods),
            source: .stmServiceStatus,
            title: title,
            message: message,
            severity: parseSeverity(from: record, title: title, message: message),
            causeText: firstString(in: record, keys: ["cause", "causeText", "raison", "motif"]),
            effectText: firstString(in: record, keys: ["effect", "effectText", "effet", "impact", "impactText"]),
            url: firstURL(in: record, keys: ["url", "link", "lien"]),
            activePeriods: activePeriods,
            scopes: parseScopes(from: record)
        )

        guard alert.isActive(at: referenceDate) else { return nil }
        return alert
    }

    private static func extractRecords(from json: Any) -> [[String: Any]] {
        if let records = json as? [[String: Any]] {
            return records
        }

        guard let dictionary = json as? [String: Any] else { return [] }
        if looksLikeRecord(dictionary) {
            return [dictionary]
        }

        let candidateArrays = dictionary.values.compactMap { value -> [[String: Any]]? in
            if let records = value as? [[String: Any]] {
                return records
            }
            return nil
        }

        if let first = candidateArrays.first(where: { !$0.isEmpty }) {
            return first
        }

        return dictionary.values.compactMap { value -> [String: Any]? in
            guard let record = value as? [String: Any], looksLikeRecord(record) else { return nil }
            return record
        }
    }

    private static func looksLikeRecord(_ record: [String: Any]) -> Bool {
        let keys = Set(record.keys.map(normalizeKey))
        return !keys.isDisjoint(with: [
            "title", "titre", "message", "texte", "description", "severity", "severite",
            "line", "ligne", "route", "etat", "status"
        ])
    }

    private static func parseSeverity(
        from record: [String: Any],
        title: String,
        message: String?
    ) -> AlertSeverity {
        let explicit = firstString(
            in: record,
            keys: ["severity", "severite", "level", "niveau", "priority", "priorite", "type", "statusType"]
        ) ?? ""
        let combined = [explicit, title, message ?? ""]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        if containsAny(combined, [
            "severe", "critical", "major", "interruption", "suspend", "fermeture",
            "cancel", "annul", "shutdown", "strike", "greve"
        ]) {
            return .severe
        }
        if containsAny(combined, [
            "warning", "delay", "retard", "detour", "perturb", "slow", "advisory", "reroute"
        ]) {
            return .warning
        }
        return .info
    }

    private static func parseScopes(from record: [String: Any]) -> [AlertScopeSelector] {
        let routeIDs = strings(
            in: record,
            keys: ["routeID", "route_id", "route", "routes", "line", "lines", "ligne", "lignes", "ligneId", "ligne_id"]
        )
        let directionIDs = strings(
            in: record,
            keys: ["directionID", "direction_id", "direction"]
        )
        let stopIDs = strings(
            in: record,
            keys: ["stopID", "stop_id", "stop", "stops", "arret", "arrets", "arretId", "arret_id"]
        )

        let routeValues = routeIDs.isEmpty ? [nil] : routeIDs.map(Optional.some)
        let directionValues = directionIDs.isEmpty ? [nil] : directionIDs.map(Optional.some)
        let stopValues = stopIDs.isEmpty ? [nil] : stopIDs.map(Optional.some)

        let scopes = routeValues.flatMap { routeID in
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

        return Array(Set(scopes)).sorted {
            ($0.routeID ?? "", $0.directionID ?? "", $0.stopID ?? "") <
                ($1.routeID ?? "", $1.directionID ?? "", $1.stopID ?? "")
        }
    }

    private static func parseActivePeriods(from record: [String: Any]) -> [DateInterval] {
        if let start = firstDate(in: record, keys: ["start", "dateStart", "dateDebut", "debut", "from", "dh_debut"]),
           let end = firstDate(in: record, keys: ["end", "dateEnd", "dateFin", "fin", "to", "dh_fin"]) {
            return [DateInterval(start: min(start, end), end: max(start, end))]
        }

        if let start = firstDate(in: record, keys: ["start", "dateStart", "dateDebut", "debut", "from", "dh_debut"]) {
            return [DateInterval(start: start, duration: 365 * 24 * 60 * 60)]
        }

        return []
    }

    private static func firstString(in record: [String: Any], keys: [String]) -> String? {
        strings(in: record, keys: keys).first
    }

    private static func firstURL(in record: [String: Any], keys: [String]) -> URL? {
        guard let string = firstString(in: record, keys: keys) else { return nil }
        return URL(string: string)
    }

    private static func firstDate(in record: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            guard let value = value(forKey: key, in: record) else { continue }
            if let date = parseDate(value) {
                return date
            }
        }
        return nil
    }

    private static func strings(in record: [String: Any], keys: [String]) -> [String] {
        var results: [String] = []
        for key in keys {
            guard let value = value(forKey: key, in: record) else { continue }
            collectStrings(from: value, into: &results)
        }

        return Array(
            Set(
                results
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
    }

    private static func value(forKey key: String, in record: [String: Any]) -> Any? {
        let normalizedTarget = normalizeKey(key)
        if let direct = record[key] {
            return direct
        }
        return record.first { normalizeKey($0.key) == normalizedTarget }?.value
    }

    private static func collectStrings(from value: Any, into results: inout [String]) {
        switch value {
        case let string as String:
            results.append(string)
        case let number as NSNumber:
            results.append(number.stringValue)
        case let array as [Any]:
            array.forEach { collectStrings(from: $0, into: &results) }
        case let dictionary as [String: Any]:
            for key in ["id", "code", "name", "nom", "title", "titre", "value", "valeur"] {
                if let nested = self.value(forKey: key, in: dictionary) {
                    collectStrings(from: nested, into: &results)
                    return
                }
            }
        default:
            break
        }
    }

    private static func parseDate(_ value: Any) -> Date? {
        if let number = value as? NSNumber {
            let timestamp = number.doubleValue
            if timestamp > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: timestamp / 1000)
            }
            if timestamp > 0 {
                return Date(timeIntervalSince1970: timestamp)
            }
        }

        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let timestamp = Double(trimmed) {
            if timestamp > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: timestamp / 1000)
            }
            if timestamp > 0 {
                return Date(timeIntervalSince1970: timestamp)
            }
        }

        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601.date(from: trimmed) {
            return date
        }
        let fallbackISO8601 = ISO8601DateFormatter()
        if let date = fallbackISO8601.date(from: trimmed) {
            return date
        }

        let formatters = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd"
        ].map { format -> DateFormatter in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }

        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    private static func derivedID(title: String, message: String?, activePeriods: [DateInterval]) -> String {
        let periodText = activePeriods.map { "\($0.start.timeIntervalSince1970)-\($0.end.timeIntervalSince1970)" }
            .joined(separator: "|")
        return "stm-\(abs([title, message ?? "", periodText].joined(separator: "|").hashValue))"
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func normalizeKey(_ key: String) -> String {
        key
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }
}
