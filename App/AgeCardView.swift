import AppKit
import SwiftUI

final class CardActivity: ObservableObject {
    @Published var isRunning = false
}

struct AgeCardView: View {
    static let size = NSSize(width: 236, height: 84)
    private static let liveAgeSize = NSSize(width: 390, height: 104)
    @ObservedObject var store: PreferencesStore
    @ObservedObject var activity: CardActivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let showSettings: () -> Void

    static func size(for format: DesktopCardFormat) -> NSSize {
        format == .liveAge ? liveAgeSize : size
    }

    var body: some View {
        let format = store.preferences.cardFormat
        let cardSize = Self.size(for: format)
        TimelineView(.animation(minimumInterval: reduceMotion || format == .liveAge ? 1 : 0.5,
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
            .padding(.horizontal, format == .liveAge ? 0 : 14)
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
                liveAgeContent(birth, date: date)
            }
        }
    }

    @ViewBuilder private func liveAgeContent(_ birth: BirthDetails, date: Date) -> some View {
        if let birthDate = birth.date {
            let parts = birth.calendar.dateComponents(
                [.year, .day, .hour, .minute, .second],
                from: birthDate,
                to: max(date, birthDate))
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 18) {
                    liveAgeUnit(parts.day, "DAYS", pad: false)
                    liveAgeUnit(parts.hour, "HRS")
                    liveAgeUnit(parts.minute, "MIN")
                    liveAgeUnit(parts.second, "SEC")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(16)
        } else {
            Text("—")
        }
    }

    private func liveAgeUnit(_ value: Int?, _ label: String, pad: Bool = true) -> some View {
        let number = value ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            Text(pad ? String(format: "%02d", number) : "\(number)")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(number)))
                .animation(.snappy, value: number)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
        }
    }

    private func accessibilityDescription(_ age: AgeSnapshot, birth: BirthDetails, date: Date) -> String {
        let description: String
        if store.preferences.cardFormat == .liveAge, let birthDate = birth.date {
            let parts = birth.calendar.dateComponents(
                [.year, .day, .hour, .minute, .second],
                from: birthDate,
                to: max(date, birthDate))
            description = "\(parts.year ?? 0) years, \(parts.day ?? 0) days, " +
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
