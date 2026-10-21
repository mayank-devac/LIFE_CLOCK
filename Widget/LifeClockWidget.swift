import AppIntents
import SwiftUI
import WidgetKit

struct WidgetClockModeOptions: DynamicOptionsProvider {
    func results() async throws -> [String] { WidgetClockMode.allCases.map(\.title) }
    func defaultResult() async -> String? { WidgetClockMode.age.title }
}

struct BirthTimeZoneOptions: DynamicOptionsProvider {
    func results() async throws -> [String] {
        let device = TimeZone.current.identifier
        return [device] + TimeZone.knownTimeZoneIdentifiers.filter { $0 != device }
    }

    func defaultResult() async -> String? { TimeZone.current.identifier }
}

struct BirthDayOptions: DynamicOptionsProvider {
    func results() async throws -> [String] { (1...31).map { String(format: "%02d", $0) } }
}

struct BirthMonthOptions: DynamicOptionsProvider {
    func results() async throws -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.monthSymbols.enumerated().map { String(format: "%02d %@", $0.offset + 1, $0.element) }
    }
}

struct BirthYearOptions: DynamicOptionsProvider {
    func results() async throws -> [String] {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        return (1900...year).reversed().map(String.init)
    }
}

struct LifeClockConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Life Clock settings"
    static var description = IntentDescription("Widget settings")

    @Parameter(title: "Day", optionsProvider: BirthDayOptions())
    var birthDay: String?

    @Parameter(title: "Month", optionsProvider: BirthMonthOptions())
    var birthMonth: String?

    @Parameter(title: "Year", optionsProvider: BirthYearOptions())
    var birthYear: String?

    @Parameter(title: "Birth time (HH:mm, optional)")
    var birthTime: String?

    @Parameter(title: "Birth timezone", optionsProvider: BirthTimeZoneOptions())
    var timeZoneID: String

    @Parameter(title: "Clock", optionsProvider: WidgetClockModeOptions())
    var mode: String?

    var selectedMode: WidgetClockMode { WidgetClockMode(selection: mode) }

    @Parameter(title: "Target age (personal estimate)", default: 80, inclusiveRange: (1, 150))
    var targetAge: Int

    @Parameter(title: "Months", default: true)
    var showMonths: Bool

    @Parameter(title: "Days", default: true)
    var showTimerDays: Bool

    @Parameter(title: "Hours", default: false)
    var showTimerHours: Bool

    @Parameter(title: "Minutes", default: false)
    var showTimerMinutes: Bool

    @Parameter(title: "Seconds", default: false)
    var showTimerSeconds: Bool

    var selectedFields: Set<Date.ComponentsFormatStyle.Field> {
        var fields: Set<Date.ComponentsFormatStyle.Field> = [.year]
        if showMonths { fields.insert(.month) }
        if showTimerDays { fields.insert(.day) }
        if showTimerHours { fields.insert(.hour) }
        if showTimerMinutes { fields.insert(.minute) }
        if showTimerSeconds { fields.insert(.second) }
        return fields
    }

    static var parameterSummary: some ParameterSummary {
        When(\.$mode, .equalTo, "Years remaining") {
            Summary {
                \.$birthDay
                \.$birthMonth
                \.$birthYear
                \.$birthTime
                \.$timeZoneID
                \.$mode
                \.$targetAge
                \.$showMonths
                \.$showTimerDays
                \.$showTimerHours
                \.$showTimerMinutes
                \.$showTimerSeconds
            }
        } otherwise: {
            Summary {
                \.$birthDay
                \.$birthMonth
                \.$birthYear
                \.$birthTime
                \.$timeZoneID
                \.$mode
                \.$showMonths
                \.$showTimerDays
                \.$showTimerHours
                \.$showTimerMinutes
                \.$showTimerSeconds
            }
        }
    }
}

struct LifeClockEntry: TimelineEntry {
    let date: Date
    let birth: BirthDetails?
    var mode: WidgetClockMode = .age
    var targetAge: Int = 80
    var fields: Set<Date.ComponentsFormatStyle.Field> = [.year, .month, .day]
    var isPreview = false
    var setupMessage: String?
}

struct LifeClockProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> LifeClockEntry {
        LifeClockEntry(date: Date(), birth:
            BirthDetails(year: 2000, month: 1, day: 1, timeZoneID: "UTC"), isPreview: true)
    }

    func snapshot(for configuration: LifeClockConfiguration, in context: Context) async -> LifeClockEntry {
        let entry = makeEntry(for: configuration, date: Date())
        return context.isPreview && configuration.birthYear == nil ? placeholder(in: context) : entry
    }

    func timeline(for configuration: LifeClockConfiguration, in context: Context) async -> Timeline<LifeClockEntry> {
        let now = Date()
        let minute = floor(now.timeIntervalSinceReferenceDate / 60) * 60
        var entries = [makeEntry(for: configuration, date: now)]
        for offset in 1...60 {
            entries.append(makeEntry(for: configuration,
                date: Date(timeIntervalSinceReferenceDate: minute + Double(offset * 60))))
        }
        // Include the stop instant so the offset clock is replaced by zero at the target.
        if let first = entries.first, first.mode == .remaining,
           let birth = first.birth, let birthDate = birth.date,
           let target = birth.calendar.date(byAdding: .year, value: first.targetAge, to: birthDate),
           target > now, let last = entries.last, target <= last.date {
            entries.append(makeEntry(for: configuration, date: target))
            entries.sort { $0.date < $1.date }
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func makeEntry(for configuration: LifeClockConfiguration, date: Date) -> LifeClockEntry {
        guard let day = configuration.birthDay, let month = configuration.birthMonth,
              let year = configuration.birthYear else {
            return LifeClockEntry(date: date, birth: nil)
        }
        guard let birth = BirthDetails(day: day, month: month, year: year, time: configuration.birthTime,
                                       timeZoneID: configuration.timeZoneID),
              let birthDate = birth.date, birthDate <= Date() else {
            return LifeClockEntry(date: date, birth: nil,
                setupMessage: "Edit Widget: choose a valid past birthday, birth time and timezone.")
        }
        return LifeClockEntry(date: date, birth: birth, mode: configuration.selectedMode,
                              targetAge: min(150, max(1, configuration.targetAge)),
                              fields: configuration.selectedFields)
    }
}

struct LifeClockWidgetView: View {
    let entry: LifeClockEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let birth = entry.birth, let birthDate = birth.date,
               let target = birth.calendar.date(byAdding: .year, value: entry.targetAge, to: birthDate) {
                Text(entry.mode == .age ? "Your age" : "Years remaining")
                    .font(.subheadline.weight(.medium))
                clockText(birth: birth, birthDate: birthDate, target: target)
                    .font(.system(size: family == .systemSmall ? 22 : 28,
                                  weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.leading)
                    .lineLimit(family == .systemSmall ? 4 : 3)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel(Text(accessibilityPrefix(birth)) + clockText(birth: birth, birthDate: birthDate, target: target))
            } else {
                Text("Set your birthday").font(.headline)
                if let message = entry.setupMessage {
                    Text(message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    setupDiagram
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.background, for: .widget)
    }

    private var setupDiagram: some View {
        let small = family == .systemSmall
        let layout = small
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
            : AnyLayout(HStackLayout(spacing: 5))
        let steps = ["Add widget", "Set birthday", "Choose clock"]
        return layout {
            ForEach(steps.indices, id: \.self) { index in
                if index > 0 {
                    Image(systemName: small ? "arrow.down" : "arrow.right")
                        .font(.system(size: 9))
                        .accessibilityHidden(true)
                }
                Text(steps[index])
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.secondary, lineWidth: 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Add widget, then set birthday, then choose clock")
        .accessibilityHint("Right-click this widget and choose Edit Widget to begin.")
        .help("Right-click this widget and choose Edit Widget to begin.")
    }

    private func clockText(birth: BirthDetails, birthDate: Date, target: Date) -> Text {
        let style = Date.ComponentsFormatStyle(style: .abbreviated,
                                              calendar: birth.calendar, fields: entry.fields)
        if #available(macOS 15.0, *) {
            if entry.mode == .remaining {
                guard entry.date < target else { return Text(style.format(target..<target)) }
                // DateOffset schedules against the moving current date, unlike the frozen
                // lower-bound updates observed with dateRange(endingAt:) in the widget host.
                return Text(.currentDate, format: .offset(to: target,
                    allowedFields: entry.fields, maxFieldCount: entry.fields.count,
                    sign: .never).calendar(birth.calendar))
            }
            return Text(.dateRange(startingAt: birthDate), format: style)
        }
        // macOS 14 cannot render live calendar components; retain the same units in timeline snapshots.
        let range = entry.mode == .remaining
            ? min(entry.date, target)..<target
            : birthDate..<max(birthDate, entry.date)
        return Text(style.format(range))
    }

    private func accessibilityPrefix(_ birth: BirthDetails) -> String {
        let mode = entry.mode == .age ? "Age: " : "Time until target age \(entry.targetAge): "
        return mode + (birth.hasBirthTime ? "" : "Approximate. ")
    }
}

@main
struct LifeClockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "LifeClockWidget", intent: LifeClockConfiguration.self,
                               provider: LifeClockProvider()) { entry in
            LifeClockWidgetView(entry: entry)
        }
        .configurationDisplayName("Life Clock")
        .description("Your age.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
