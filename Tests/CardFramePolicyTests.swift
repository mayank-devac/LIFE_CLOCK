import XCTest

final class CardFramePolicyTests: XCTestCase {
    private let minimum = CGSize(width: 510, height: 100)

    func testOversizedAndDisconnectedDisplayFramesFitIncludingGrip() throws {
        let areas = [CGRect(x: 0, y: 30, width: 1280, height: 690),
                     CGRect(x: -1440, y: -200, width: 1440, height: 870)]
        let frames = [CGRect(x: 0, y: 0, width: 3000, height: 1800),
                      CGRect(x: 2500, y: 900, width: 900, height: 400),
                      CGRect(x: -5000, y: -3000, width: 700, height: 300),
                      CGRect(x: 200, y: 200, width: 2000, height: 200),
                      CGRect(x: 200, y: 200, width: 700, height: 2000)]
        for area in areas {
            for frame in frames {
                let result = try XCTUnwrap(CardFramePolicy.fit(frame, to: area, minimumSize: minimum))
                XCTAssertTrue(area.contains(result))
                XCTAssertLessThanOrEqual(result.maxX, area.maxX)
                XCTAssertGreaterThanOrEqual(result.minY, area.minY)
                XCTAssertGreaterThanOrEqual(result.width, minimum.width)
                XCTAssertGreaterThanOrEqual(result.height, minimum.height)
            }
        }
    }

    func testContainedFrameIsUnchangedAndRecoveryIsIdempotent() throws {
        let area = CGRect(x: -1440, y: 30, width: 1440, height: 870)
        let frame = CGRect(x: -1200, y: 100, width: 800, height: 400)
        XCTAssertEqual(CardFramePolicy.fit(frame, to: area, minimumSize: minimum), frame)
        let recovered = try XCTUnwrap(CardFramePolicy.fit(
            CGRect(x: 2000, y: -1000, width: 2000, height: 2000), to: area, minimumSize: minimum))
        XCTAssertEqual(CardFramePolicy.fit(recovered, to: area, minimumSize: minimum), recovered)
    }

    func testResizeKeepsTopLeftAndGripWithinActiveScreen() throws {
        let area = CGRect(x: -1440, y: 30, width: 1440, height: 870)
        let frame = CGRect(x: -1000, y: 500, width: 600, height: 300)
        let enlarged = try XCTUnwrap(CardFramePolicy.resize(frame, by: CGSize(width: 5000, height: 5000),
                                                            in: area, minimumSize: minimum))
        XCTAssertEqual(enlarged.minX, frame.minX)
        XCTAssertEqual(enlarged.maxY, frame.maxY)
        XCTAssertEqual(enlarged.maxX, area.maxX)
        XCTAssertEqual(enlarged.minY, area.minY)
        XCTAssertTrue(area.contains(enlarged))
        let shrunken = try XCTUnwrap(CardFramePolicy.resize(frame, by: CGSize(width: -5000, height: -5000),
                                                           in: area, minimumSize: minimum))
        XCTAssertEqual(shrunken.size, minimum)
        XCTAssertEqual(shrunken.minX, frame.minX)
        XCTAssertEqual(shrunken.maxY, frame.maxY)
    }

    func testMinimumLargerThanDisplayIsRejected() {
        for area in [CGRect(x: 0, y: 0, width: 500, height: 700),
                     CGRect(x: 0, y: 0, width: 1280, height: 90)] {
            XCTAssertNil(CardFramePolicy.fit(area, to: area, minimumSize: minimum))
            XCTAssertNil(CardFramePolicy.resize(area, by: .zero, in: area, minimumSize: minimum))
        }
    }
}
