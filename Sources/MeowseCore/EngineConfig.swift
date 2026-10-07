import CoreGraphics
import Foundation

/// Settings resolved for the engine thread. Built on the main thread and
/// handed over as a value, so the event path reads plain stored fields.
public struct EngineConfig: Equatable, Sendable {
    public var smooth: Bool
    public var smoothVertical: Bool
    public var smoothHorizontal: Bool
    public var trackpadPhases: Bool
    public var reverseVertical: Bool
    public var reverseHorizontal: Bool
    public var notchDistance: Double
    /// Seconds for a glide's remaining distance to shrink by a factor of e.
    public var decay: Double
    public var fasterKey: Hotkey
    public var sidewaysKey: Hotkey
    public var unsmoothedKey: Hotkey
    public var fasterFactor: Double
    public var stopOnClick: Bool

    /// Events the tap must receive; 0 means no tap is needed. Clicks that
    /// stop a glide come from a separate tap that's on only mid-glide.
    public let eventMask: CGEventMask

    public init(_ s: Settings) {
        let active = s.enabled
        smooth = active && s.smooth && (s.smoothVertical || s.smoothHorizontal)
        smoothVertical = s.smoothVertical
        smoothHorizontal = s.smoothHorizontal
        trackpadPhases = s.trackpadPhases
        reverseVertical = active && s.reverseVertical
        reverseHorizontal = active && s.reverseHorizontal
        notchDistance = max(1, s.notchDistance)
        // 99% of the distance is covered after ln(100) time constants.
        decay = max(0.01, s.glideTime) / log(100)
        fasterKey = s.fasterKey
        sidewaysKey = s.sidewaysKey
        unsmoothedKey = s.unsmoothedKey
        fasterFactor = max(1, s.fasterFactor)
        stopOnClick = s.stopOnClick
        let effectiveHotkeys: [Hotkey]
        if smooth {
            effectiveHotkeys = [fasterFactor > 1 ? s.fasterKey : .none, s.sidewaysKey, s.unsmoothedKey]
        } else {
            effectiveHotkeys = reverseVertical != reverseHorizontal ? [s.sidewaysKey] : []
        }
        eventMask = EngineConfig.mask(
            smooth: smooth,
            reverse: reverseVertical || reverseHorizontal,
            hotkeys: effectiveHotkeys
        )
    }

    /// Whether a click should stop a glide in flight.
    public var stopsOnClick: Bool { smooth && stopOnClick }

    /// The smallest mask that serves the configuration. Keyboard events are
    /// never needed: modifier hotkeys come from the wheel event's flags.
    static func mask(smooth: Bool, reverse: Bool, hotkeys: [Hotkey]) -> CGEventMask {
        guard smooth || reverse else { return 0 }
        func bit(_ t: CGEventType) -> CGEventMask { 1 << CGEventMask(t.rawValue) }
        var mask = bit(.scrollWheel)
        if hotkeys.contains(where: { $0.needsMouseButtonEvents }) {
            mask |= bit(.otherMouseDown) | bit(.otherMouseUp)
        }
        return mask
    }
}
