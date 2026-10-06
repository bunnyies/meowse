import AppKit
import SwiftUI

/// Settings window with toolbar tabs. Created on demand and released on close.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    enum Tab: Int { case general, scrolling, hotkeys, awake, updates }

    var onClose: (() -> Void)?
    private let tabs = FittingTabViewController()

    init(store: SettingsStore, awake: AwakeController, updater: Updater, requestPermission: @escaping () -> Void) {
        let tabs = self.tabs
        tabs.tabStyle = .toolbar

        func add<V: View>(_ title: String, _ symbol: String, _ view: V) {
            let host = NSHostingController(rootView: view)
            host.sizingOptions = [.preferredContentSize]
            host.title = title  // becomes the window title
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        add("General", "gearshape", GeneralTab(store: store, requestPermission: requestPermission))
        add("Scrolling", "scroll", ScrollingTab(store: store))
        add("Hotkeys", "keyboard", HotkeysTab(store: store))
        add("Awake", "cup.and.saucer", AwakeTab(store: store, awake: awake))
        add("Updates", "arrow.down.circle", UpdatesTab(store: store, updater: updater))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func select(_ tab: Tab) {
        tabs.selectedTabViewItemIndex = tab.rawValue
    }

    func show() {
        if window?.isVisible == false { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

/// Resizes the window to the selected tab's SwiftUI content, anchored at the top.
private final class FittingTabViewController: NSTabViewController {

    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        fitWindow()
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        if viewController === tabViewItems[selectedTabViewItemIndex].viewController {
            fitWindow()
        }
    }

    private func fitWindow() {
        guard let window = view.window,
              let size = tabViewItems[selectedTabViewItemIndex].viewController?.preferredContentSize,
              size.width > 0, size.height > 0 else { return }
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var frame = window.frame
        frame.origin.y += frame.height - target.height
        frame.size = target.size
        window.setFrame(frame, display: true, animate: window.isVisible)
    }
}
