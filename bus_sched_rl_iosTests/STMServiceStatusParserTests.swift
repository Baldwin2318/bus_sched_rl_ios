import XCTest
@testable import bus_sched_rl_ios

final class STMServiceStatusParserTests: XCTestCase {
    func testParseAlertsUsesExactSTMHeaderAndDescriptionTexts() throws {
        let data = try XCTUnwrap(
            """
            {
              "header": { "timestamp": 1774408512 },
              "alerts": [
                {
                  "active_periods": { "start": 1773885300, "end": null },
                  "cause": null,
                  "effect": null,
                  "informed_entities": [
                    { "route_short_name": "10" },
                    { "direction_id": "N" },
                    { "stop_code": "53010" }
                  ],
                  "header_texts": [
                    { "language": "fr", "text": "Votre arrêt" },
                    { "language": "en", "text": "Your stop" }
                  ],
                  "description_texts": [
                    { "language": "fr", "text": "Cet arrêt est relocalisé." },
                    { "language": "en", "text": "This stop is relocated." }
                  ]
                }
              ]
            }
            """.data(using: .utf8)
        )

        let alerts = STMServiceStatusParser.parseAlerts(from: data)

        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.source, .stmServiceStatus)
        XCTAssertEqual(alerts.first?.title, "Your stop")
        XCTAssertEqual(alerts.first?.message, "This stop is relocated.")
        XCTAssertEqual(alerts.first?.severity, .warning)
        XCTAssertEqual(alerts.first?.scopes, [
            AlertScopeSelector(routeID: "10", directionID: "N", stopID: "53010", tripID: nil)
        ])
    }

    func testParseAlertsFallsBackToFrenchWhenEnglishMissing() throws {
        let data = try XCTUnwrap(
            """
            {
              "header": { "timestamp": 1774408512 },
              "alerts": [
                {
                  "active_periods": { "start": 1773885300, "end": null },
                  "cause": null,
                  "effect": null,
                  "informed_entities": [
                    { "route_short_name": "11" },
                    { "direction_id": "E" }
                  ],
                  "header_texts": [
                    { "language": "fr", "text": "Votre ligne" },
                    { "language": "en", "text": null }
                  ],
                  "description_texts": [
                    { "language": "fr", "text": "Certains arrêts sont annulés, déplacés ou relocalisés." },
                    { "language": "en", "text": null }
                  ]
                }
              ]
            }
            """.data(using: .utf8)
        )

        let alerts = STMServiceStatusParser.parseAlerts(from: data)

        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.title, "Votre ligne")
        XCTAssertEqual(alerts.first?.message, "Certains arrêts sont annulés, déplacés ou relocalisés.")
        XCTAssertEqual(alerts.first?.severity, .warning)
    }

    func testParseAlertsCombinesSeparateStopCodesIntoScopedSelectors() throws {
        let data = try XCTUnwrap(
            """
            {
              "header": { "timestamp": 1774408512 },
              "alerts": [
                {
                  "active_periods": { "start": 1773885300, "end": null },
                  "cause": null,
                  "effect": null,
                  "informed_entities": [
                    { "route_short_name": "10" },
                    { "direction_id": "N" },
                    { "stop_code": "53010" },
                    { "stop_code": "53045" }
                  ],
                  "header_texts": [
                    { "language": "en", "text": "Your line" }
                  ],
                  "description_texts": [
                    { "language": "en", "text": "Some stops are moved." }
                  ]
                }
              ]
            }
            """.data(using: .utf8)
        )

        let alerts = STMServiceStatusParser.parseAlerts(from: data)

        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(Set(alerts[0].scopes), Set([
            AlertScopeSelector(routeID: "10", directionID: "N", stopID: "53010", tripID: nil),
            AlertScopeSelector(routeID: "10", directionID: "N", stopID: "53045", tripID: nil)
        ]))
    }

    func testParseAlertsDropsExpiredSTMNotice() throws {
        let data = try XCTUnwrap(
            """
            {
              "header": { "timestamp": 1774408512 },
              "alerts": [
                {
                  "active_periods": { "start": 1735689600, "end": 1735696800 },
                  "cause": null,
                  "effect": null,
                  "informed_entities": [
                    { "route_short_name": "55" }
                  ],
                  "header_texts": [
                    { "language": "en", "text": "Your line" }
                  ],
                  "description_texts": [
                    { "language": "en", "text": "This stop is moved." }
                  ]
                }
              ]
            }
            """.data(using: .utf8)
        )

        let referenceDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-01-01T12:00:00Z"))
        let alerts = STMServiceStatusParser.parseAlerts(from: data, referenceDate: referenceDate)

        XCTAssertTrue(alerts.isEmpty)
    }

    func testParseAlertsFiltersNormalMetroServiceNotices() throws {
        let data = try XCTUnwrap(
            """
            {
              "header": { "timestamp": 1774408512 },
              "alerts": [
                {
                  "active_periods": { "start": 1774284480, "end": null },
                  "cause": null,
                  "effect": null,
                  "informed_entities": [
                    { "route_short_name": "1" }
                  ],
                  "header_texts": [
                    { "language": "en", "text": "Your line" }
                  ],
                  "description_texts": [
                    { "language": "en", "text": "Normal métro service" }
                  ]
                }
              ]
            }
            """.data(using: .utf8)
        )

        let alerts = STMServiceStatusParser.parseAlerts(from: data)

        XCTAssertTrue(alerts.isEmpty)
    }

    func testParseAlertsConvertsHTMLNoticeIntoReadableMessageAndLink() throws {
        let data = try XCTUnwrap(
            """
            {
              "header": { "timestamp": 1774408512 },
              "alerts": [
                {
                  "active_periods": { "start": 1774284480, "end": null },
                  "cause": null,
                  "effect": null,
                  "informed_entities": [
                    { "route_short_name": "225" }
                  ],
                  "header_texts": [
                    { "language": "fr", "text": "Votre ligne" }
                  ],
                  "description_texts": [
                    {
                      "language": "fr",
                      "text": "Avec la <a class=\\"external\\" href=\\"https://www.stm.info/fr/a-propos/grands-projets/grands-projets-bus/refonte-du-reseau-bus?utm_campaign=mip&utm_source=refonte2026&utm_medium=horairesstm\\" target=\\"_blank\\">refonte du réseau bus 2026</a> et l'arrivée du REM Anse-à-l'Orme, cette ligne sera modifiée."
                    }
                  ]
                }
              ]
            }
            """.data(using: .utf8)
        )

        let alerts = STMServiceStatusParser.parseAlerts(from: data)

        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(
            alerts.first?.message,
            "Avec la refonte du réseau bus 2026 et l'arrivée du REM Anse-à-l'Orme, cette ligne sera modifiée."
        )
        XCTAssertEqual(
            alerts.first?.url?.absoluteString,
            "https://www.stm.info/fr/a-propos/grands-projets/grands-projets-bus/refonte-du-reseau-bus?utm_campaign=mip&utm_source=refonte2026&utm_medium=horairesstm"
        )
    }
}
