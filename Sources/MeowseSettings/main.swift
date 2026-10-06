import AppKit
import MeowseCore

// Writing to Meowse after it quit must end quietly, not with SIGPIPE.
signal(SIGPIPE, SIG_IGN)

/// Shows the window when Meowse asks and exits when it closes.
final class SettingsAppDelegate: NSObject, NSApplicationDelegate {

    private let remote = Remote()
    private var window: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Connection.shared.onMessage = { [weak self] in self?.handle($0) }
        Connection.shared.start()
    }

    private func handle(_ message: ToSettings) {
        switch message {
        case .state(let state):
            remote.apply(state)
        case .show(let tab):
            if window == nil {
                let controller = SettingsWindowController(store: remote.store, awake: remote.awake, updater: remote.updater) {
                    Connection.shared.send(.requestPermission)
                }
                controller.onClose = { NSApp.terminate(nil) }
                window = controller
            }
            if let tab { window?.select(tab) }
            window?.show()
        }
    }
}

let app = NSApplication.shared
let delegate = SettingsAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
