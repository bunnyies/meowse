import AppKit

// A second instance would add a second event tap and smooth every scroll twice.
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id)
       .contains(where: { $0.processIdentifier != getpid() }) {
    NSLog("Meowse: another instance is already running; exiting")
    exit(0)
}

// Writing to a Settings window that just closed must fail quietly, not end Meowse.
signal(SIGPIPE, SIG_IGN)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
