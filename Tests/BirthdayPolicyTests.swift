import XCTest

final class BirthdayPolicyTests: XCTestCase {
    private let birth = BirthDetails(year: 2000, month: 10, day: 19, timeZoneID: "Asia/Kolkata")
    private let utc = TimeZone(secondsFromGMT: 0)!

    private func key(_ timestamp: String, birth: BirthDetails? = nil,
                     last: String? = nil, active: Bool = true, zone: TimeZone? = nil) -> String? {
        BirthdayPolicy.celebrationKey(birth: birth ?? self.birth,
            now: ISO8601DateFormatter().date(from: timestamp)!, timeZone: zone ?? utc,
            lastCelebratedDay: last, sessionActive: active)
    }

    func testWakeOnBirthdayAndRepeatUnlocks() {
        XCTAssertNil(key("2026-10-18T23:59:00Z"))
        XCTAssertNil(key("2026-10-19T08:00:00Z", active: false))
        XCTAssertEqual(key("2026-10-19T08:00:00Z"), "2026-10-19")
        XCTAssertNil(key("2026-10-19T09:00:00Z", last: "2026-10-19"))
        XCTAssertNil(key("2026-10-19T20:00:00Z", last: "2026-10-19"))
        XCTAssertEqual(key("2027-10-19T08:00:00Z", last: "2026-10-19"), "2027-10-19")
    }

    func testBirthdayFollowsCurrentLocalDate() {
        let moment = "2026-10-18T20:00:00Z"
        XCTAssertNil(key(moment))
        XCTAssertEqual(key(moment, zone: TimeZone(identifier: "Asia/Kolkata")!), "2026-10-19")
    }

    func testLeapBirthdayPolicy() {
        let leap = BirthDetails(year: 2000, month: 2, day: 29, timeZoneID: "UTC")
        XCTAssertEqual(key("2027-02-28T10:00:00Z", birth: leap), "2027-02-28")
        XCTAssertNil(key("2027-03-01T10:00:00Z", birth: leap))
        XCTAssertNil(key("2028-02-28T10:00:00Z", birth: leap))
        XCTAssertEqual(key("2028-02-29T10:00:00Z", birth: leap), "2028-02-29")
    }

    func testGreetingDoesNotWaitForBirthHour() {
        let timed = BirthDetails(year: 2000, month: 10, day: 19, hour: 22, minute: 0, timeZoneID: "UTC")
        XCTAssertEqual(key("2026-10-19T08:00:00Z", birth: timed), "2026-10-19")
    }

    func testNoBelatedGreetingAndNoGreetingBeforeBirth() {
        XCTAssertNil(key("2026-10-20T08:00:00Z"))
        XCTAssertNil(key("1999-10-19T08:00:00Z"))
    }
}
