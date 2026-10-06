/// What to do with one discrete wheel tick. The engine applies it to the event.
public struct WheelRoute: Equatable {
    /// Negate this axis's delta fields on the original event.
    public var reverseY = false
    public var reverseX = false
    /// Zero this axis on the original event (the animator owns it now).
    public var clearY = false
    public var clearX = false
    /// Distance for the animator in points, already swapped, signed and scaled.
    public var glideY = 0.0
    public var glideX = 0.0
    /// Swallow the original event instead of passing it on.
    public var swallow = false

    public var glides: Bool { glideY != 0 || glideX != 0 }
    public var editsEvent: Bool { reverseY || reverseX || clearY || clearX }
}

public enum WheelRouter {
    /// Routes one tick of `lines` per axis (the system's accelerated line count).
    @inline(__always)
    public static func route(
        lines dy: Double,
        _ dx: Double,
        flags: UInt64,
        heldButtons: UInt32,
        config c: EngineConfig,
        smoothingAllowedForTarget: Bool
    ) -> WheelRoute {
        var r = WheelRoute()

        let unsmoothed = c.unsmoothedKey.isHeld(flags: flags, heldButtons: heldButtons)
        let sideways = c.sidewaysKey.isHeld(flags: flags, heldButtons: heldButtons)
        let smoothing = c.smooth && !unsmoothed && smoothingAllowedForTarget

        // With the sideways key held, a purely vertical tick is handled as horizontal.
        let swap = sideways && dy != 0 && dx == 0
        let reverseForY = swap ? c.reverseHorizontal : c.reverseVertical
        let smoothForY = swap ? c.smoothHorizontal : c.smoothVertical

        var y = dy, x = dx
        if y != 0 && reverseForY { y = -y; r.reverseY = true }
        if x != 0 && c.reverseHorizontal { x = -x; r.reverseX = true }

        let glideY = smoothing && y != 0 && smoothForY
        let glideX = smoothing && x != 0 && c.smoothHorizontal
        guard glideY || glideX else { return r }

        let notch = c.notchDistance * (c.fasterKey.isHeld(flags: flags, heldButtons: heldButtons) ? c.fasterFactor : 1)
        let outY = glideY ? ScrollMath.distance(lines: y, notch: notch) : 0
        let outX = glideX ? ScrollMath.distance(lines: x, notch: notch) : 0
        if swap {
            r.glideY = outX
            r.glideX = outY
        } else {
            r.glideY = outY
            r.glideX = outX
        }

        let passY = y != 0 && !glideY
        let passX = x != 0 && !glideX
        if passY || passX {
            // One axis glides; the other passes through on the original event.
            r.clearY = glideY
            r.clearX = glideX
            if glideY { r.reverseY = false }
            if glideX { r.reverseX = false }
        } else {
            r.swallow = true
        }
        return r
    }
}
