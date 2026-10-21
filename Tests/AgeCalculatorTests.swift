import XCTest
import SwiftUI

final class AgeCalculatorTests: XCTestCase {
    func testWidgetClockModeResolvesSavedDropdownAndLegacySelections() {
        XCTAssertEqual(WidgetClockMode(selection: "Years remaining"), .remaining)
        XCTAssertEqual(WidgetClockMode(selection: "remaining"), .remaining)
        XCTAssertEqual(WidgetClockMode(selection: "Age"), .age)
        XCTAssertEqual(WidgetClockMode(selection: "age"), .age)
        XCTAssertEqual(WidgetClockMode(selection: nil), .age)
        XCTAssertEqual(WidgetClockMode(selection: "unknown"), .age)
    }

    func testWidgetTimerDefaultsExcludeYearsAndIncludeDaysThroughSeconds() {
        XCTAssertEqual(WidgetTimerUnit.defaultSelection, [.days, .hours, .minutes, .seconds])
    }

    func testWidgetTimerAccumulatesTimeIntoSelectedUnits() {
        let hours = WidgetTimerUnit.durationStyle(for: [.hours, .minutes, .seconds])
            .locale(Locale(identifier: "en_US"))
        XCTAssertEqual(hours.format(.seconds(86_401)), "24h 0m 1s")
        let seconds = WidgetTimerUnit.durationStyle(for: [.seconds])
            .locale(Locale(identifier: "en_US"))
        XCTAssertEqual(seconds.format(.seconds(61)), "61s")
    }

    func testWidgetTimerYearsUseCalendarYearsAcrossALeapYear() {
        if #available(macOS 15.0, *) {
            let birth = BirthDetails(year: 2000, month: 1, day: 1, timeZoneID: "UTC")
            let fields = Set([WidgetTimerUnit.years, .days].map(\.calendarField))
            let style = SystemFormatStyle.DateOffset(to: birth.date!, allowedFields: fields,
                maxFieldCount: 2, sign: .never).calendar(birth.calendar)
                .locale(Locale(identifier: "en_US"))
            XCTAssertEqual(String(style.format(date("2001-01-01T00:00:00Z")).characters), "1 year")
        }
    }

    func testWidgetDayTimerCarriesIntoDaysAndKeepsSecondsVisible() {
        let style = WidgetTimerUnit.durationStyle(for: WidgetTimerUnit.defaultSelection)
            .locale(Locale(identifier: "en_US"))
        XCTAssertEqual(style.format(.seconds(86_399.9)), "0d 23h 59m 59s")
        XCTAssertEqual(style.format(.seconds(86_400)), "1d 0h 0m 0s")
        XCTAssertEqual(style.format(.seconds(86_401)), "1d 0h 0m 1s")
    }

    func testWidgetCalendarClockSupportsMonthsAndClampedCountdown() throws {
        let birth = BirthDetails(year: 2000, month: 1, day: 1, timeZoneID: "UTC")
        let start = try XCTUnwrap(birth.date)
        let style = Date.ComponentsFormatStyle(style: .abbreviated,
            locale: Locale(identifier: "en_US"), calendar: birth.calendar,
            fields: [.year, .month, .day])
        let full = style.format(start..<date("2017-08-12T00:00:00Z"))
        XCTAssertTrue(full.contains("17"), full)
        XCTAssertTrue(full.contains("7"), full)
        XCTAssertTrue(full.contains("11"), full)
        for years in [60, 80, 90] {
            let target = try XCTUnwrap(birth.calendar.date(byAdding: .year, value: years, to: start))
            let after = target.addingTimeInterval(1)
            let stopped = style.format(min(after, target)..<target)
            XCTAssertTrue(stopped.contains("0"), stopped)
            XCTAssertFalse(stopped.contains("-"), stopped)
            let remaining = try XCTUnwrap(AgeCalculator.remaining(birth: birth, now: after, lifespanYears: years))
            XCTAssertEqual(remaining.totalSeconds, 0)
        }
        let yearsOnly = Date.ComponentsFormatStyle(style: .abbreviated,
            locale: Locale(identifier: "en_US"), calendar: birth.calendar, fields: [.year])
        XCTAssertTrue(yearsOnly.format(start..<date("2017-08-12T00:00:00Z")).contains("17"))
    }

    func testRemainingWidgetClockSchedulesLiveSecondsTowardsTarget() throws {
        if #available(macOS 15.0, *) {
            let now = date("2026-10-21T12:45:57Z")
            let target = date("2089-03-10T01:31:54Z")
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
            let style = SystemFormatStyle.DateOffset(to: target,
                allowedFields: [.year, .month, .day, .hour, .minute, .second],
                maxFieldCount: 6, sign: .never).calendar(calendar).locale(Locale(identifier: "en_US"))
            let first = String(style.format(now).characters)
            let second = String(style.format(now.addingTimeInterval(1)).characters)
            XCTAssertNotEqual(first, second, "Countdown seconds must change without a timeline reload")
            let nextUpdate = try XCTUnwrap(style.discreteInput(after: now))
            XCTAssertGreaterThan(nextUpdate, now)
            XCTAssertLessThanOrEqual(nextUpdate.timeIntervalSince(now), 1.001)
            XCTAssertNotEqual(String(style.format(nextUpdate).characters), first)
            let lastSecond = String(style.format(target.addingTimeInterval(-1)).characters)
            XCTAssertTrue(lastSecond.contains("1"), lastSecond)
        }
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func testDisplayReadingsShareLeapDayPolicyAndCountdownFractions() throws {
        let birth = BirthDetails(year: 2000, month: 2, day: 29, timeZoneID: "UTC")
        let now = date("2023-02-28T00:00:00Z")
        let age = try XCTUnwrap(AgeCalculator.snapshot(birth: birth, now: now))
        for format in DesktopCardFormat.allCases where format != .countdown {
            let reading = try XCTUnwrap(age.reading(for: format, birth: birth, now: now))
            XCTAssertEqual(reading.parts.year, 23)
            XCTAssertEqual(reading.parts.month, 0)
            XCTAssertEqual(reading.parts.day, 0)
            XCTAssertEqual(reading.totalSeconds, age.totalSeconds)
            XCTAssertEqual(reading.accessibleDescription,
                           "23 years, 0 months, 0 days, 0 hours, 0 minutes, 0 seconds")
        }

        let end = date("2080-02-29T00:00:00Z")
        let before = end.addingTimeInterval(-1.25)
        let beforeAge = try XCTUnwrap(AgeCalculator.snapshot(birth: birth, now: before))
        let remaining = try XCTUnwrap(beforeAge.reading(for: .countdown, birth: birth, now: before))
        XCTAssertEqual(remaining.parts.second, 1)
        XCTAssertEqual(remaining.totalSeconds, 1.25, accuracy: 0.00001)
        let after = try XCTUnwrap(AgeCalculator.remaining(birth: birth, now: end.addingTimeInterval(1), lifespanYears: 80))
        XCTAssertEqual(after.totalSeconds, 0)
        XCTAssertEqual(after.parts.second, 0)
    }

    func testInvalidBirthdaySavePreservesPreviousSettings() throws {
        let suite = "LifeClockTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PreferencesStore(defaults: defaults)
        let original = LifePreferences(birth: BirthDetails(year: 2000, month: 1, day: 1, timeZoneID: "UTC"))
        try store.save(original)
        let invalidBirthdays = [
            BirthDetails(year: 2024, month: 3, day: 10, hour: 2, minute: 30, timeZoneID: "America/New_York"),
            BirthDetails(year: 2000, month: 2, day: 30, timeZoneID: "UTC"),
            BirthDetails(year: 2000, month: 1, day: 1, timeZoneID: "invalid"),
            BirthDetails(year: 9999, month: 1, day: 1, timeZoneID: "UTC")
        ]
        for birth in invalidBirthdays {
            var changed = original
            changed.birth = birth
            XCTAssertThrowsError(try store.save(changed))
            XCTAssertEqual(store.preferences, original)
            XCTAssertEqual(PreferencesStore(defaults: defaults).preferences, original)
        }
        try store.save(LifePreferences())
        XCTAssertNil(PreferencesStore(defaults: defaults).preferences.birth)
    }

    func testUnreadableSettingsRejectOrdinarySavesAndRecoverWithBackup() throws {
        let suite = "LifeClockTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = Data("{unreadable".utf8)
        defaults.set(original, forKey: "lifePreferences.v1")
        let store = PreferencesStore(defaults: defaults)
        let warning = try XCTUnwrap(store.readWarning)
        var updated = store.preferences
        updated.cardFormat = .totalSeconds
        updated.cardEnabled = false
        XCTAssertThrowsError(try store.save(updated))
        updated.birth = BirthDetails(year: 2000, month: 1, day: 1, timeZoneID: "UTC")
        XCTAssertThrowsError(try store.save(updated))
        XCTAssertTrue(store.recoveryNeeded)
        XCTAssertEqual(store.readWarning, warning)
        XCTAssertEqual(defaults.data(forKey: "lifePreferences.v1"), original)
        XCTAssertNil(defaults.object(forKey: "lifePreferences.recoveryBackup.v1"))

        try store.replaceUnreadableSettings()
        XCTAssertEqual(defaults.data(forKey: "lifePreferences.recoveryBackup.v1"), original)
        XCTAssertFalse(store.recoveryNeeded)
        XCTAssertNil(store.readWarning)
        XCTAssertNil(store.preferences.birth)
        XCTAssertEqual(PreferencesStore(defaults: defaults).preferences, LifePreferences())
        try store.save(updated)
        XCTAssertEqual(PreferencesStore(defaults: defaults).preferences, updated)
        try store.replaceUnreadableSettings()
        XCTAssertEqual(defaults.data(forKey: "lifePreferences.recoveryBackup.v1"), original)
    }

    func testRecoveryNeverOverwritesAnExistingBackup() throws {
        let suite = "LifeClockTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = Data("broken".utf8)
        let backup = Data("older backup".utf8)
        defaults.set(original, forKey: "lifePreferences.v1")
        defaults.set(backup, forKey: "lifePreferences.recoveryBackup.v1")
        let store = PreferencesStore(defaults: defaults)
        XCTAssertThrowsError(try store.replaceUnreadableSettings())
        XCTAssertEqual(defaults.data(forKey: "lifePreferences.v1"), original)
        XCTAssertEqual(defaults.data(forKey: "lifePreferences.recoveryBackup.v1"), backup)
        XCTAssertTrue(store.recoveryNeeded)
        XCTAssertNotNil(store.readWarning)
    }

    func testBirthdayEditingRequiresConfirmationThenSavesLiveEdits() throws {
        let suite = "LifeClockTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PreferencesStore(defaults: defaults)
        let draft = BirthDetails(year: 2000, month: 2, day: 10, hour: 12, minute: 30,
                                 timeZoneID: "Asia/Kolkata")
        let future = BirthDetails(year: 9999, month: 1, day: 1, timeZoneID: "UTC")

        XCTAssertFalse(try store.saveBirthday(draft, action: .edit))
        XCTAssertFalse(try store.saveBirthday(future, action: .edit))
        XCTAssertNil(store.preferences.birth)
        XCTAssertNil(defaults.object(forKey: "lifePreferences.v1"))

        var displayOnly = store.preferences
        displayOnly.cardFormat = .detailed
        try store.save(displayOnly)
        XCTAssertFalse(try store.saveBirthday(draft, action: .edit))
        XCTAssertNil(PreferencesStore(defaults: defaults).preferences.birth)
        XCTAssertThrowsError(try store.saveBirthday(future, action: .confirm))
        XCTAssertNil(store.preferences.birth)

        XCTAssertTrue(try store.saveBirthday(draft, action: .confirm))
        XCTAssertEqual(PreferencesStore(defaults: defaults).preferences.birth, draft)
        XCTAssertEqual(store.preferences.cardFormat, .detailed)

        var edited = draft
        edited.day = 11
        XCTAssertTrue(try store.saveBirthday(edited, action: .edit))
        XCTAssertEqual(PreferencesStore(defaults: defaults).preferences.birth, edited)
        XCTAssertThrowsError(try store.saveBirthday(future, action: .edit))
        XCTAssertEqual(store.preferences.birth, edited)
        XCTAssertEqual(PreferencesStore(defaults: defaults).preferences.birth, edited)
    }

    func testBirthdayConfirmationCannotBypassRecovery() throws {
        let suite = "LifeClockTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = Data("broken".utf8)
        defaults.set(original, forKey: "lifePreferences.v1")
        let store = PreferencesStore(defaults: defaults)
        let draft = BirthDetails(year: 2000, month: 1, day: 1, timeZoneID: "UTC")
        XCTAssertFalse(try store.saveBirthday(draft, action: .edit))
        XCTAssertThrowsError(try store.saveBirthday(draft, action: .confirm))
        XCTAssertEqual(defaults.data(forKey: "lifePreferences.v1"), original)
        XCTAssertTrue(store.recoveryNeeded)
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

    func testDesktopFormatTimelineCadenceCoversMotionAndSubseconds() {
        let cases: [(DesktopCardFormat, Set<SubsecondUnit>, Bool, Double?)] = [
            (.detailed, [], false, 0.5),
            (.detailed, [.milliseconds], false, 0.5),
            (.detailed, [], true, 1),
            (.detailed, [.milliseconds], true, 1),
            (.decimalYears, [], false, 0.5),
            (.decimalYears, [.milliseconds], false, 0.5),
            (.decimalYears, [], true, 1),
            (.decimalYears, [.milliseconds], true, 1),
            (.totalSeconds, [], false, 0.5),
            (.totalSeconds, [.milliseconds], false, 0.5),
            (.totalSeconds, [], true, 1),
            (.totalSeconds, [.milliseconds], true, 1),
            (.liveAge, [], false, 1),
            (.liveAge, [.milliseconds], false, nil),
            (.liveAge, [], true, 1),
            (.liveAge, [.milliseconds], true, 1),
            (.countdown, [], false, 1),
            (.countdown, [.milliseconds], false, nil),
            (.countdown, [], true, 1),
            (.countdown, [.milliseconds], true, 1),
        ]

        for (format, units, reduceMotion, expected) in cases {
            XCTAssertEqual(format.minimumTimelineInterval(subsecondUnits: units,
                                                         reduceMotion: reduceMotion), expected,
                           "Unexpected cadence for \(format), units: \(units), reduce motion: \(reduceMotion)")
        }
    }

    func testRemainingLifeCountsDownToTargetAndClampsAtZero() throws {
        let birth = BirthDetails(year: 2000, month: 1, day: 1, timeZoneID: "UTC")
        let oneSecondLeft = try XCTUnwrap(AgeCalculator.remaining(
            birth: birth, now: date("2079-12-31T23:59:59Z"), lifespanYears: 80))
        XCTAssertEqual(oneSecondLeft.parts.year, 0)
        XCTAssertEqual(oneSecondLeft.parts.month, 0)
        XCTAssertEqual(oneSecondLeft.parts.day, 0)
        XCTAssertEqual(oneSecondLeft.parts.hour, 0)
        XCTAssertEqual(oneSecondLeft.parts.minute, 0)
        XCTAssertEqual(oneSecondLeft.parts.second, 1)

        let afterTarget = try XCTUnwrap(AgeCalculator.remaining(
            birth: birth, now: date("2080-01-01T00:00:01Z"), lifespanYears: 80))
        XCTAssertEqual(afterTarget.parts.year, 0)
        XCTAssertEqual(afterTarget.parts.month, 0)
        XCTAssertEqual(afterTarget.parts.day, 0)
        XCTAssertEqual(afterTarget.parts.hour, 0)
        XCTAssertEqual(afterTarget.parts.minute, 0)
        XCTAssertEqual(afterTarget.parts.second, 0)
        XCTAssertNil(AgeCalculator.remaining(birth: birth, now: Date(), lifespanYears: -1))

        let oneMonthLeft = try XCTUnwrap(AgeCalculator.remaining(
            birth: birth, now: date("2079-12-01T00:00:00Z"), lifespanYears: 80))
        XCTAssertEqual(oneMonthLeft.parts.year, 0)
        XCTAssertEqual(oneMonthLeft.parts.month, 1)
        XCTAssertEqual(oneMonthLeft.parts.day, 0)
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
