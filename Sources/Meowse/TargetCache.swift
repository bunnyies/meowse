import Darwin

/// Whether the scroll target is the Dock process, which draws the Dock,
/// Launchpad and Mission Control: system UI that pages or switches instead of
/// scrolling a document, so it gets the wheel unsmoothed. The lookup
/// (`proc_pidpath`, safe on any thread, no allocation) runs only when the
/// target process changes.
struct TargetCache {
    private var pid: pid_t = -1
    private var dock = false

    mutating func isDock(_ target: pid_t) -> Bool {
        if target != pid {
            pid = target
            dock = Self.lookUpDock(target)
        }
        return dock
    }

    private static func lookUpDock(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        let size = Int(4 * MAXPATHLEN)  // PROC_PIDPATHINFO_MAXSIZE
        return withUnsafeTemporaryAllocation(of: CChar.self, capacity: size) { buf in
            guard let base = buf.baseAddress, proc_pidpath(pid, base, UInt32(size)) > 0 else { return false }
            return strcmp(base, "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock") == 0
        }
    }
}
