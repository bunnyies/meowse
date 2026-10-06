import AppKit
import MeowseCore

/// The menu bar item. Items are built once and refreshed in `menuNeedsUpdate`,
/// so nothing runs while the menu is closed.
final class StatusMenuController: NSObject, NSMenuDelegate {

    private let store: SettingsStore
    private let awake: AwakeController
    private let updater: Updater
    private var statusItem: NSStatusItem?

    var openSettings: () -> Void = {}
    var openUpdates: () -> Void = {}
    var requestPermission: () -> Void = {}
    var retryEngine: () -> Void = {}
    /// Runs when the menu opens, before items are refreshed.
    var willOpen: () -> Void = {}
    var trusted = false { didSet { updateIcon() } }
    var engineStatus: Engine.TapStatus = .off { didSet { updateIcon() } }

    private lazy var plainIcon = Self.makeIcon(badged: false)
    private lazy var badgedIcon = Self.makeIcon(badged: true)

    private let menu = NSMenu()
    private var permissionItem: NSMenuItem!
    private var engineFailedItem: NSMenuItem!
    private var permissionSeparator: NSMenuItem!
    private var smoothItem: NSMenuItem!
    private var reverseItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var awakeItem: NSMenuItem!
    private var durationItems: [NSMenuItem] = []
    private var allowDisplaySleepItem: NSMenuItem!
    private var wiggleItem: NSMenuItem!
    private var intervalItems: [NSMenuItem] = []
    private var updateItem: NSMenuItem!

    init(store: SettingsStore, awake: AwakeController, updater: Updater) {
        self.store = store
        self.awake = awake
        self.updater = updater
        super.init()
        buildMenu()
    }

    // MARK: - Visibility

    func setVisible(_ visible: Bool) {
        if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.menu = menu
            item.button?.toolTip = "Meowse"
            statusItem = item
            updateIcon()
        } else if !visible, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// Badged while Keep Awake or Wiggle is on; dimmed while scrolling is unavailable.
    func updateIcon() {
        guard let button = statusItem?.button else { return }
        button.image = (awake.isAwake || awake.isWiggling) ? badgedIcon : plainIcon
        button.appearsDisabled = !trusted || !store.settings.enabled || engineStatus == .failed
    }

    // MARK: - Building

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        permissionItem = item("Allow Accessibility Access…", "exclamationmark.triangle.fill", #selector(permissionClicked))
        engineFailedItem = item("Scrolling Didn’t Start: Retry", "exclamationmark.triangle.fill", #selector(retryClicked))
        permissionSeparator = .separator()
        menu.addItem(permissionItem)
        menu.addItem(engineFailedItem)
        menu.addItem(permissionSeparator)

        menu.addItem(.sectionHeader(title: "Scrolling"))
        smoothItem = item("Smooth Scrolling", "scroll", #selector(toggleSmooth))
        reverseItem = item("Reverse Direction", "arrow.up.arrow.down", #selector(toggleReverse))
        pauseItem = item("Pause Scrolling", "pause.circle", #selector(togglePause))
        [smoothItem, reverseItem, pauseItem].forEach(menu.addItem)

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Awake"))

        awakeItem = item("Keep Awake", "cup.and.saucer", #selector(toggleAwake))
        menu.addItem(awakeItem)
        let awakeFor = item("Keep Awake For", "timer", nil)
        let durations = NSMenu()
        durations.autoenablesItems = false
        for d in Awake.durations {
            let i = item(Awake.durationLabel(d), nil, #selector(pickDuration(_:)))
            i.representedObject = d
            durationItems.append(i)
            durations.addItem(i)
        }
        durations.addItem(.separator())
        allowDisplaySleepItem = item("Allow Display to Sleep", nil, #selector(toggleAllowDisplaySleep))
        durations.addItem(allowDisplaySleepItem)
        awakeFor.submenu = durations
        menu.addItem(awakeFor)

        wiggleItem = item("Wiggle Cursor", "cursorarrow.motionlines", #selector(toggleWiggle))
        menu.addItem(wiggleItem)
        let wiggleEvery = item("Wiggle When Idle For", "hourglass", nil)
        let intervals = NSMenu()
        intervals.autoenablesItems = false
        for s in Awake.wiggleIntervals {
            let i = item(Awake.intervalLabel(s), nil, #selector(pickInterval(_:)))
            i.representedObject = s
            intervalItems.append(i)
            intervals.addItem(i)
        }
        wiggleEvery.submenu = intervals
        menu.addItem(wiggleEvery)

        menu.addItem(.separator())
        menu.addItem(item("Settings…", "gearshape", #selector(settingsClicked), key: ","))
        updateItem = item("Check for Updates…", "arrow.down.circle", #selector(updatesClicked))
        menu.addItem(updateItem)
        let quit = NSMenuItem(title: "Quit Meowse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quit)
    }

    private func item(_ title: String, _ symbol: String?, _ action: Selector?, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        if let symbol {
            i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return i
    }

    // MARK: - Refresh

    func menuNeedsUpdate(_ menu: NSMenu) {
        willOpen()
        let s = store.settings

        let engineFailed = trusted && engineStatus == .failed
        permissionItem.isHidden = trusted
        engineFailedItem.isHidden = !engineFailed
        permissionSeparator.isHidden = trusted && !engineFailed

        smoothItem.state = s.smooth ? .on : .off
        reverseItem.state = (s.reverseVertical || s.reverseHorizontal) ? .on : .off
        smoothItem.isEnabled = s.enabled
        reverseItem.isEnabled = s.enabled
        pauseItem.title = s.enabled ? "Pause Scrolling" : "Resume Scrolling"
        pauseItem.image = NSImage(systemSymbolName: s.enabled ? "pause.circle" : "play.circle", accessibilityDescription: nil)

        awakeItem.state = awake.isAwake ? .on : .off
        awakeItem.image = NSImage(systemSymbolName: awake.isAwake ? "cup.and.heat.waves" : "cup.and.saucer", accessibilityDescription: nil)
        let awakeDetail: String
        if awake.isAwake {
            awakeDetail = awake.awakeRemaining.map(Awake.remainingLabel) ?? "Until turned off"
        } else {
            awakeDetail = s.awakeDuration > 0 ? "For \(Awake.durationLabel(s.awakeDuration).lowercased())" : "Until turned off"
        }
        setSubtitle(awakeItem, base: "Keep Awake", awakeDetail + (s.awakeAllowDisplaySleep ? " · display may sleep" : ""))
        for i in durationItems {
            i.state = (i.representedObject as? TimeInterval) == s.awakeDuration ? .on : .off
        }
        allowDisplaySleepItem.state = s.awakeAllowDisplaySleep ? .on : .off

        if let version = updater.availableVersion {
            updateItem.title = "Update to Meowse \(version)…"
            updateItem.badge = NSMenuItemBadge(string: "New")
        } else {
            updateItem.title = "Check for Updates…"
            updateItem.badge = nil
        }

        wiggleItem.state = awake.isWiggling ? .on : .off
        setSubtitle(wiggleItem, base: "Wiggle Cursor", "When idle for \(Awake.intervalLabel(s.wiggleInterval).lowercased())")
        for i in intervalItems {
            i.state = (i.representedObject as? TimeInterval) == s.wiggleInterval ? .on : .off
        }
    }

    private func setSubtitle(_ item: NSMenuItem, base: String, _ text: String?) {
        if #available(macOS 14.4, *) {
            item.title = base
            item.subtitle = text
        } else {
            item.title = text.map { "\(base) (\($0))" } ?? base
        }
    }

    // MARK: - Actions

    @objc private func permissionClicked() { requestPermission() }
    @objc private func retryClicked() { retryEngine() }
    @objc private func settingsClicked() { openSettings() }
    @objc private func updatesClicked() { openUpdates() }
    @objc private func toggleSmooth() { store.settings.smooth.toggle() }
    @objc private func togglePause() { store.settings.enabled.toggle() }

    @objc private func toggleReverse() {
        let on = !(store.settings.reverseVertical || store.settings.reverseHorizontal)
        store.settings.reverseVertical = on
        store.settings.reverseHorizontal = on
    }

    @objc private func toggleAwake() {
        if awake.isAwake {
            awake.stopAwake()
        } else {
            awake.startAwake(duration: store.settings.awakeDuration, allowDisplaySleep: store.settings.awakeAllowDisplaySleep)
        }
    }

    @objc private func pickDuration(_ sender: NSMenuItem) {
        guard let d = sender.representedObject as? TimeInterval else { return }
        store.settings.awakeDuration = d
        awake.startAwake(duration: d, allowDisplaySleep: store.settings.awakeAllowDisplaySleep)
    }

    @objc private func toggleAllowDisplaySleep() {
        store.settings.awakeAllowDisplaySleep.toggle()  // AppDelegate restarts a running session
    }

    @objc private func toggleWiggle() {
        if awake.isWiggling {
            awake.stopWiggle()
        } else {
            awake.startWiggle(interval: store.settings.wiggleInterval)
        }
    }

    @objc private func pickInterval(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? TimeInterval else { return }
        store.settings.wiggleInterval = s
        awake.startWiggle(interval: s)
    }

    // MARK: - Icon

    /// A mouse with cat ears, from the website's 24-unit outline scaled to the
    /// 16 pt height of a menu bar symbol. Both variants share one size so the
    /// glyph stays put when the badge comes and goes.
    static func makeIcon(badged: Bool) -> NSImage {
        let glyph = NSBezierPath(roundedRect: NSRect(x: 6.5, y: 4.5, width: 11, height: 16), xRadius: 5.5, yRadius: 5.5)
        for ear in [[(8.5, 5.5), (7.0, 2.5), (10.0, 4.5)], [(15.5, 5.5), (17.0, 2.5), (14.0, 4.5)]] {
            glyph.move(to: NSPoint(x: ear[0].0, y: ear[0].1))
            glyph.line(to: NSPoint(x: ear[1].0, y: ear[1].1))
            glyph.line(to: NSPoint(x: ear[2].0, y: ear[2].1))
        }
        glyph.move(to: NSPoint(x: 12, y: 4.5))
        glyph.line(to: NSPoint(x: 12, y: 9.5))
        glyph.transform(using: AffineTransform(scale: 0.8))
        glyph.transform(using: AffineTransform(translationByX: 0.4, byY: -0.2))
        glyph.lineWidth = 1.6 * 0.8
        glyph.lineCapStyle = .round
        glyph.lineJoinStyle = .round

        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: true) { _ in
            NSColor.black.set()
            glyph.stroke()
            if badged {
                let dot = NSRect(x: 15.4, y: 0.4, width: 4.4, height: 4.4)
                // Clear a ring around the dot so it stands apart from the ear.
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: dot.insetBy(dx: -1.1, dy: -1.1)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = badged ? "Meowse (keeping awake)" : "Meowse"
        return image
    }
}
