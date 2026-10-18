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

    static func size(for format: DesktopCardFormat, subsecondUnits: Set<SubsecondUnit>) -> NSSize {
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

// Wallpaper layout: the age fills the whole screen, centered on a glass pane,
// sizing computed once from the screen. The panel ignores the mouse in this
// mode so desktop icons stay clickable underneath.
struct WallpaperAgeView: View {
    private struct Metrics {
        let digit: CGFloat
        let gap: CGFloat
        let panePadding: CGFloat
    }

    @ObservedObject var store: PreferencesStore
    @ObservedObject var activity: CardActivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let refreshInterval = reduceMotion
            ? 1
            : (store.preferences.subsecondUnits.isEmpty ? 1 : 0.049)
        TimelineView(.animation(minimumInterval: refreshInterval,
                                paused: !activity.isRunning)) { context in
            GeometryReader { geometry in
                centerContent(size: geometry.size, now: context.date)
            }
        }
    }

    @ViewBuilder private func centerContent(size: CGSize, now: Date) -> some View {
        if let birth = store.preferences.birth, let birthDate = birth.date {
            let metrics = metrics(size: size)
            let parts = birth.calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: birthDate,
                to: max(now, birthDate))
            let fractional = max(0, now.timeIntervalSince(birthDate))
            HStack(alignment: .center, spacing: metrics.gap) {
                ForEach(Array(units(parts: parts, fractional: fractional).enumerated()), id: \.offset) { unit in
                    numberUnit(text: unit.element.text, label: unit.element.label,
                               metrics: metrics, animated: unit.element.animated)
                }
            }
            .modifier(WallpaperGlassModifier(enabled: store.preferences.wallpaperGlass,
                                             panePadding: metrics.panePadding))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            let metrics = metrics(size: size)
            Text("—")
                .font(.system(size: metrics.digit * 1.2, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .modifier(WallpaperGlassModifier(enabled: store.preferences.wallpaperGlass,
                                                 panePadding: metrics.panePadding))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .accessibilityLabel("Set your birthday in Settings")
        }
    }

    // One row: six main units in order, then the enabled subsecond groups.
    private func units(parts: DateComponents, fractional: TimeInterval)
        -> [(text: String, label: String, animated: Bool)] {
        var rows = [
            (text: String(format: "%02d", parts.year ?? 0), label: "Years", animated: true),
            (text: String(format: "%02d", parts.month ?? 0), label: "Months", animated: true),
            (text: "\(parts.day ?? 0)", label: "Days", animated: true),
            (text: String(format: "%02d", parts.hour ?? 0), label: "HRS", animated: true),
            (text: String(format: "%02d", parts.minute ?? 0), label: "MINS", animated: true),
            (text: String(format: "%02d", parts.second ?? 0), label: "SECS", animated: true),
        ]
        rows += store.preferences.subsecondUnits
            .sorted { $0.groupIndex < $1.groupIndex }
            .map { unit -> (String, String, Bool) in
                (unit.formattedValue(of: fractional), unit.shortLabel, false)
            }
        return rows
    }

    private func metrics(size: CGSize) -> Metrics {
        let unitCount = CGFloat(6 + store.preferences.subsecondUnits.count)
        let digit = min(size.height * 0.24, size.width / unitCount * 0.13)
        let gap = min(64, size.width / (unitCount + 1) * 0.26, digit * 0.55)
        let panePadding = min(max(size.height * 0.06, 30), 80)
        return Metrics(digit: digit, gap: gap, panePadding: panePadding)
    }

    private func numberUnit(text: String, label: String, metrics: Metrics, animated: Bool) -> some View {
        VStack(alignment: .leading, spacing: metrics.digit * 0.12) {
            Text(text)
                .font(.system(size: metrics.digit, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(animated ? .numericText() : .identity)
                .animation(animated ? .snappy : nil, value: text)
            Text(label.uppercased())
                .font(.system(size: max(10, metrics.digit * 0.15), weight: .medium))
                .tracking(max(1, metrics.digit * 0.06))
                .foregroundStyle(.secondary)
        }
    }
}

// Wallpaper glass: frosted pane behind the big digits with a subtle top gloss,
// bright rim and soft shadow — the "liquid glass" look on macOS 26+.
private struct WallpaperGlassModifier: ViewModifier {
    let enabled: Bool
    let panePadding: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            content
                .modifier(GlassPaneModifier(cornerRadius: panePadding * 1.4, padding: panePadding))
        } else {
            content
                .padding(.horizontal, panePadding)
                .padding(.vertical, panePadding * 0.75)
                .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
        }
    }
}

private struct GlassPaneModifier: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let gloss = LinearGradient(
            stops: [
                .init(color: .white.opacity(0.20), location: 0.0),
                .init(color: .white.opacity(0.03), location: 0.32),
                .init(color: .white.opacity(0.06), location: 0.78),
                .init(color: .white.opacity(0.12), location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom)
        paneBase(content)
            .overlay { gloss.clipShape(shape).allowsHitTesting(false) }
            .overlay {
                shape.strokeBorder(.white.opacity(0.16), lineWidth: 1).allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.22), radius: 26, x: 0, y: 14)
    }

    @ViewBuilder private func paneBase(_ content: some View) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let padded = content
            .padding(.horizontal, padding)
            .padding(.vertical, padding * 0.75)
        if #available(macOS 26.0, *) {
            padded.glassEffect(.regular, in: shape)
        } else {
            padded.background(.ultraThinMaterial, in: shape)
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
