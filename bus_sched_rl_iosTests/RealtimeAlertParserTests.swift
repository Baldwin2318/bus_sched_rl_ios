import XCTest
@testable import bus_sched_rl_ios

final class RealtimeAlertParserTests: XCTestCase {
    func testParseAlertsNormalizesRouteAndStopScope() {
        var feed = TransitRealtime_FeedMessage()
        var entity = TransitRealtime_FeedEntity()
        entity.id = "alert-1"

        var alert = TransitRealtime_Alert()
        alert.headerText = translatedString("Route 55 delayed")
        alert.descriptionText = translatedString("Expect 10 minute delays near Main Stop.")
        alert.severityLevel = .warning

        var selector = TransitRealtime_EntitySelector()
        selector.routeID = "55"
        selector.stopID = "stop-1"
        selector.directionID = 0
        alert.informedEntity = [selector]

        entity.alert = alert
        feed.entity = [entity]

        let parsedAlerts = GTFSRealtimeAlertParser.parseAlerts(from: feed)

        XCTAssertEqual(parsedAlerts.count, 1)
        XCTAssertEqual(parsedAlerts.first?.id, "alert-1")
        XCTAssertEqual(parsedAlerts.first?.severity, .warning)
        XCTAssertEqual(parsedAlerts.first?.title, "Route 55 delayed")
        XCTAssertEqual(parsedAlerts.first?.scopes.first?.routeID, "55")
        XCTAssertEqual(parsedAlerts.first?.scopes.first?.stopID, "stop-1")
        XCTAssertEqual(parsedAlerts.first?.scopes.first?.directionID, "0")
    }

    func testParseAlertsDropsExpiredAlert() {
        let now = Date()
        var feed = TransitRealtime_FeedMessage()
        var entity = TransitRealtime_FeedEntity()
        entity.id = "expired-alert"

        var alert = TransitRealtime_Alert()
        alert.headerText = translatedString("Expired delay")
        alert.severityLevel = .warning

        var period = TransitRealtime_TimeRange()
        period.start = UInt64(now.addingTimeInterval(-3600).timeIntervalSince1970)
        period.end = UInt64(now.addingTimeInterval(-1800).timeIntervalSince1970)
        alert.activePeriod = [period]

        entity.alert = alert
        feed.entity = [entity]

        let parsedAlerts = GTFSRealtimeAlertParser.parseAlerts(from: feed, referenceDate: now)

        XCTAssertTrue(parsedAlerts.isEmpty)
    }

    private func translatedString(_ text: String) -> TransitRealtime_TranslatedString {
        var translated = TransitRealtime_TranslatedString()
        var translation = TransitRealtime_TranslatedString.Translation()
        translation.text = text
        translated.translation = [translation]
        return translated
    }
}
