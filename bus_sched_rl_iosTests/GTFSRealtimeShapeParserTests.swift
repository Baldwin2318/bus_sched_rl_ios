import XCTest
@testable import bus_sched_rl_ios

final class GTFSRealtimeShapeParserTests: XCTestCase {
    func testParseShapesDecodesEncodedPolyline() {
        var feed = TransitRealtime_FeedMessage()
        var entity = TransitRealtime_FeedEntity()
        entity.id = "shape-entity"

        var shape = TransitRealtime_Shape()
        shape.shapeID = "detour-shape"
        shape.encodedPolyline = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
        entity.shape = shape
        feed.entity = [entity]

        let parsedShapes = GTFSRealtimeShapeParser.parseShapes(from: feed)

        XCTAssertEqual(parsedShapes["detour-shape"]?.count, 3)
        XCTAssertEqual(parsedShapes["detour-shape"]?.first?.latitude, 38.5, accuracy: 0.0001)
        XCTAssertEqual(parsedShapes["detour-shape"]?.first?.longitude, -120.2, accuracy: 0.0001)
    }
}
