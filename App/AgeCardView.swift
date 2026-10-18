import AppKit
import SwiftUI

final class CardActivity: ObservableObject {
    @Published var isRunning = false
}

struct AgeCardView: View {
    static let size = NSSize(width: 236, height: 84)
    private static let liveAgeSize = NSSize(width: 280, height: 64)
    @ObservedObject var store: PreferencesStore
    @ObservedObject var activity: CardActivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let showSettings: () -> Void

    static func size(for format: DesktopCardFormat, precision: SubsecondPrecision = .seconds) -> NSSize {
        guard [.liveAge, .countdown].contains(format) else { return size }
        let extraPrecisionWidth = CGFloat(precision.fractionalDigits / 3) * 16
        return NSSize(width: liveAgeSize.width + extraPrecisionWidth, height: liveAgeSize.height)
    }

    var body: some View {
        let format = store.preferences.cardFormat
        let precision = store.preferences.subsecondPrecision
        let cardSize = Self.size(for: format, precision: precision)
        let liveCard = format == .liveAge || format == .countdown
        let refreshInterval = reduceMotion ? 1 : (liveCard ? (precision == .seconds ? 1 : 0.05) : 0.5)
        TimelineView(.animation(minimumInterval: refreshInterval,
                                paused: !activity.isRunning)) { context in
            VStack(spacing: 4) {
                if let birth = store.preferences.birth,
                   let age = AgeCalculator.snapshot(birth: birth, now: context.date) {
                    ageContent(age, date: context.date)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityDescription(age, birth: birth, date: context.date))
                } else {
                    Text("—")
                        .accessibilityLabel("Set your birthday in Settings")
                }
            }
            .font(.system(size: 25, weight: .medium, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, [.liveAge, .countdown].contains(format) ? 0 : 14)
            .frame(width: cardSize.width, height: cardSize.height)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(CardDragSurface(showSettings: showSettings))
        }
    }

    @ViewBuilder private func ageContent(_ age: AgeSnapshot, date: Date) -> some View {
        switch store.preferences.cardFormat {
        case .detailed:
            Text(String(format: "%02d · %02d · %02d", age.years, age.months, age.days))
            HStack(spacing: 2) {
                Text(String(format: "%02d", age.hours))
                separator(date)
                Text(String(format: "%02d", age.minutes))
                separator(date)
                Text(String(format: "%02d", age.seconds))
            }
            .font(.system(size: 20, weight: .regular, design: .monospaced))
            .foregroundStyle(.secondary)
        case .decimalYears:
            Text(age.decimalYears.formattedDecimalYears(fractionDigits: 9))
        case .totalSeconds:
            Text(age.totalSeconds.formatted(.number.precision(.fractionLength(3))))
        case .liveAge:
            if let birth = store.preferences.birth {
                LiveAgeCardView(birth: birth, precision: store.preferences.subsecondPrecision, now: date)
            }
        case .countdown:
            if let birth = store.preferences.birth {
                LiveAgeCardView(birth: birth, mode: .remaining,
                                precision: store.preferences.subsecondPrecision, now: date)
            }
        }
    }

    private func accessibilityDescription(_ age: AgeSnapshot, birth: BirthDetails, date: Date) -> String {
        let description: String
        if store.preferences.cardFormat == .liveAge, let birthDate = birth.date {
            let parts = birth.calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: birthDate,
                to: max(date, birthDate))
            description = "\(parts.year ?? 0) years, \(parts.month ?? 0) months, \(parts.day ?? 0) days, " +
                "\(parts.hour ?? 0) hours, \(parts.minute ?? 0) minutes, \(parts.second ?? 0) seconds"
        } else if store.preferences.cardFormat == .countdown,
                  let parts = AgeCalculator.remainingParts(birth: birth, now: date, lifespanYears: 80) {
            description = "\(parts.year ?? 0) years, \(parts.month ?? 0) months, \(parts.day ?? 0) days, " +
                "\(parts.hour ?? 0) hours, \(parts.minute ?? 0) minutes, \(parts.second ?? 0) seconds"
        } else {
            description = age.accessibleDescription
        }
        return description + (birth.hasBirthTime ? "" : ", approximate")
    }

    private func separator(_ date: Date) -> some View {
        Text(":")
            .opacity(reduceMotion || date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.2)
    }
}

struct LiveAgeCardView: View {
    enum Mode: Equatable {
        case age
        case remaining
    }

    let birth: BirthDetails
    var mode: Mode = .age
    var lifespanYears = 80
    var precision: SubsecondPrecision = .seconds
    var now: Date = .now

    private var parts: DateComponents? {
        guard let birthDate = birth.date else { return nil }
        switch mode {
        case .age:
            return birth.calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: birthDate,
                to: max(now, birthDate))
        case .remaining:
            return AgeCalculator.remainingParts(birth: birth, now: now, lifespanYears: lifespanYears)
        }
    }

    private var fractionalInterval: TimeInterval? {
        guard let birthDate = birth.date else { return nil }
        switch mode {
        case .age:
            return max(0, now.timeIntervalSince(birthDate))
        case .remaining:
            guard let endDate = birth.calendar.date(byAdding: .year, value: lifespanYears, to: birthDate) else {
                return nil
            }
            return max(0, endDate.timeIntervalSince(now))
        }
    }

    var body: some View {
        if let parts, let fractionalInterval {
            HStack(alignment: .center, spacing: 10) {
                unit(parts.year, "YRS")
                unit(parts.month, "MOS")
                unit(parts.day, "DAYS", pad: false)
                unit(parts.hour, "HRS")
                unit(parts.minute, "MIN")
                unit(parts.second, "SEC", fraction: precision.fractionText(of: fractionalInterval))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 8)
        } else {
            Text("—")
        }
    }

    private func unit(_ value: Int?, _ label: String, pad: Bool = true, fraction: String? = nil) -> some View {
        let number = value ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(pad ? String(format: "%02d", number) : "\(number)")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: Double(number)))
                    .animation(.snappy, value: number)
                if let fraction {
                    Text(".\(fraction)")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: fraction)
                }
            }
            .monospacedDigit()
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
        }
    }
}

// Native window dragging keeps movement smooth even while the numbers update.
private struct CardDragSurface: NSViewRepresentable {
    let showSettings: () -> Void

    func makeNSView(context: Context) -> DragView { DragView() }

    func updateNSView(_ view: DragView, context: Context) {
        view.showSettings = showSettings
    }

    final class DragView: NSView {
        var showSettings: (() -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setAccessibilityElement(false)
            let menu = NSMenu()
            let item = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            self.menu = menu
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                if let menu { NSMenu.popUpContextMenu(menu, with: event, for: self) }
            } else {
                window?.performDrag(with: event)
            }
        }

        @objc private func openSettings() { showSettings?() }
    }
}
