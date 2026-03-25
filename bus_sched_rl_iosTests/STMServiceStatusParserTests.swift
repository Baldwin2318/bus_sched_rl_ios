import XCTest
@testable import bus_sched_rl_ios

final class STMServiceStatusParserTests: XCTestCase {
    func testParseAlertsNormalizesGlobalSTMNotice() throws {
        let data = try XCTUnwrap(
            """
            {
              "messages": [
                {
                  "id": "stm-1",
                  "title": "STM network disruption",
                  "message": "Service is heavily disrupted across the network.",
                  "severity": "severe"
                }
              ]
            }
            """.data(using: .utf8)
        )

        let alerts = STMServiceStatusParser.parseAlerts(from: data)

        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.id, "stm-1")
        XCTAssertEqual(alerts.first?.source, .stmServiceStatus)
        XCTAssertEqual(alerts.first?.severity, .severe)
        XCTAssertTrue(alerts.first?.isGlobal == true)
    }

    func testParseAlertsNormalizesRouteScopedSTMNotice() throws {
        let data = try XCTUnwrap(
            """
            {
              "messages": [
                {
                  "id": "stm-55",
                  "titre": "Ligne 55 perturbée",
                  "description": "Retards importants sur la ligne 55.",
                  "ligne": "55"
                }
              ]
            }
            """.data(using: .utf8)
        )

        let alerts = STMServiceStatusParser.parseAlerts(from: data)

        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.scopes.first?.routeID, "55")
        XCTAssertEqual(alerts.first?.severity, .warning)
        XCTAssertEqual(alerts.first?.source, .stmServiceStatus)
    }

    func testParseAlertsDropsExpiredSTMNotice() throws {
        let data = try XCTUnwrap(
            """
            {
              "messages": [
                {
                  "id": "stm-expired",
                  "title": "Expired notice",
                  "message": "Old disruption",
                  "dateStart": "2025-01-01T00:00:00Z",
                  "dateEnd": "2025-01-01T02:00:00Z"
                }
              ]
            }
            """.data(using: .utf8)
        )

        let referenceDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-01-01T12:00:00Z"))
        let alerts = STMServiceStatusParser.parseAlerts(from: data, referenceDate: referenceDate)

        XCTAssertTrue(alerts.isEmpty)
    }
}
