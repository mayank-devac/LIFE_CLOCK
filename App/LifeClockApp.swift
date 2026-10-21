import AppKit
import Combine
import SwiftUI
import WidgetKit

@main
struct LifeClockApp: App {
    @NSApplicationDelegateAdaptor(LifeClockDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Life Clock", systemImage: "hourglass") {
            Button("Show Life Clock") { delegate.showCard() }
            Button("Settings…") { delegate.showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit Life Clock") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

@MainActor
final class LifeClockDelegate: NSObject, NSApplicationDelegate {
    let store = PreferencesStore()
    private var card: DesktopCardController?
    private var birthday: BirthdayCoordinator?
    private var settingsWindow: NSWindow?
    private var preferencesSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Refresh cached entries after installing a newer configurable widget build.
        WidgetCenter.shared.reloadTimelines(ofKind: "LifeClockWidget")
        let card = DesktopCardController(store: store) { [weak self] in self?.showSettings() }
        self.card = card
        let birthday = BirthdayCoordinator(store: store)
        self.birthday = birthday
        preferencesSubscription = store.$preferences.sink { [weak self] preferences in
            // @Published emits before assignment; update consumers after the save finishes.
            DispatchQueue.main.async {
                self?.card?.apply(preferences)
                self?.birthday?.check()
            }
        }
        card.apply(store.preferences)
        birthday.start()
        if store.preferences.birth == nil || store.readWarning != nil { showSettings() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if store.preferences.birth == nil { showSettings() } else { showCard() }
        return true
    }

    func showCard() {
        guard store.preferences.birth != nil else { showSettings(); return }
        if !store.preferences.cardEnabled {
            var preferences = store.preferences
            preferences.cardEnabled = true
            do { try store.save(preferences) } catch { showSettings(); return }
        }
        card?.show()
    }

    func showSettings() {
        if settingsWindow?.isVisible != true {
            let view = SetupAndSettingsView(store: store, onResetCardSize: { [weak card] in
                card?.resetCardSize()
            }) {
                // Keep the settings window open until the user chooses Close.
            }
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: SetupAndSettingsView.size),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Life Clock"
            window.contentMinSize = NSSize(width: SetupAndSettingsView.size.width,
                                          height: min(600, SetupAndSettingsView.size.height))
            window.contentMaxSize = NSSize(width: SetupAndSettingsView.size.width,
                                          height: .greatestFiniteMagnitude)
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
