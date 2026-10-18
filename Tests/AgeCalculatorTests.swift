import XCTest

final class AgeCalculatorTests: XCTestCase {
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func testExactBirthdayAndElapsedFractions() throws {
        let birth = BirthDetails(year: 2000, month: 10, day: 19, hour: 12, minute: 30, timeZoneID: "UTC")
        let birthday = date("2026-10-19T12:30:00Z")
        let exact = try XCTUnwrap(AgeCalculator.snapshot(birth: birth, now: birthday))
        XCTAssertEqual(exact.years, 26)
        XCTAssertEqual(exact.months, 0)
        XCTAssertEqual(exact.days, 0)
        XCTAssertEqual(exact.decimalYears, 26, accuracy: 0.00000001)
        let fraction = try XCTUnwrap(AgeCalculator.snapshot(birth: birth, now: birthday.addingTimeInterval(1.25)))
        XCTAssertEqual(fraction.seconds, 1)
        XCTAssertEqual(fraction.milliseconds, 250)
        XCTAssertEqual(fraction.totalSeconds - exact.totalSeconds, 1.25, accuracy: 0.00001)
    }

    func testLeapBirthdayUsesFebruary28AndReturnsToFebruary29() throws {
        let birth = BirthDetails(year: 2000, month: 2, day: 29, timeZoneID: "UTC")
        let normalYear = try XCTUnwrap(AgeCalculator.snapshot(birth: birth, now: date("2023-02-28T00:00:00Z")))
        XCTAssertEqual(normalYear.years, 23)
        XCTAssertEqual(normalYear.decimalYears, 23, accuracy: 0.00000001)
        XCTAssertEqual(AgeCalculator.snapshot(birth: birth, now: date("2024-02-28T00:00:00Z"))?.years, 23)
        XCTAssertEqual(AgeCalculator.snapshot(birth: birth, now: date("2024-02-29T00:00:00Z"))?.years, 24)
    }

    func testDecimalYearsUsesActualAnniversaryInterval() throws {
        let birth = BirthDetails(year: 2000, month: 1, day: 1, timeZoneID: "UTC")
        let start = date("2024-01-01T00:00:00Z")
        let end = date("2025-01-01T00:00:00Z")
        let halfway = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        XCTAssertEqual(try XCTUnwrap(AgeCalculator.snapshot(birth: birth, now: halfway)).decimalYears,
                       24.5, accuracy: 0.00000001)
    }

    func testDesktopFormatDecodesPreviouslySavedAgeFormats() throws {
        XCTAssertTrue(DesktopCardFormat.allCases.contains(.countdown))
        for format in AgeFormat.allCases {
            let data = try JSONEncoder().encode(format)
            XCTAssertEqual(try JSONDecoder().decode(DesktopCardFormat.self, from: data).rawValue, format.rawValue)
        }
    }

    func testRemainingLifeCountsDownToTargetAndClampsAtZero() throws {
        let birth = BirthDetails(year: 2000, month: 1, day: 1, timeZoneID: "UTC")
        let oneSecondLeft = try XCTUnwrap(AgeCalculator.remainingParts(
            birth: birth, now: date("2079-12-31T23:59:59Z"), lifespanYears: 80))
        XCTAssertEqual(oneSecondLeft.year, 0)
        XCTAssertEqual(oneSecondLeft.month, 0)
        XCTAssertEqual(oneSecondLeft.day, 0)
        XCTAssertEqual(oneSecondLeft.hour, 0)
        XCTAssertEqual(oneSecondLeft.minute, 0)
        XCTAssertEqual(oneSecondLeft.second, 1)

        let afterTarget = try XCTUnwrap(AgeCalculator.remainingParts(
            birth: birth, now: date("2080-01-01T00:00:01Z"), lifespanYears: 80))
        XCTAssertEqual(afterTarget.year, 0)
        XCTAssertEqual(afterTarget.month, 0)
        XCTAssertEqual(afterTarget.day, 0)
        XCTAssertEqual(afterTarget.hour, 0)
        XCTAssertEqual(afterTarget.minute, 0)
        XCTAssertEqual(afterTarget.second, 0)
        XCTAssertNil(AgeCalculator.remainingParts(birth: birth, now: Date(), lifespanYears: -1))

        let oneMonthLeft = try XCTUnwrap(AgeCalculator.remainingParts(
            birth: birth, now: date("2079-12-01T00:00:00Z"), lifespanYears: 80))
        XCTAssertEqual(oneMonthLeft.year, 0)
        XCTAssertEqual(oneMonthLeft.month, 1)
        XCTAssertEqual(oneMonthLeft.day, 0)
    }

    func testSubsecondUnitsFormatSeparateValues() {
        let interval = 12.123456789
        XCTAssertEqual(SubsecondUnit.milliseconds.formattedValue(of: interval), "123")
        XCTAssertEqual(SubsecondUnit.microseconds.formattedValue(of: interval), "456")
        XCTAssertEqual(SubsecondUnit.nanoseconds.formattedValue(of: interval), "789")
        XCTAssertEqual(SubsecondUnit.picoseconds.formattedValue(of: interval), "000")
        for unit in SubsecondUnit.allCases {
            XCTAssertLessThanOrEqual(unit.formattedValue(of: interval).count, 3)
        }
        XCTAssertEqual(SubsecondUnit.picoseconds.formattedValue(of: 12), "000")
    }

    func testPreferencesDecodeWithoutNewSubsecondSetting() throws {
        let data = Data(#"{"birth":null,"cardFormat":"countdown","cardEnabled":true,"alwaysOnTop":false}"#.utf8)
        let preferences = try JSONDecoder().decode(LifePreferences.self, from: data)
        XCTAssertEqual(preferences.cardFormat, .countdown)
        XCTAssertTrue(preferences.subsecondUnits.isEmpty)
        XCTAssertTrue(preferences.cardEnabled)
    }

    func testPreferencesMigrateLegacySubsecondPrecision() throws {
        let data = Data(#"{"birth":null,"cardFormat":"countdown","subsecondPrecision":"nanoseconds","cardEnabled":true,"alwaysOnTop":false}"#.utf8)
        let preferences = try JSONDecoder().decode(LifePreferences.self, from: data)
        XCTAssertEqual(preferences.subsecondUnits, [.milliseconds, .microseconds, .nanoseconds])
    }

    func testDateOnlyUsesSelectedTimezoneMidnight() throws {
        let birth = BirthDetails(year: 2000, month: 1, day: 1, timeZoneID: "Asia/Kolkata")
        XCTAssertFalse(birth.hasBirthTime)
        XCTAssertEqual(try XCTUnwrap(birth.date), date("1999-12-31T18:30:00Z"))
    }

    func testWidgetDateComponentsKeepTheSelectedBirthdayAndTimezone() throws {
        let selected = DateComponents(year: 2000, month: 10, day: 19)
        let approximate = try XCTUnwrap(BirthDetails(dateComponents: selected, timeComponents: nil,
                                                    timeZoneID: "Asia/Kolkata"))
        XCTAssertFalse(approximate.hasBirthTime)
        XCTAssertEqual(approximate.date, date("2000-10-18T18:30:00Z"))
        let timed = try XCTUnwrap(BirthDetails(dateComponents: selected,
            timeComponents: DateComponents(hour: 12, minute: 30), timeZoneID: "Asia/Kolkata"))
        XCTAssertTrue(timed.hasBirthTime)
        XCTAssertEqual(timed.date, date("2000-10-19T07:00:00Z"))
        XCTAssertNil(BirthDetails(dateComponents: DateComponents(month: 10, day: 19),
                                 timeComponents: nil, timeZoneID: "Asia/Kolkata"))
        XCTAssertNil(BirthDetails(dateComponents: selected, timeComponents: DateComponents(hour: 12),
                                 timeZoneID: "Asia/Kolkata"))
    }

    func testWidgetDropdownsAndOptionalTime() throws {
        let birth = try XCTUnwrap(BirthDetails(day: "29", month: "02 February", year: "2000",
                                              time: "12:30", timeZoneID: "Asia/Kolkata"))
        XCTAssertEqual(birth.date, date("2000-02-29T07:00:00Z"))
        let approximate = try XCTUnwrap(BirthDetails(day: "01", month: "01 January", year: "2000",
                                                    time: "  ", timeZoneID: "UTC"))
        XCTAssertFalse(approximate.hasBirthTime)
        XCTAssertNil(BirthDetails(day: "29", month: "02 February", year: "2001", time: nil, timeZoneID: "UTC"))
        for time in ["25:00", "12:60", "12", "9:30", "12:30:00", "ab:cd"] {
            XCTAssertNil(BirthDetails(day: "01", month: "01 January", year: "2000", time: time, timeZoneID: "UTC"))
        }
    }

    func testInvalidAndFutureBirthdaysAreRejected() {
        XCTAssertNil(BirthDetails(year: 2000, month: 2, day: 30, timeZoneID: "UTC").date)
        XCTAssertNil(BirthDetails(year: 2000, month: 1, day: 1, timeZoneID: "invalid").date)
        XCTAssertNil(BirthDetails(year: 2000, month: 1, day: 1, hour: 25, minute: 0, timeZoneID: "UTC").date)
        XCTAssertNil(BirthDetails(year: 2000, month: 1, day: 1, hour: 12, minute: nil, timeZoneID: "UTC").date)
        let future = BirthDetails(year: 2030, month: 1, day: 1, timeZoneID: "UTC")
        XCTAssertNil(AgeCalculator.snapshot(birth: future, now: date("2026-01-01T00:00:00Z")))
    }

    func testMissingDSTTimeIsRejectedAndElapsedTimeCrossesDST() throws {
        XCTAssertNil(BirthDetails(year: 2024, month: 3, day: 10, hour: 2, minute: 30,
                                  timeZoneID: "America/New_York").date)
        let birth = BirthDetails(year: 2024, month: 3, day: 9, timeZoneID: "America/New_York")
        let nextDay = try XCTUnwrap(AgeCalculator.snapshot(birth: birth, now: date("2024-03-11T04:00:00Z")))
        XCTAssertEqual(nextDay.days, 2)
        XCTAssertEqual(nextDay.totalSeconds, 47 * 3_600)
    }

    func testMonthEndAndWakeUseCurrentDate() throws {
        let birth = BirthDetails(year: 2000, month: 1, day: 31, timeZoneID: "UTC")
        let before = try XCTUnwrap(AgeCalculator.snapshot(birth: birth, now: date("2026-02-28T23:00:00Z")))
        let after = try XCTUnwrap(AgeCalculator.snapshot(birth: birth, now: date("2026-03-01T07:00:00Z")))
        XCTAssertEqual(before.months, 1)
        XCTAssertEqual(before.days, 0)
        XCTAssertEqual(after.totalSeconds - before.totalSeconds, 8 * 3_600)
        XCTAssertEqual(after.hours, 7)
    }
}
