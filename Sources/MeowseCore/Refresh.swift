import Foundation

/// When to restart the app so the system takes back memory it never returns
/// to one that keeps running.
///
/// Every display change (a monitor plugged in or out, mirroring, a new
/// resolution) leaves colour tables, window contexts and freed pages behind in
/// any menu bar app, Meowse's code or not, and they add up over days. Only a
/// new process gives them back.
public enum Refresh {

    /// Growth over the launch footprint that makes a restart worth it. Opening
    /// the menu costs well under this, so a copy that only did that never restarts.
    public static let growth = 2

    /// A copy that started recently is left alone, so a restart can't repeat.
    public static let minimumUptime: TimeInterval = 3600

    /// How long the display must stay asleep first. A Mac on its way to sleep
    /// would only finish the restart once it woke.
    public static let settleDelay: TimeInterval = 10

    /// `busy` is anything a restart would cut short: a Keep Awake or Wiggle
    /// session, an open Settings window, an update being installed.
    public static func isDue(footprint: Int, atLaunch: Int, uptime: TimeInterval, busy: Bool) -> Bool {
        atLaunch > 0 && !busy && uptime >= minimumUptime && footprint >= growth * atLaunch
    }
}
