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
        let subsecondUnits: Set<SubsecondUnit> = reduceMotion ? [] : store.preferences.subsecondUnits
        let cardSize = Self.size(for: format, subsecondUnits: subsecondUnits)
        let liveCard = format == .liveAge || format == .countdown
        let refreshInterval = format.minimumTimelineInterval(subsecondUnits: subsecondUnits,
                                                              reduceMotion: reduceMotion)
        TimelineView(.animation(minimumInterval: refreshInterval,
                                paused: !activity.isRunning)) { context in
            VStack(spacing: 4) {
                if let birth = store.preferences.birth,
                   let age = AgeCalculator.snapshot(birth: birth, now: context.date),
                   let reading = age.reading(for: format, birth: birth, now: context.date) {
                    ageContent(age, reading: reading, date: context.date)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityDescription(reading, birth: birth))
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

    @ViewBuilder private func ageContent(_ age: AgeSnapshot, reading: ClockReading, date: Date) -> some View {
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
            LiveAgeCardView(reading: reading, subsecondUnits: store.preferences.subsecondUnits)
        case .countdown:
            LiveAgeCardView(reading: reading, subsecondUnits: store.preferences.subsecondUnits)
        }
    }

    private func accessibilityDescription(_ reading: ClockReading, birth: BirthDetails) -> String {
        reading.accessibleDescription + (birth.hasBirthTime ? "" : ", approximate")
    }

    private func separator(_ date: Date) -> some View {
        Text(":")
            .opacity(reduceMotion || date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.2)
    }
}

struct LiveAgeCardView: View {
    let reading: ClockReading
    var subsecondUnits: Set<SubsecondUnit> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            unit(reading.parts.year, "YRS", numberSize: 33)
            unit(reading.parts.month, "MONTH", numberSize: 33)
            unit(reading.parts.day, "DAYS", numberSize: 33, pad: false)
            unit(reading.parts.hour, "HRS", numberSize: 33)
            unit(reading.parts.minute, "MIN", numberSize: 33)
            unit(reading.parts.second, "SEC", numberSize: 33)
            ForEach(SubsecondUnit.allCases.filter { !reduceMotion && subsecondUnits.contains($0) }) { subsecondUnit in
                SubsecondValueColumn(
                    value: subsecondUnit.formattedValue(of: reading.totalSeconds),
                    label: subsecondUnit.shortLabel,
                    accessibilityLabel: subsecondUnit.title)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 10)
    }

    private func unit(_ value: Int?, _ label: String, numberSize: CGFloat, pad: Bool = true) -> some View {
        let number = value ?? 0
        return textUnit(pad ? String(format: "%02d", number) : "\(number)", label, numberSize: numberSize)
    }

    private func textUnit(_ value: String, _ label: String, numberSize: CGFloat,
                          transition: ContentTransition = .numericText(),
                          animation: Animation? = .snappy) -> some View {
        return VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: numberSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(reduceMotion ? .identity : transition)
                .animation(reduceMotion ? nil : animation, value: value)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SubsecondValueColumn: View {
    let value: String
    let label: String
    let accessibilityLabel: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            valueText
                .accessibilityLabel("\(accessibilityLabel): \(value)")
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var valueText: some View {
        let text = Text(value)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        if reduceMotion {
            text
        } else {
            text.keyframeAnimator(initialValue: 1.0, trigger: value) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(1.035, duration: 0.035)
                    LinearKeyframe(1.0, duration: 0.085)
                }
            }
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
        let columnWidth: CGFloat
        let rowWidth: CGFloat
        let panePadding: CGFloat
        let paneWidth: CGFloat
        let paneHeight: CGFloat
    }

    @ObservedObject var store: PreferencesStore
    @ObservedObject var activity: CardActivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleSubsecondUnits: Set<SubsecondUnit> {
        reduceMotion ? [] : store.preferences.subsecondUnits
    }

    var body: some View {
        // Same frame-rate rule as the card: subsecond digits get uncapped
        // timeline updates, plain seconds tick once per second.
        let format = store.preferences.cardFormat
        let refreshInterval = format.minimumTimelineInterval(
            subsecondUnits: visibleSubsecondUnits,
            reduceMotion: reduceMotion)
        // Read every preference OUTSIDE the timeline: a paused timeline caches
        // frames, so live slider changes must not depend on it re-ticking.
        GeometryReader { geometry in
            let size = geometry.size
            let preferences = store.preferences
            let metrics = metrics(size: size, scale: preferences.wallpaperSize)
            let maxSlackX = max(0, (size.width - metrics.paneWidth) / 2)
            let maxSlackY = max(0, (size.height - metrics.paneHeight) / 2)
            let fullScreenGlass = preferences.wallpaperGlass && preferences.wallpaperGlassFullScreen
            TimelineView(.animation(minimumInterval: refreshInterval,
                                    paused: !activity.isRunning)) { context in
                centerContent(size: size, metrics: metrics, preferences: preferences,
                              maxSlackX: maxSlackX, maxSlackY: maxSlackY,
                              fullScreenGlass: fullScreenGlass, now: context.date)
            }
        }
    }

    @ViewBuilder private func centerContent(size: CGSize, metrics: Metrics,
                                            preferences: LifePreferences,
                                            maxSlackX: CGFloat, maxSlackY: CGFloat,
                                            fullScreenGlass: Bool, now: Date) -> some View {
        if let birth = preferences.birth, birth.date != nil {
            if let snapshot = AgeCalculator.snapshot(birth: birth, now: now),
               let reading = snapshot.reading(for: preferences.cardFormat, birth: birth, now: now) {
                ageContent(preferences: preferences, snapshot: snapshot, reading: reading,
                           metrics: metrics, now: now)
                    .modifier(WallpaperGlassModifier(enabled: preferences.wallpaperGlass && !fullScreenGlass,
                                                     panePadding: metrics.panePadding,
                                                     roundness: preferences.wallpaperRoundness,
                                                     strength: preferences.wallpaperGlassStrength))
                    .offset(x: preferences.wallpaperOffsetX * maxSlackX,
                            y: -preferences.wallpaperOffsetY * maxSlackY)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .modifier(WallpaperScreenGlassModifier(enabled: fullScreenGlass,
                                                           strength: preferences.wallpaperGlassStrength))
            } else {
                Text("—")
                    .font(.system(size: metrics.digit * 1.2, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .modifier(WallpaperGlassModifier(enabled: preferences.wallpaperGlass && !fullScreenGlass,
                                                     panePadding: metrics.panePadding,
                                                     roundness: preferences.wallpaperRoundness,
                                                     strength: preferences.wallpaperGlassStrength))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .accessibilityLabel("Set your birthday in Settings")
                    .modifier(WallpaperScreenGlassModifier(enabled: fullScreenGlass,
                                                           strength: preferences.wallpaperGlassStrength))
            }
        } else {
            Text("—")
                .font(.system(size: metrics.digit * 1.2, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .modifier(WallpaperGlassModifier(enabled: preferences.wallpaperGlass && !fullScreenGlass,
                                                 panePadding: metrics.panePadding,
                                                 roundness: preferences.wallpaperRoundness,
                                                 strength: preferences.wallpaperGlassStrength))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .accessibilityLabel("Set your birthday in Settings")
                .modifier(WallpaperScreenGlassModifier(enabled: fullScreenGlass,
                                                       strength: preferences.wallpaperGlassStrength))
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
        rows += visibleSubsecondUnits
            .sorted { $0.groupIndex < $1.groupIndex }
            .map { unit -> (String, String, Bool) in
                (unit.formattedValue(of: fractional), unit.shortLabel, false)
            }
        return rows
    }

    // Wallpaper bodies per Display format; glass/offsets wrap the whole result.
    @ViewBuilder private func ageContent(preferences: LifePreferences,
                                         snapshot: AgeSnapshot, reading: ClockReading,
                                         metrics: Metrics, now: Date) -> some View {
        switch preferences.cardFormat {
        case .liveAge, .countdown:
            HStack(alignment: .center, spacing: metrics.gap) {
                ForEach(Array(units(parts: reading.parts, fractional: reading.totalSeconds).enumerated()), id: \.offset) { unit in
                    numberUnit(text: unit.element.text, label: unit.element.label,
                               metrics: metrics, animated: unit.element.animated)
                }
            }
            .frame(width: metrics.rowWidth)
        case .detailed:
            VStack(alignment: .center, spacing: metrics.digit * 0.18) {
                Text(String(format: "%02d · %02d · %02d",
                            reading.parts.year ?? 0, reading.parts.month ?? 0, reading.parts.day ?? 0))
                    .font(.system(size: metrics.digit, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .shadow(color: .black.opacity(0.22), radius: 2.5, x: 0, y: 1)
                HStack(alignment: .center, spacing: metrics.digit * 0.18) {
                    Text(String(format: "%02d", reading.parts.hour ?? 0))
                    Text(":").opacity(reduceMotion ? 1 : secondsPhase(now))
                    Text(String(format: "%02d", reading.parts.minute ?? 0))
                    Text(":").opacity(reduceMotion ? 1 : secondsPhase(now))
                    Text(String(format: "%02d", reading.parts.second ?? 0))
                }
                .font(.system(size: metrics.digit * 0.45, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .frame(width: metrics.rowWidth)
        case .decimalYears:
            Text(snapshot.decimalYears.formattedDecimalYears(fractionDigits: 9))
                .font(.system(size: metrics.digit, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .shadow(color: .black.opacity(0.22), radius: 2.5, x: 0, y: 1)
                .frame(width: metrics.rowWidth)
        case .totalSeconds:
            Text(snapshot.totalSeconds.formatted(.number.precision(.fractionLength(3))))
                .font(.system(size: metrics.digit, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .shadow(color: .black.opacity(0.22), radius: 2.5, x: 0, y: 1)
                .frame(width: metrics.rowWidth)
        }
    }

    private func secondsPhase(_ now: Date) -> Double {
        now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) < 1 ? 1 : 0.3
    }
    // Equal-width columns across a wide hero row. Single-value formats
    // (detailed, decimal years, total seconds) size one wide column instead.
    // Digit size is capped by the scaled row width and the scaled screen
    // height so the pane stays inside the screen; offsets use the leftover slack.
    private func metrics(size: CGSize, scale: Double) -> Metrics {
        let format = store.preferences.cardFormat
        let panePadding = min(max(size.height * 0.07, 36), 110)
        let growth = CGFloat(max(0.05, scale))
        let lineFactor: CGFloat
        if format == .liveAge || format == .countdown {
            let columns = CGFloat(6 + visibleSubsecondUnits.count)
            let targetRow = size.width * 0.9 * growth
            let columnAdvance = 2.4 + 0.55
            let verticalBudget = (size.height - panePadding * 1.5) / 1.4
            let digit = min(size.height * 0.26 * growth,
                            targetRow / (columns * columnAdvance - 0.55),
                            verticalBudget)
            let gap = digit * 0.55
            let columnWidth = digit * 2.4
            let rowWidth = columns * columnWidth + (columns - 1) * gap
            lineFactor = 1.4
            return Metrics(digit: digit, gap: gap, columnWidth: columnWidth,
                           rowWidth: rowWidth, panePadding: panePadding,
                           paneWidth: rowWidth + panePadding * 2,
                           paneHeight: digit * lineFactor + panePadding * 1.5)
        } else {
            // "17 · 07 · 24" ≈ 12 characters; decimal years and total seconds
            // land in the same ballpark, so one estimate serves all three.
            let charWidth = CGFloat(12) * 0.62
            let digit = min(size.height * 0.26 * growth,
                            size.width * 0.85 * growth / charWidth)
            lineFactor = format == .detailed ? 1.9 : 1.45
            return Metrics(digit: digit, gap: digit * 0.55, columnWidth: digit * charWidth,
                           rowWidth: digit * charWidth, panePadding: panePadding,
                           paneWidth: digit * charWidth + panePadding * 2,
                           paneHeight: digit * lineFactor + panePadding * 1.5)
        }
    }

    private func numberUnit(text: String, label: String, metrics: Metrics, animated: Bool) -> some View {
        VStack(alignment: .center, spacing: metrics.digit * 0.1) {
            Text(text)
                .font(.system(size: metrics.digit, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(!reduceMotion && animated ? .numericText() : .identity)
                .animation(!reduceMotion && animated ? .snappy : nil, value: text)
                // Keeps digits legible on bright wallpaper patches without
                // looking like a hard outline.
                .shadow(color: .black.opacity(0.22), radius: 2.5, x: 0, y: 1)
            Text(label.uppercased())
                .font(.system(size: max(10, metrics.digit * 0.15), weight: .medium))
                .tracking(max(1, metrics.digit * 0.06))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.secondary)
        }
        .frame(width: metrics.columnWidth)
    }
}

// Wallpaper glass: frosted pane behind the big digits with a subtle top gloss,
// bright rim and soft shadow — the "liquid glass" look on macOS 26+.
private struct WallpaperGlassModifier: ViewModifier {
    let enabled: Bool
    let panePadding: CGFloat
    let roundness: CGFloat
    let strength: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            content
                .modifier(GlassPaneModifier(cornerRadius: panePadding * roundness, padding: panePadding,
                                            strength: strength))
        } else {
            content
                .padding(.horizontal, panePadding)
                .padding(.vertical, panePadding * 0.75)
                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
        }
    }
}

private struct GlassPaneModifier: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let strength: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let gloss = LinearGradient(
            stops: [
                .init(color: .white.opacity(0.10 * sheen), location: 0.0),
                .init(color: .white.opacity(0.015 * sheen), location: 0.36),
                .init(color: .white.opacity(0.03 * sheen), location: 0.80),
                .init(color: .white.opacity(0.05 * sheen), location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom)
        paneBase(content)
            .overlay {
                // Neutral smoke veil: paired low-opacity black + white washes
                // cancel out to a grain-free translucent darkening that reads
                // softly on light and dark wallpapers alike.
                shape.fill(Color.black.opacity(0.13 * strength))
                    .allowsHitTesting(false)
                shape.fill(Color.white.opacity(0.13 * strength))
                    .allowsHitTesting(false)
            }
            .overlay { gloss.clipShape(shape).allowsHitTesting(false) }
            .overlay {
                shape.strokeBorder(.white.opacity(0.14), lineWidth: 1).allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 8)
    }

    // Gloss intensity follows the slider a little (0.5× at clarity … 1× at heavy).
    var sheen: CGFloat { 0.5 + 0.5 * strength }

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

// Full-screen variant: glass spans the entire screen behind the digits.
private struct WallpaperScreenGlassModifier: ViewModifier {
    let enabled: Bool
    let strength: CGFloat

    func body(content: Content) -> some View {
        let sheen = 0.5 + 0.5 * strength
        let gloss = LinearGradient(
            stops: [
                .init(color: .white.opacity(0.08 * sheen), location: 0.0),
                .init(color: .white.opacity(0.012 * sheen), location: 0.34),
                .init(color: .white.opacity(0.028 * sheen), location: 0.78),
                .init(color: .white.opacity(0.045 * sheen), location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom)
        if enabled {
            // Whole-screen mode stays grain-free: a single neutral scrim whose
            // depth follows the strength slider, no stacked materials.
            content
                .overlay {
                    Rectangle().fill(Color.black.opacity(0.16 * strength))
                        .allowsHitTesting(false)
                    Rectangle().fill(Color.white.opacity(0.16 * strength))
                        .allowsHitTesting(false)
                }
                .overlay { gloss.allowsHitTesting(false) }
        } else {
            content
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
            guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first,
                  let frame = CardFramePolicy.resize(startingFrame,
                      by: CGSize(width: mouseLocation.x - startingMouseLocation.x,
                                 height: startingMouseLocation.y - mouseLocation.y),
                      in: screen.visibleFrame, minimumSize: minimumSize) else { return }
            window.setFrame(frame, display: true)
        }

        override func mouseUp(with event: NSEvent) {
            window?.saveFrame(usingName: "LifeClockCard")
            startingFrame = nil
            startingMouseLocation = nil
        }
    }
}
