import AppIntents
import SwiftUI
import WidgetKit

extension AgeFormat: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Age format" }
    static var caseDisplayRepresentations: [AgeFormat: DisplayRepresentation] {
        [.detailed: "Detailed age", .decimalYears: "Decimal years", .totalSeconds: "Total seconds"]
    }
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

    @Parameter(title: "Age format", default: .detailed)
    var format: AgeFormat
}

struct LifeClockEntry: TimelineEntry {
    let date: Date
    let birth: BirthDetails?
    var format: AgeFormat = .detailed
    var isPreview = false
    var setupMessage = "Right-click this widget → Edit Widget to set your birthday."
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
        return LifeClockEntry(date: date, birth: birth, format: configuration.format)
    }
}

struct LifeClockWidgetView: View {
    let entry: LifeClockEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            if let birth = entry.birth,
               let age = AgeCalculator.snapshot(birth: birth, now: entry.date) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    ageContent(age)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(age.years) years, \(age.months) months, \(age.days) days old" + (birth.hasBirthTime ? "" : ", approximate") + (entry.isPreview ? ", preview" : ", as of \(entry.date.formatted(date: .omitted, time: .shortened))"))
                Text(entry.isPreview ? "Preview" : "As of \(entry.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityHidden(true)
                if !birth.hasBirthTime {
                    Text("Approximate")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
                if let birthDate = birth.date {
                    Text(birthDate, style: .timer)
                        .font(.system(size: family == .systemSmall ? 19 : 24,
                                      weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .help("Live time since birth")
                        .accessibilityLabel(Text("Time since birth: ") + Text(birthDate, style: .timer))
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text(entry.setupMessage)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                    .lineLimit(family == .systemSmall ? 5 : 7)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .accessibilityLabel(entry.setupMessage)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.background, for: .widget)
    }

    @ViewBuilder private func ageContent(_ age: AgeSnapshot) -> some View {
        switch entry.format {
        case .detailed:
            Text(String(format: "%02d · %02d · %02d", age.years, age.months, age.days))
                .font(.system(size: family == .systemSmall ? 26 : 30, weight: .medium, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5).lineLimit(1)
        case .decimalYears:
            Text(age.decimalYears.formattedDecimalYears(fractionDigits: 6))
                .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
        case .totalSeconds:
            Text(age.totalSeconds.rounded(.down).formatted(.number.precision(.fractionLength(0))))
                .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
        }
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
