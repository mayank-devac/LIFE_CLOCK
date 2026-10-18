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
    private var wallpaperActive = false
    private let store: PreferencesStore
    private let showSettings: () -> Void

    init(store: PreferencesStore, showSettings: @escaping () -> Void) {
        self.store = store
        self.showSettings = showSettings
        let cardSize = AgeCardView.size(for: store.preferences.cardFormat,
                                        subsecondUnits: store.preferences.subsecondUnits)
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
        panel.minSize = cardSize
        panel.contentView = NSHostingView(rootView: AgeCardView(store: store, activity: activity,
                                                               showSettings: showSettings))
        if !panel.setFrameUsingName("LifeClockCard") { panel.center() }
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
        let wallpaper = preferences.wallpaperMode
        let switchedModes = wallpaper != wallpaperActive
        if switchedModes {
            wallpaperActive = wallpaper
            // Swap the presentation view and autosave slot only when the mode
            // changes; the free card keeps its controls, the wallpaper view
            // fills the screen chrome-free. A separate autosave name keeps the
            // free card's remembered position intact during wallpaper runs.
            panel.contentView = NSHostingView(
                rootView: wallpaper
                    ? AnyView(WallpaperAgeView(store: store, activity: activity))
                    : AnyView(AgeCardView(store: store, activity: activity,
                                          showSettings: showSettings)))
            panel.setFrameAutosaveName(wallpaper ? "LifeClockWallpaper" : "LifeClockCard")
        }
        if wallpaper {
            panel.minSize = .zero
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            refreshWallpaperFrame()
        } else {
            let cardSize = AgeCardView.size(for: preferences.cardFormat,
                                            subsecondUnits: preferences.subsecondUnits)
            panel.minSize = cardSize
            panel.hasShadow = true
            panel.ignoresMouseEvents = false
            if panel.frame.width < cardSize.width || panel.frame.height < cardSize.height {
                let top = panel.frame.maxY
                let width = max(panel.frame.width, cardSize.width)
                let height = max(panel.frame.height, cardSize.height)
                panel.setFrame(NSRect(x: panel.frame.minX, y: top - height,
                                      width: width, height: height), display: true)
            }
            panel.level = preferences.alwaysOnTop ? .floating
                : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            panel.collectionBehavior = preferences.alwaysOnTop
                ? [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                : [.canJoinAllSpaces, .stationary, .ignoresCycle]
            if switchedModes { keepOnScreen() }
        }
        if preferences.cardEnabled && preferences.birth != nil { show() } else { panel.orderOut(nil) }
        updateActivity()
    }

    func show() {
        keepOnScreen()
        panel.orderFrontRegardless()
        updateActivity()
    }

    func windowDidMove(_ notification: Notification) {
        panel.saveFrame(usingName: panel.frameAutosaveName)
    }

    private func keepOnScreen() {
        if wallpaperActive { refreshWallpaperFrame(); return }
        guard !NSScreen.screens.contains(where: { $0.visibleFrame.contains(panel.frame) }),
              let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        let origin = NSPoint(x: max(area.minX, min(panel.frame.minX, area.maxX - panel.frame.width)),
                             y: max(area.minY, min(panel.frame.minY, area.maxY - panel.frame.height)))
        panel.setFrameOrigin(origin)
    }

    // Wallpaper mode covers the whole screen frame — the full wallpaper area,
    // including what sits behind the menu bar and the Dock.
    private func refreshWallpaperFrame() {
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        panel.setFrame(screen.frame, display: true)
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
