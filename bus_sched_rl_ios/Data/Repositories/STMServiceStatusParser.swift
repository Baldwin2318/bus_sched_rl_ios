import Foundation

struct STMServiceStatusParser {
    static func parseAlerts(from data: Data, referenceDate: Date = Date()) -> [ServiceAlert] {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            return []
        }

        return response.alerts.compactMap { alert in
            let activePeriods = alert.activePeriods.values.compactMap(\.dateInterval)
            let parsedDescription = parsedMessage(from: alert.descriptionTexts)
            let serviceAlert = ServiceAlert(
                id: derivedID(for: alert),
                source: .stmServiceStatus,
                title: preferredText(from: alert.headerTexts) ?? "STM service notice",
                message: parsedDescription.message,
                severity: severity(for: alert),
                causeText: normalized(alert.cause),
                effectText: normalized(alert.effect),
                url: parsedDescription.url,
                activePeriods: activePeriods,
                scopes: scopes(for: alert.informedEntities)
            )

            guard serviceAlert.isActive(at: referenceDate) else { return nil }
            guard shouldInclude(serviceAlert) else { return nil }
            return serviceAlert
        }
    }

    private static func preferredText(from texts: [LocalizedText]) -> String? {
        let preferredLanguageOrder = ["en", "fr"]

        for language in preferredLanguageOrder {
            if let text = texts.first(where: {
                $0.language?.lowercased() == language && normalized($0.text) != nil
            })?.text,
               let normalizedText = normalized(text) {
                return normalizedText
            }
        }

        return texts.lazy.compactMap { normalized($0.text) }.first
    }

    private static func parsedMessage(from texts: [LocalizedText]) -> (message: String?, url: URL?) {
        let preferredLanguageOrder = ["en", "fr"]

        for language in preferredLanguageOrder {
            if let text = texts.first(where: { $0.language?.lowercased() == language })?.text,
               let parsed = parsedHTML(text),
               parsed.message != nil || parsed.url != nil {
                return parsed
            }
        }

        for text in texts.compactMap(\.text) {
            if let parsed = parsedHTML(text),
               parsed.message != nil || parsed.url != nil {
                return parsed
            }
        }

        return (message: nil, url: nil)
    }

    private static func scopes(for entities: [InformedEntity]) -> [AlertScopeSelector] {
        let routeIDs = Set(entities.compactMap { normalized($0.routeShortName) })
        let directionIDs = Set(entities.compactMap { normalized($0.directionID) })
        let stopIDs = Set(entities.compactMap { normalized($0.stopCode) })

        if routeIDs.isEmpty && directionIDs.isEmpty && stopIDs.isEmpty {
            return []
        }

        let routeValues = routeIDs.isEmpty ? [nil] : routeIDs.sorted().map(Optional.some)
        let directionValues = directionIDs.isEmpty ? [nil] : directionIDs.sorted().map(Optional.some)
        let stopValues = stopIDs.isEmpty ? [nil] : stopIDs.sorted().map(Optional.some)

        let selectors = routeValues.flatMap { routeID in
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

        return Array(Set(selectors)).sorted {
            ($0.routeID ?? "", $0.directionID ?? "", $0.stopID ?? "") <
                ($1.routeID ?? "", $1.directionID ?? "", $1.stopID ?? "")
        }
    }

    private static func severity(for alert: AlertPayload) -> AlertSeverity {
        let combined = [
            preferredText(from: alert.headerTexts) ?? "",
            preferredText(from: alert.descriptionTexts) ?? "",
            normalized(alert.effect) ?? "",
            normalized(alert.cause) ?? ""
        ]
        .joined(separator: " ")
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        if containsAny(combined, [
            "normal service", "service normal", "weekends and holidays", "week-ends et les jours feries"
        ]) {
            return .info
        }
        if containsAny(combined, [
            "cancelled", "annule", "suspend", "ferme", "closed", "shutdown", "interruption", "strike", "greve"
        ]) {
            return .severe
        }
        if containsAny(combined, [
            "moved", "deplace", "relocate", "relocalise", "delay", "retard", "construction", "travaux"
        ]) {
            return .warning
        }
        return .info
    }

    private static func shouldInclude(_ alert: ServiceAlert) -> Bool {
        let combined = [alert.title, alert.message ?? ""]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        if containsAny(combined, [
            "service normal du metro",
            "normal metro service"
        ]) {
            return false
        }

        return true
    }

    private static func derivedID(for alert: AlertPayload) -> String {
        let title = preferredText(from: alert.headerTexts) ?? ""
        let message = parsedMessage(from: alert.descriptionTexts).message ?? ""
        let scope = scopes(for: alert.informedEntities).map {
            [
                $0.routeID ?? "",
                $0.directionID ?? "",
                $0.stopID ?? ""
            ].joined(separator: ":")
        }.joined(separator: "|")
        let periods = alert.activePeriods.values.compactMap(\.dateInterval).map {
            "\($0.start.timeIntervalSince1970)-\($0.end.timeIntervalSince1970)"
        }.joined(separator: "|")

        return "stm-\(abs([title, message, scope, periods].joined(separator: "|").hashValue))"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parsedHTML(_ value: String?) -> (message: String?, url: URL?)? {
        guard let normalizedValue = normalized(value) else { return nil }

        let nsValue = normalizedValue as NSString
        let hrefPattern = #"href\s*=\s*"([^"]+)""#
        let hrefRegex = try? NSRegularExpression(pattern: hrefPattern, options: [.caseInsensitive])
        let hrefRange = NSRange(location: 0, length: nsValue.length)
        let extractedURL: URL?
        if let match = hrefRegex?.firstMatch(in: normalizedValue, options: [], range: hrefRange),
           match.numberOfRanges > 1 {
            let urlString = nsValue.substring(with: match.range(at: 1))
            extractedURL = URL(string: urlString)
        } else {
            extractedURL = nil
        }

        if normalizedValue.contains("<"), normalizedValue.contains(">"),
           let data = normalizedValue.data(using: .utf8),
           let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
           ) {
            let plainText = normalized(attributed.string.replacingOccurrences(of: "\u{00A0}", with: " "))
            return (message: plainText, url: extractedURL)
        }

        return (message: normalizedValue, url: extractedURL)
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

private extension STMServiceStatusParser {
    struct Response: Decodable {
        let header: Header?
        let alerts: [AlertPayload]
    }

    struct Header: Decodable {
        let timestamp: TimeInterval?
    }

    struct AlertPayload: Decodable {
        let activePeriods: ActivePeriods
        let cause: String?
        let effect: String?
        let informedEntities: [InformedEntity]
        let headerTexts: [LocalizedText]
        let descriptionTexts: [LocalizedText]

        enum CodingKeys: String, CodingKey {
            case activePeriods = "active_periods"
            case cause
            case effect
            case informedEntities = "informed_entities"
            case headerTexts = "header_texts"
            case descriptionTexts = "description_texts"
        }
    }

    struct ActivePeriods: Decodable {
        let values: [ActivePeriod]

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let single = try? container.decode(ActivePeriod.self) {
                values = [single]
            } else {
                values = try container.decode([ActivePeriod].self)
            }
        }
    }

    struct ActivePeriod: Decodable {
        let start: TimeInterval?
        let end: TimeInterval?

        var dateInterval: DateInterval? {
            guard let start else { return nil }
            let startDate = Date(timeIntervalSince1970: start)
            let endDate = Date(timeIntervalSince1970: end ?? (start + 365 * 24 * 60 * 60))
            return DateInterval(start: min(startDate, endDate), end: max(startDate, endDate))
        }
    }

    struct InformedEntity: Decodable {
        let routeShortName: String?
        let directionID: String?
        let stopCode: String?

        enum CodingKeys: String, CodingKey {
            case routeShortName = "route_short_name"
            case directionID = "direction_id"
            case stopCode = "stop_code"
        }
    }

    struct LocalizedText: Decodable {
        let language: String?
        let text: String?
    }
}
