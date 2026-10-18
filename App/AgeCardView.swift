import AppKit
import SwiftUI

final class CardActivity: ObservableObject {
    @Published var isRunning = false
}

struct AgeCardView: View {
    static let size = NSSize(width: 236, height: 84)
    private static let liveAgeBaseSize = NSSize(width: 350, height: 100)
    @ObservedObject var store: PreferencesStore
    @ObservedObject var activity: CardActivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let showSettings: () -> Void

    static func size(for format: DesktopCardFormat, subsecondUnits: Set<SubsecondUnit> = []) -> NSSize {
        guard [.liveAge, .countdown].contains(format) else { return size }
        let extraPrecisionWidth = CGFloat(subsecondUnits.count) * 40
        return NSSize(width: liveAgeBaseSize.width + extraPrecisionWidth, height: liveAgeBaseSize.height)
    }

    var body: some View {
        let format = store.preferences.cardFormat
        let subsecondUnits = store.preferences.subsecondUnits
        let cardSize = Self.size(for: format, subsecondUnits: subsecondUnits)
        let liveCard = format == .liveAge || format == .countdown
        let refreshInterval = reduceMotion ? 1 : (liveCard ? (subsecondUnits.isEmpty ? 1 : 0.049) : 0.5)
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
            .frame(minWidth: cardSize.width, maxWidth: .infinity, minHeight: cardSize.height, maxHeight: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(CardDragSurface(showSettings: showSettings))
            .overlay(alignment: .bottomTrailing) {
                if liveCard {
                    ResizeCornerHandle(minimumSize: cardSize)
                        .frame(width: 20, height: 20)
                        .padding(3)
                        .accessibilityLabel("Resize Life Clock card")
                }
            }
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
                LiveAgeCardView(birth: birth, subsecondUnits: store.preferences.subsecondUnits, now: date)
            }
        case .countdown:
            if let birth = store.preferences.birth {
                LiveAgeCardView(birth: birth, mode: .remaining,
                                subsecondUnits: store.preferences.subsecondUnits, now: date)
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
    var subsecondUnits: Set<SubsecondUnit> = []
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
            HStack(alignment: .center, spacing: 8) {
                unit(parts.year, "YRS", numberSize: 33)
                unit(parts.month, "MONTH", numberSize: 33)
                unit(parts.day, "DAYS", numberSize: 33, pad: false)
                unit(parts.hour, "HRS", numberSize: 33)
                unit(parts.minute, "MIN", numberSize: 33)
                unit(parts.second, "SEC", numberSize: 33)
                ForEach(SubsecondUnit.allCases.filter { subsecondUnits.contains($0) }) { subsecondUnit in
                    textUnit(subsecondUnit.formattedValue(of: fractionalInterval), subsecondUnit.shortLabel,
                             numberSize: 18, animated: false)
                        .accessibilityLabel("\(subsecondUnit.title): \(subsecondUnit.formattedValue(of: fractionalInterval))")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 10)
        } else {
            Text("—")
        }
    }

    private func unit(_ value: Int?, _ label: String, numberSize: CGFloat, pad: Bool = true) -> some View {
        let number = value ?? 0
        return textUnit(pad ? String(format: "%02d", number) : "\(number)", label, numberSize: numberSize)
    }

    private func textUnit(_ value: String, _ label: String, numberSize: CGFloat,
                          animated: Bool = true) -> some View {
        return VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: numberSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(animated ? .numericText() : .identity)
                .animation(animated ? .snappy : nil, value: value)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
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

private struct ResizeCornerHandle: NSViewRepresentable {
    let minimumSize: NSSize

    func makeNSView(context: Context) -> ResizeView {
        ResizeView(minimumSize: minimumSize)
    }

    func updateNSView(_ view: ResizeView, context: Context) {
        view.minimumSize = minimumSize
    }

    final class ResizeView: NSView {
        var minimumSize: NSSize
        private var startingFrame: NSRect?
        private var startingMouseLocation: NSPoint?

        init(minimumSize: NSSize) {
            self.minimumSize = minimumSize
            super.init(frame: .zero)
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel("Resize Life Clock card")
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeUpDown)
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            let grip = NSBezierPath()
            for offset: CGFloat in [6, 10, 14] {
                grip.move(to: NSPoint(x: bounds.maxX - offset, y: bounds.minY + 2))
                grip.line(to: NSPoint(x: bounds.maxX - 2, y: bounds.minY + offset))
            }
            NSColor.secondaryLabelColor.withAlphaComponent(0.8).setStroke()
            grip.lineWidth = 1.5
            grip.stroke()
        }

        override func mouseDown(with event: NSEvent) {
            startingFrame = window?.frame
            startingMouseLocation = NSEvent.mouseLocation
        }

        override func mouseDragged(with event: NSEvent) {
            guard let startingFrame, let startingMouseLocation, let window else { return }
            let mouseLocation = NSEvent.mouseLocation
            let width = max(minimumSize.width, startingFrame.width + mouseLocation.x - startingMouseLocation.x)
            let height = max(minimumSize.height, startingFrame.height - mouseLocation.y + startingMouseLocation.y)
            window.setFrame(NSRect(x: startingFrame.minX,
                                   y: startingFrame.maxY - height,
                                   width: width,
                                   height: height), display: true)
        }

        override func mouseUp(with event: NSEvent) {
            window?.saveFrame(usingName: "LifeClockCard")
            startingFrame = nil
            startingMouseLocation = nil
        }
    }
}
