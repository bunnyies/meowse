import Foundation

/// Keep Awake and Wiggle Cursor helpers.
public enum Awake {

    /// Session lengths offered in the UI; 0 means until turned off.
    public static let durations: [TimeInterval] = [0, 15 * 60, 30 * 60, 3600, 2 * 3600, 4 * 3600, 8 * 3600]

    /// Idle intervals after which the cursor is wiggled.
    public static let wiggleIntervals: [TimeInterval] = [30, 60, 120, 240]

    /// What the wiggle timer does when it fires: wiggle only if the user has
    /// been idle for the interval, and re-arm for the time left until they
    /// would be. An active user costs at most one wakeup per interval.
    public static func wigglePlan(idle: TimeInterval, interval: TimeInterval) -> (wiggleNow: Bool, nextCheck: TimeInterval) {
        // 5% slack so timer leeway can't skip a cycle.
        if idle >= interval * 0.95 {
            return (true, interval)
        }
        return (false, max(1, interval - idle))
    }

    /// "Until Turned Off", "15 Minutes", "1 Hour", "2 Hours".
    public static func durationLabel(_ seconds: TimeInterval) -> String {
        if seconds <= 0 { return "Until Turned Off" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return minutes == 1 ? "1 Minute" : "\(minutes) Minutes" }
        let hours = minutes / 60, rest = minutes % 60
        let h = hours == 1 ? "1 Hour" : "\(hours) Hours"
        return rest == 0 ? h : "\(h) \(rest) Minutes"
    }

    /// "30 Seconds", "1 Minute", "4 Minutes".
    public static func intervalLabel(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds)) Seconds" }
        return durationLabel(seconds)
    }

    /// Compact countdown for menu subtitles: "52 min left", "1 hr 5 min left".
    public static func remainingLabel(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes <= 1 { return "Less than a minute left" }
        if minutes < 60 { return "\(minutes) min left" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) hr left" : "\(h) hr \(m) min left"
    }
}
