import AppKit
import SwiftUI

@MainActor
final class BirthdayCoordinator {
    private let store: PreferencesStore
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private var celebration: NSPanel?
    private var dismissal: DispatchWorkItem?
    private var awake = true
    private var displayAwake = true
    private var sessionActive = true

    init(store: PreferencesStore) { self.store = store }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in
            self?.awake = false; self?.dismiss()
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            self?.awake = true; self?.check()
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.displayAwake = false; self?.dismiss()
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.displayAwake = true; self?.check()
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            self?.sessionActive = false; self?.dismiss()
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.sessionActive = true; self?.check()
        }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.sessionActive = false; self?.dismiss()
        }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.sessionActive = true; self?.check()
        }
        observe(.default, .NSCalendarDayChanged) { [weak self] in self?.check() }
        observe(.default, .NSSystemTimeZoneDidChange) { [weak self] in self?.check() }
        // Rechecks clock changes and sessions whose unlock notification precedes the CG session update.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        check()
    }

    func check() {
        guard awake, displayAwake, sessionActive,
              let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              session["CGSSessionScreenIsLocked"] as? Bool != true,
              let birth = store.preferences.birth,
              let key = BirthdayPolicy.celebrationKey(birth: birth, now: Date(), timeZone: .current,
                  lastCelebratedDay: store.lastCelebratedDay, sessionActive: true) else { return }
        showCelebration()
        store.lastCelebratedDay = key
    }

    private func showCelebration() {
        dismiss()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
                            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Happy birthday"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: BirthdayCelebrationView { [weak self] in self?.dismiss() })
        panel.center()
        panel.orderFrontRegardless()
        celebration = panel
        let dismissal = DispatchWorkItem { [weak self] in self?.dismiss() }
        self.dismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: dismissal)
    }

    private func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        celebration?.close()
        celebration = nil
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, token))
    }

    deinit {
        timer?.invalidate()
        dismissal?.cancel()
        observers.forEach { $0.0.removeObserver($0.1) }
    }
}

private struct BirthdayCelebrationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var falling = false
    let dismiss: () -> Void
    private let colours: [Color] = [.orange, .pink, .blue, .mint, .purple]

    var body: some View {
        ZStack {
            VStack(spacing: 14) {
                Image(systemName: "birthday.cake.fill").font(.system(size: 36)).foregroundStyle(.orange)
                Text("Happy birthday!").font(.largeTitle.bold())
                Text("Another year of being you.\nMake this one yours.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Thank you", action: dismiss).buttonStyle(.borderedProminent)
            }
            if !reduceMotion {
                GeometryReader { geometry in
                    ForEach(0..<24) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colours[index % colours.count])
                            .frame(width: 6, height: 11)
                            .rotationEffect(.degrees(falling ? Double(index * 41) : 0))
                            .position(x: CGFloat((index * 67 + 19) % 420),
                                      y: falling ? geometry.size.height + 30 : -30 - CGFloat(index % 5) * 18)
                            .opacity(falling ? 0 : 1)
                            .animation(.easeOut(duration: 3.5).delay(Double(index % 6) * 0.12), value: falling)
                    }
                }
                .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .frame(width: 420, height: 280)
        .clipped()
        .onAppear { if !reduceMotion { falling = true } }
    }
}
