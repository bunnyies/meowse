import AppKit
import MeowseCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let store = SettingsStore.shared
    private let engine = Engine.shared
    private let awake = AwakeController.shared
    private let updater = Updater.shared
    private lazy var statusMenu = StatusMenuController(store: store, awake: awake, updater: updater)
    private var settingsWindow: SettingsWindowController?
    private var trusted = false
    /// Exists only while Accessibility access is missing.
    private var trustWatch: DispatchSourceTimer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First, so a copy that's moving never installs its tap or asks for access.
        if AppMover.offerMove() { return }
        engine.start()
        engine.apply(EngineConfig(store.settings))
        rebuildScreens()

        store.onChange = { [weak self] new, old in self?.settingsChanged(new, old) }
        awake.onChange = { [weak self] in self?.statusMenu.updateIcon() }
        statusMenu.openSettings = { [weak self] in self?.showSettings() }
        statusMenu.openUpdates = { [weak self] in
            guard let self else { return }
            if self.updater.availableVersion == nil { self.updater.check(userInitiated: true) }
            self.showSettings(tab: .updates)
        }
        statusMenu.requestPermission = { [weak self] in self?.requestPermission() }
        statusMenu.willOpen = { [weak self] in self?.refreshTrust(prompt: false) }
        statusMenu.retryEngine = { [weak self] in self?.engine.revalidate() }
        engine.onStatusChange = { [weak self] status in
            self?.store.engineStatus = status
            self?.statusMenu.engineStatus = status
            if status != .active { self?.store.scrollDevice = nil }
        }
        engine.onDeviceChange = { [weak self] device in self?.store.scrollDevice = device }
        statusMenu.setVisible(store.settings.showMenuBarIcon)

        observeSystem()
        awake.observeSystem()
        updater.setAutomaticChecks(store.settings.checkForUpdates)
        refreshTrust(prompt: true)
    }

    /// Opening the app again (e.g. with the menu bar icon hidden) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func settingsChanged(_ new: Settings, _ old: Settings) {
        let config = EngineConfig(new)
        if config != EngineConfig(old) { engine.apply(config) }
        if new.showMenuBarIcon != old.showMenuBarIcon { statusMenu.setVisible(new.showMenuBarIcon) }
        if new.enabled != old.enabled { statusMenu.updateIcon() }

        // Running sessions pick up preference changes.
        if new.awakeAllowDisplaySleep != old.awakeAllowDisplaySleep, awake.isAwake {
            let remaining = awake.awakeUntil == nil ? 0 : max(1, awake.awakeRemaining ?? 0)
            awake.startAwake(duration: remaining, allowDisplaySleep: new.awakeAllowDisplaySleep)
        }
        if new.wiggleInterval != old.wiggleInterval, awake.isWiggling {
            awake.startWiggle(interval: new.wiggleInterval)
        }
        if new.checkForUpdates != old.checkForUpdates {
            updater.setAutomaticChecks(new.checkForUpdates)
        }
    }

    // MARK: - System events

    private func observeSystem() {
        // Posted when the Accessibility list changes.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil, queue: .main
        ) { [weak self] _ in
            // The permission database updates shortly after the notification.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.refreshTrust(prompt: false) }
        }

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshTrust(prompt: false)
                self?.engine.revalidate()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuildScreens()
        }
    }

    private func refreshTrust(prompt: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let now = AXIsProcessTrustedWithOptions(options)
        updateTrustWatch(trusted: now)
        guard now != trusted || prompt else { return }
        NSLog("Meowse: accessibility trusted = %d", now ? 1 : 0)
        trusted = now
        engine.setTrusted(now)
        statusMenu.trusted = now
        store.accessibilityTrusted = now
    }

    /// The accessibility notification isn't delivered on every macOS release,
    /// so while access is missing (and only then) recheck every 2 s.
    private func updateTrustWatch(trusted: Bool) {
        if trusted {
            trustWatch?.cancel()
            trustWatch = nil
        } else if trustWatch == nil {
            let t = DispatchSource.makeTimerSource(queue: .main)
            t.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(500))
            t.setEventHandler { [weak self] in self?.refreshTrust(prompt: false) }
            t.resume()
            trustWatch = t
        }
    }

    private func requestPermission() {
        refreshTrust(prompt: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// One paused display link per screen; the engine runs the one under the
    /// cursor while a glide is in flight.
    private func rebuildScreens() {
        let links: [Engine.ScreenLink] = NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }
            let link = screen.displayLink(target: engine, selector: #selector(Engine.tick(_:)))
            let maxHz = Float(max(screen.maximumFramesPerSecond, 60))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: maxHz, preferred: maxHz)
            link.isPaused = true
            return Engine.ScreenLink(bounds: CGDisplayBounds(id), link: link)
        }
        engine.setScreens(links)
    }

    // MARK: - Settings window

    private func showSettings(tab: SettingsWindowController.Tab? = nil) {
        if settingsWindow == nil {
            let controller = SettingsWindowController(store: store, awake: awake, updater: updater) { [weak self] in
                self?.requestPermission()
            }
            controller.onClose = { [weak self] in
                // Release the window and its views.
                DispatchQueue.main.async { self?.settingsWindow = nil }
            }
            settingsWindow = controller
        }
        store.refreshLaunchAtLogin()
        refreshTrust(prompt: false)
        if let tab { settingsWindow?.select(tab) }
        settingsWindow?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
        awake.stopAwake()
    }
}
