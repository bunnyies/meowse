import Foundation

/// Smooth-scroll integrator and trackpad phase machine.
///
/// Scalar state only (no allocation, no locks); owned by the engine thread,
/// which both feeds input and steps frames.
///
/// The distance still owed shrinks exponentially with time constant `decay`,
/// and the speed that produces follows it through a short `rise`, so a notch
/// moves the page on the next frame and a run of notches never jerks the
/// speed. Both are real-time constants, so a glide is the same at any
/// refresh rate.
///
/// A scroll event's point delta holds whole points, so frames carry whole
/// points: the fraction stays behind for the next frame instead of being
/// truncated away. Every posted frame costs the target app an event and
/// usually a redraw, and none moves by zero. The glide ends once less than
/// `settleThreshold` is owed, and the remainder goes out in the final frame,
/// so each glide lands within half a point of its distance at any frame rate.
public struct ScrollAnimator {

    public enum State: UInt8 { case idle, tracking, momentum }

    /// A frame to post. Marker frames carry no motion and only close a phase.
    public struct Frame: Equatable {
        public var dy: Double
        public var dx: Double
        public var scrollPhase: Double
        public var momentumPhase: Double
        public var isMarker: Bool
        /// Last frame of the gesture.
        public var isFinal: Bool
    }

    /// Raw values for kCGScrollWheelEventScrollPhase / MomentumPhase.
    public enum PhaseValue {
        public static let began = 1.0
        public static let changed = 2.0
        public static let ended = 4.0
        public static let momentumBegan = 1.0
        public static let momentumContinue = 2.0
        public static let momentumEnded = 3.0
    }

    /// Seconds for the speed to build up after a notch: one 60 Hz frame.
    public static let rise = 1.0 / 60

    /// Seconds for the remaining distance to shrink by a factor of e.
    public var decay: Double { didSet { cachedDt = -1 } }
    /// Pause in wheel input after which the glide counts as momentum. A
    /// spinning wheel ticks faster than this; separate flicks are slower.
    public var momentumAfter: Double = 0.1
    /// Owed distance below which the glide finishes.
    public var settleThreshold: Double = 1.0

    public private(set) var state: State = .idle
    public var isActive: Bool { state != .idle }

    // Per axis: rem = not yet integrated, speed = points per second,
    // carry = integrated but not yet a whole point, owed = input not yet posted,
    // dir = sign of the last input.
    private var remY = 0.0, remX = 0.0
    private var speedY = 0.0, speedX = 0.0
    private var carryY = 0.0, carryX = 0.0
    private var owedY = 0.0, owedX = 0.0
    private var dirY = 0.0, dirX = 0.0
    private var lastInputTime = 0.0
    private var beginPending = false

    // Recomputed only when the frame interval changes.
    private var cachedDt = -1.0
    private var remainingFactor = 0.0
    private var velocityFactor = 0.0
    private var transfer = 0.0

    public init(decay: Double = EngineConfig(Settings()).decay) {
        self.decay = decay
    }

    /// Adds one wheel tick's distance in points, already scaled and direction-corrected.
    public mutating func input(dy: Double, dx: Double, now: Double, emit: (Frame) -> Void) {
        if state == .momentum {
            // A new tick interrupts the fling: close momentum, then track again.
            emit(Frame(dy: 0, dx: 0, scrollPhase: 0, momentumPhase: PhaseValue.momentumEnded, isMarker: true, isFinal: false))
            state = .idle
        }
        Self.accumulate(dy, rem: &remY, speed: &speedY, carry: &carryY, owed: &owedY, dir: &dirY)
        Self.accumulate(dx, rem: &remX, speed: &speedX, carry: &carryX, owed: &owedX, dir: &dirX)
        if state == .idle {
            state = .tracking
            beginPending = true
        }
        lastInputTime = now
    }

    /// Advances one display frame of `dt` seconds.
    public mutating func step(now: Double, dt: Double, emit: (Frame) -> Void) {
        guard state != .idle else { return }

        guard dt.isFinite, dt > 0 else { return }
        if dt != cachedDt {
            let d = max(decay, 0.000001)
            remainingFactor = exp(-dt / d)
            velocityFactor = exp(-dt / Self.rise)
            let difference = d - Self.rise
            transfer = abs(difference) < 1e-10
                ? remainingFactor * dt / (d * Self.rise)
                : (remainingFactor - velocityFactor) / difference
            cachedDt = dt
        }

        integrate(rem: &remY, speed: &speedY, carry: &carryY)
        integrate(rem: &remX, speed: &speedX, carry: &carryX)
        let exhausted = abs(remY) + abs(speedY * Self.rise) < 1e-9
            && abs(remX) + abs(speedX * Self.rise) < 1e-9

        // Under a point left: deliver it, rounded, and close the gesture.
        if (abs(owedY) < settleThreshold && abs(owedX) < settleThreshold) || exhausted {
            let lastY = owedY.rounded(.toNearestOrEven), lastX = owedX.rounded(.toNearestOrEven)
            if lastY != 0 || lastX != 0 {
                emit(motionFrame(lastY, lastX))
            }
            emit(finalMarker())
            reset()
            return
        }

        if state == .tracking && !beginPending && now - lastInputTime > momentumAfter {
            // Input paused: the rest of the glide is momentum.
            emit(Frame(dy: 0, dx: 0, scrollPhase: PhaseValue.ended, momentumPhase: 0, isMarker: true, isFinal: false))
            state = .momentum
            beginPending = true
        }

        // Post the nearest whole points; the rest carries over. Rounding rather
        // than truncating lets the carry reach the last point while it is owed,
        // and rounding half to even never sends a point backwards.
        let outY = carryY.rounded(.toNearestOrEven), outX = carryX.rounded(.toNearestOrEven)
        guard outY != 0 || outX != 0 else { return }
        carryY -= outY
        carryX -= outX
        owedY -= outY
        owedX -= outX
        emit(motionFrame(outY, outX))
    }

    /// Stops the glide immediately (e.g. on click) and closes the current phase.
    public mutating func stop(emit: (Frame) -> Void) {
        guard state != .idle else { return }
        emit(finalMarker())
        reset()
    }

    /// Drops all state without emitting anything.
    public mutating func reset() {
        remY = 0; remX = 0
        speedY = 0; speedX = 0
        carryY = 0; carryX = 0
        owedY = 0; owedX = 0
        dirY = 0; dirX = 0
        state = .idle
        beginPending = false
    }

    // Exact solution of rem' = -rem/decay, speed' = (rem/decay - speed)/rise.
    // Per axis: owed = rem + speed*rise + carry. Integrate by subtracting
    // stored distance, so changing dt cannot create or lose motion.
    private func integrate(rem: inout Double, speed: inout Double, carry: inout Double) {
        let stored = rem + speed * Self.rise
        speed = speed * velocityFactor + rem * transfer
        rem *= remainingFactor
        carry += stored - (rem + speed * Self.rise)
    }

    private mutating func motionFrame(_ dy: Double, _ dx: Double) -> Frame {
        var f = Frame(dy: dy, dx: dx, scrollPhase: 0, momentumPhase: 0, isMarker: false, isFinal: false)
        if state == .tracking {
            f.scrollPhase = beginPending ? PhaseValue.began : PhaseValue.changed
        } else {
            f.momentumPhase = beginPending ? PhaseValue.momentumBegan : PhaseValue.momentumContinue
        }
        beginPending = false
        return f
    }

    private func finalMarker() -> Frame {
        if state == .momentum {
            return Frame(dy: 0, dx: 0, scrollPhase: 0, momentumPhase: PhaseValue.momentumEnded, isMarker: true, isFinal: true)
        }
        return Frame(dy: 0, dx: 0, scrollPhase: PhaseValue.ended, momentumPhase: 0, isMarker: true, isFinal: true)
    }

    @inline(__always)
    private static func accumulate(_ v: Double, rem: inout Double, speed: inout Double,
                                   carry: inout Double, owed: inout Double, dir: inout Double) {
        guard v != 0 else { return }  // a tick on the other axis leaves this glide alone
        if v * dir > 0 {
            rem += v
            owed += v
        } else {
            // Reversal drops the old glide.
            rem = v
            owed = v
            speed = 0
            carry = 0
        }
        dir = v > 0 ? 1 : -1
    }
}

/// Wheel-tick shaping.
public enum ScrollMath {
    /// Points to glide for a tick of `lines`, the system's accelerated line
    /// count, keeping its sign. A slow notch (a line or less) moves `notch`
    /// points; faster spins move farther, growing with the square root, so a
    /// quick spin covers ground without running away.
    @inline(__always)
    public static func distance(lines: Double, notch: Double) -> Double {
        guard lines != 0 else { return 0 }
        let d = notch * max(1, abs(lines)).squareRoot()
        return lines > 0 ? d : -d
    }

    /// The line delta CoreGraphics gives a pixel scroll of `points`: a tenth,
    /// truncated, but at least one line for any motion.
    @inline(__always)
    public static func lineDelta(points: Double) -> Double {
        let lines = (points / 10).rounded(.towardZero)
        if lines != 0 || points == 0 { return lines }
        return points > 0 ? 1 : -1
    }
}
