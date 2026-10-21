import Foundation

struct BirthDetails: Codable, Equatable {
    var year: Int
    var month: Int
    var day: Int
    var hour: Int?
    var minute: Int?
    var timeZoneID: String

    init(year: Int, month: Int, day: Int, hour: Int? = nil, minute: Int? = nil, timeZoneID: String) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.timeZoneID = timeZoneID
    }

    /// Keep the selected calendar date unchanged when interpreting it in the birth timezone.
    init?(dateComponents: DateComponents, timeComponents: DateComponents?, timeZoneID: String) {
        guard let year = dateComponents.year, let month = dateComponents.month,
              let day = dateComponents.day else { return nil }
        if let timeComponents, (timeComponents.hour == nil || timeComponents.minute == nil) { return nil }
        self.init(year: year, month: month, day: day,
                  hour: timeComponents?.hour, minute: timeComponents?.minute, timeZoneID: timeZoneID)
        guard date != nil else { return nil }
    }

    /// Widget dropdowns use strings because macOS does not reliably render DateComponents pickers.
    init?(day: String, month: String, year: String, time: String?, timeZoneID: String) {
        guard let day = Int(day), let monthNumber = month.split(separator: " ").first,
              let month = Int(monthNumber), let year = Int(year) else { return nil }
        let text = time?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var hour: Int?
        var minute: Int?
        if !text.isEmpty {
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
                  let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            hour = h
            minute = m
        }
        self.init(year: year, month: month, day: day, hour: hour, minute: minute, timeZoneID: timeZoneID)
        guard date != nil else { return nil }
    }

    var hasBirthTime: Bool { hour != nil && minute != nil }
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return calendar
    }

    var date: Date? {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour ?? 0), (0...59).contains(minute ?? 0),
              TimeZone(identifier: timeZoneID) != nil,
              (hour == nil) == (minute == nil) else { return nil }
        let parts = DateComponents(year: year, month: month, day: day,
                                   hour: hour ?? 0, minute: minute ?? 0, second: 0)
        guard let date = calendar.date(from: parts) else { return nil }
        // Calendar normalises invalid dates and missing DST times; reject those.
        let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard actual.year == year, actual.month == month, actual.day == day,
              actual.hour == (hour ?? 0), actual.minute == (minute ?? 0) else { return nil }
        return date
    }
}

// Widget configuration uses a String dropdown because macOS can return an enum's
// default instead of its saved selection. Accept both new labels and legacy raw values.
enum WidgetClockMode: String, CaseIterable {
    case age, remaining

    var title: String {
        switch self {
        case .age: return "Age"
        case .remaining: return "Years remaining"
        }
    }

    init(selection: String?) {
        self = Self.allCases.first { $0.rawValue == selection || $0.title == selection } ?? .age
    }
}

enum AgeFormat: String, Codable, CaseIterable, Identifiable {
    case detailed, decimalYears, totalSeconds
    var id: String { rawValue }
    var title: String {
        switch self {
        case .detailed: return "Detailed age"
        case .decimalYears: return "Decimal years"
        case .totalSeconds: return "Total seconds"
        }
    }
}

enum WidgetTimerUnit: String, CaseIterable, Hashable {
    case years, days, hours, minutes, seconds

    static let defaultSelection: Set<Self> = [.days, .hours, .minutes, .seconds]

    var calendarField: Date.ComponentsFormatStyle.Field {
        switch self {
        case .years: return .year
        case .days: return .day
        case .hours: return .hour
        case .minutes: return .minute
        case .seconds: return .second
        }
    }

    private var durationUnit: Duration.UnitsFormatStyle.Unit? {
        switch self {
        case .years: return nil // Calendar years are not a fixed duration.
        case .days: return .days
        case .hours: return .hours
        case .minutes: return .minutes
        case .seconds: return .seconds
        }
    }

    static func durationStyle(for units: Set<Self>) -> Duration.UnitsFormatStyle {
        .units(allowed: Set(units.compactMap(\.durationUnit)), width: .narrow,
               maximumUnitCount: units.count, zeroValueUnits: .show(length: 1),
               fractionalPart: .hide(rounded: .down))
    }
}

enum DesktopCardFormat: String, Codable, CaseIterable, Identifiable {
    case detailed, decimalYears, totalSeconds, liveAge, countdown
    var id: String { rawValue }
    var title: String {
        switch self {
        case .detailed: return "Detailed age"
        case .decimalYears: return "Decimal years"
        case .totalSeconds: return "Total seconds"
        case .liveAge: return "Live age card"
        case .countdown: return "Years remaining"
        }
    }

    /// Select the timeline cadence for this format and its optional fractional units.
    /// A nil interval lets TimelineView sample every animation frame.
    func minimumTimelineInterval(subsecondUnits: Set<SubsecondUnit>, reduceMotion: Bool) -> Double? {
        guard !reduceMotion else { return 1 }
        switch self {
        case .liveAge, .countdown:
            return subsecondUnits.isEmpty ? 1 : nil
        case .detailed, .decimalYears, .totalSeconds:
            return 0.5
        }
    }
}

enum SubsecondUnit: String, Codable, CaseIterable, Hashable, Identifiable {
    case milliseconds, microseconds, nanoseconds, picoseconds

    var id: String { rawValue }
    var groupIndex: Int {
        switch self {
        case .milliseconds: return 0
        case .microseconds: return 1
        case .nanoseconds: return 2
        case .picoseconds: return 3
        }
    }
    var title: String {
        switch self {
        case .milliseconds: return "Milliseconds"
        case .microseconds: return "Microseconds"
        case .nanoseconds: return "Nanoseconds"
        case .picoseconds: return "Picoseconds (estimated)"
        }
    }
    var shortLabel: String {
        switch self {
        case .milliseconds: return "MILI"
        case .microseconds: return "MICROSEC"
        case .nanoseconds: return "NANO"
        case .picoseconds: return "pico"
        }
    }

    func formattedValue(of interval: TimeInterval) -> String {
        let scale: Int64 = 1_000_000_000_000
        let fraction = interval - floor(interval)
        let value = min(scale - 1, max(0, Int64(fraction * Double(scale))))
        let digits = String(format: "%012lld", value)
        let start = digits.index(digits.startIndex, offsetBy: groupIndex * 3)
        let end = digits.index(start, offsetBy: 3)
        return String(digits[start..<end])
    }
}

extension Double {
    func formattedDecimalYears(fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: self)) ?? String(self)
    }
}

struct ClockReading {
    let parts: DateComponents
    let totalSeconds: TimeInterval

    var accessibleDescription: String {
        "\(parts.year ?? 0) years, \(parts.month ?? 0) months, \(parts.day ?? 0) days, " +
            "\(parts.hour ?? 0) hours, \(parts.minute ?? 0) minutes, \(parts.second ?? 0) seconds"
    }
}

struct AgeSnapshot {
    let years: Int
    let months: Int
    let days: Int
    let hours: Int
    let minutes: Int
    let seconds: Int
    let milliseconds: Int
    let decimalYears: Double
    let totalSeconds: TimeInterval

    var calendarDescription: String { "\(years)y  \(months)m  \(days)d" }
    var clockDescription: String {
        String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
    }
    var clock: ClockReading {
        ClockReading(parts: DateComponents(year: years, month: months, day: days,
                                           hour: hours, minute: minutes, second: seconds),
                     totalSeconds: totalSeconds)
    }
    var accessibleDescription: String { clock.accessibleDescription }

    func reading(for format: DesktopCardFormat, birth: BirthDetails, now: Date) -> ClockReading? {
        format == .countdown
            ? AgeCalculator.remaining(birth: birth, now: now, lifespanYears: 80)
            : clock
    }
}

enum AgeCalculator {
    static func remaining(birth: BirthDetails, now: Date, lifespanYears: Int) -> ClockReading? {
        guard lifespanYears >= 0, let birthDate = birth.date, birthDate <= now,
              let endDate = birth.calendar.date(byAdding: .year, value: lifespanYears, to: birthDate) else {
            return nil
        }
        let boundedNow = min(now, endDate)
        let parts = birth.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: boundedNow,
            to: endDate)
        return ClockReading(parts: parts, totalSeconds: max(0, endDate.timeIntervalSince(now)))
    }

    /// Clamp leap-day anniversaries to February 28 in non-leap years.
    static func anniversary(of birth: BirthDetails, year: Int) -> Date? {
        let calendar = birth.calendar
        guard let start = calendar.date(from: DateComponents(year: year, month: birth.month, day: 1)),
              let days = calendar.range(of: .day, in: .month, for: start) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: birth.month,
            day: min(birth.day, days.count), hour: birth.hour ?? 0, minute: birth.minute ?? 0))
    }

    static func snapshot(birth: BirthDetails, now: Date) -> AgeSnapshot? {
        guard let birthDate = birth.date, birthDate <= now else { return nil }
        let calendar = birth.calendar
        var anniversaryYear = calendar.component(.year, from: now)
        guard let thisYear = anniversary(of: birth, year: anniversaryYear) else { return nil }
        if now < thisYear { anniversaryYear -= 1 }
        guard let previous = anniversary(of: birth, year: anniversaryYear),
              let next = anniversary(of: birth, year: anniversaryYear + 1) else { return nil }
        let years = anniversaryYear - birth.year
        let remainder = calendar.dateComponents([.month, .day, .hour, .minute, .second], from: previous, to: now)
        let elapsed = now.timeIntervalSince(birthDate)
        let milliseconds = min(999, max(0, Int((elapsed - floor(elapsed)) * 1_000)))
        return AgeSnapshot(years: years, months: remainder.month ?? 0, days: remainder.day ?? 0,
            hours: remainder.hour ?? 0, minutes: remainder.minute ?? 0, seconds: remainder.second ?? 0,
            milliseconds: milliseconds,
            decimalYears: Double(years) + now.timeIntervalSince(previous) / next.timeIntervalSince(previous),
            totalSeconds: elapsed)
    }
}

enum BirthdayPolicy {
    /// Celebrations follow today's local calendar date, independently of birth timezone/time.
    static func celebrationKey(birth: BirthDetails, now: Date, timeZone: TimeZone,
                               lastCelebratedDay: String?, sessionActive: Bool) -> String? {
        guard sessionActive, let birthDate = birth.date, birthDate <= now else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = today.year,
              let monthStart = calendar.date(from: DateComponents(year: year, month: birth.month, day: 1)),
              let monthDays = calendar.range(of: .day, in: .month, for: monthStart),
              today.month == birth.month, today.day == min(birth.day, monthDays.count) else { return nil }
        let key = String(format: "%04d-%02d-%02d", year, today.month!, today.day!)
        return key == lastCelebratedDay ? nil : key
    }
}
