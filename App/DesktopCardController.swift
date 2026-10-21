import AppKit
import CoreGraphics
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
        // Upgrade older selections while their numeric ID still resolves.
        // If it no longer resolves, retain it until the user chooses a screen.
        if store.preferences.wallpaperDisplayUUID == nil,
           let screen = NSScreen.screens.first(where: {
               store.preferences.matchesWallpaperDisplay(id: $0.lifeClockDisplayID ?? 0,
                                                          uuid: $0.lifeClockDisplayUUID)
           }), let uuid = screen.lifeClockDisplayUUID {
            var updated = store.preferences
            updated.wallpaperDisplayUUID = uuid
            do { try store.save(updated) }
            catch { NSLog("Life Clock could not upgrade the saved display: %@", error.localizedDescription) }
        }
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
        // Hide before applying presentation changes: wallpaper layout requests a
        // full-screen redraw, which is unnecessary when switching the card off.
        guard preferences.cardEnabled && preferences.birth != nil else {
            if activity.isRunning { activity.isRunning = false }
            if panel.isVisible { panel.orderOut(nil) }
            return
        }

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
        show()
    }

    func show() {
        keepOnScreen()
        panel.orderFrontRegardless()
        updateActivity()
    }

    func resetCardSize() {
        guard !wallpaperActive else { return }
        let size = AgeCardView.size(for: store.preferences.cardFormat,
                                    subsecondUnits: store.preferences.subsecondUnits)
        let frame = NSRect(x: panel.frame.midX - size.width / 2,
                           y: panel.frame.midY - size.height / 2,
                           width: size.width, height: size.height)
        panel.setFrame(frame, display: true, animate: true)
        keepOnScreen()
        panel.saveFrame(usingName: "LifeClockCard")
    }

    func windowDidMove(_ notification: Notification) {
        panel.saveFrame(usingName: panel.frameAutosaveName)
    }

    private func keepOnScreen() {
        if wallpaperActive { refreshWallpaperFrame(); return }
        guard !NSScreen.screens.contains(where: { $0.visibleFrame.contains(panel.frame) }),
              let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        guard let frame = CardFramePolicy.fit(panel.frame, to: screen.visibleFrame,
                                               minimumSize: panel.minSize) else { return }
        panel.setFrame(frame, display: true)
        panel.saveFrame(usingName: "LifeClockCard")
    }

    // Wallpaper mode covers the whole screen frame — the full wallpaper area,
    // including what sits behind the menu bar and the Dock. The chosen display
    // wins; the primary display is both the default and the fallback when the
    // chosen display is disconnected. NSScreen.main follows the key window,
    // whereas NSScreen.screens.first is the primary display.
    private func refreshWallpaperFrame() {
        guard let screen = wallpaperScreen() else { return }
        panel.setFrame(screen.frame, display: true)
    }

    private func wallpaperScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let identities = screens.map { (id: $0.lifeClockDisplayID ?? 0, uuid: $0.lifeClockDisplayUUID) }
        if let index = store.preferences.wallpaperDisplayIndex(in: identities) {
            return screens[index]
        }
        return screens.first
    }

    private func updateActivity() {
        let running = store.preferences.cardEnabled && store.preferences.birth != nil
            && awake && displayAwake && sessionActive && panel.isVisible
            && panel.occlusionState.contains(.visible)
        if activity.isRunning != running { activity.isRunning = running }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, token))
    }

    deinit { observers.forEach { $0.0.removeObserver($0.1) } }
}
