import AppKit
import SwiftUI

private final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DesktopCardController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let activity = CardActivity()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var awake = true
    private var displayAwake = true
    private var sessionActive = true

    init(store: PreferencesStore, showSettings: @escaping () -> Void) {
        let cardSize = AgeCardView.size(for: store.preferences.cardFormat,
                                        precision: store.preferences.subsecondPrecision)
        panel = DesktopPanel(contentRect: NSRect(origin: .zero, size: cardSize),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.delegate = self
        panel.title = "Life Clock"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: AgeCardView(store: store, activity: activity,
                                                               showSettings: showSettings))
        if !panel.setFrameUsingName("LifeClockCard") { panel.center() }
        panel.setContentSize(cardSize)
        panel.setFrameAutosaveName("LifeClockCard")
        keepOnScreen()

        observe(.default, NSWindow.didChangeOcclusionStateNotification) { [weak self] in self?.updateActivity() }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in self?.keepOnScreen() }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in
            self?.awake = false; self?.updateActivity()
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            self?.awake = true; self?.updateActivity()
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.displayAwake = false; self?.updateActivity()
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.displayAwake = true; self?.updateActivity()
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            self?.sessionActive = false; self?.updateActivity()
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.sessionActive = true; self?.updateActivity()
        }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.sessionActive = false; self?.updateActivity()
        }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.sessionActive = true; self?.updateActivity()
        }
    }

    func apply(_ preferences: LifePreferences) {
        let cardSize = AgeCardView.size(for: preferences.cardFormat,
                                        precision: preferences.subsecondPrecision)
        if panel.contentView?.frame.size != cardSize {
            panel.setContentSize(cardSize)
            keepOnScreen()
        }
        panel.level = preferences.alwaysOnTop ? .floating
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = preferences.alwaysOnTop
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            : [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if preferences.cardEnabled && preferences.birth != nil { show() } else { panel.orderOut(nil) }
        updateActivity()
    }

    func show() {
        keepOnScreen()
        panel.orderFrontRegardless()
        updateActivity()
    }

    func windowDidMove(_ notification: Notification) { panel.saveFrame(usingName: "LifeClockCard") }

    private func keepOnScreen() {
        guard !NSScreen.screens.contains(where: { $0.visibleFrame.contains(panel.frame) }),
              let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        let origin = NSPoint(x: max(area.minX, min(panel.frame.minX, area.maxX - panel.frame.width)),
                             y: max(area.minY, min(panel.frame.minY, area.maxY - panel.frame.height)))
        panel.setFrameOrigin(origin)
    }

    private func updateActivity() {
        let running = awake && displayAwake && sessionActive && panel.isVisible && panel.occlusionState.contains(.visible)
        if activity.isRunning != running { activity.isRunning = running }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, token))
    }

    deinit { observers.forEach { $0.0.removeObserver($0.1) } }
}
