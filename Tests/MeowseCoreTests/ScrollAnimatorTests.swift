import XCTest
@testable import MeowseCore

final class ScrollAnimatorTests: XCTestCase {

    private func run(_ a: inout ScrollAnimator, from t0: Double, hz: Double, maxFrames: Int = 2000) -> (frames: [ScrollAnimator.Frame], end: Double) {
        var out: [ScrollAnimator.Frame] = []
        var t = t0
        let dt = 1 / hz
        for _ in 0..<maxFrames where a.isActive {
            t += dt
            a.step(now: t, dt: dt) { out.append($0) }
        }
        return (out, t)
    }

    func testGlideCoversFullDistanceAndEnds() {
        var a = ScrollAnimator()
        a.input(dy: 100, dx: 0, now: 0) { _ in XCTFail("no frame on first input") }
        let (frames, _) = run(&a, from: 0, hz: 120)
        XCTAssertFalse(a.isActive)
        let total = frames.filter { !$0.isMarker }.reduce(0) { $0 + $1.dy }
        XCTAssertEqual(total, 100, accuracy: 1e-9)
        XCTAssertTrue(frames.last!.isFinal)
    }

    func testGlideTimeIsTheSameAtEveryRefreshRate() {
        func duration(hz: Double) -> Double {
            var a = ScrollAnimator()
            a.input(dy: 300, dx: 0, now: 0) { _ in }
            return run(&a, from: 0, hz: hz).end
        }
        let d60 = duration(hz: 60), d120 = duration(hz: 120), d240 = duration(hz: 240)
        XCTAssertEqual(d60, d120, accuracy: 0.05)
        XCTAssertEqual(d120, d240, accuracy: 0.05)
    }

    func testGlideTimeSettingSetsTheLength() {
        func duration(glideTime: Double) -> Double {
            var s = Settings()
            s.glideTime = glideTime
            var a = ScrollAnimator(decay: EngineConfig(s).decay)
            a.input(dy: 80, dx: 0, now: 0) { _ in }
            return run(&a, from: 0, hz: 120).end
        }
        // 99% of the distance arrives by the glide time; the last point a little later.
        XCTAssertEqual(duration(glideTime: 0.4), 0.47, accuracy: 0.05)
        XCTAssertEqual(duration(glideTime: 0.8), 0.92, accuracy: 0.08)
    }

    func testFirstFrameMovesImmediately() {
        var a = ScrollAnimator()
        a.input(dy: 80, dx: 0, now: 0) { _ in }
        var first: ScrollAnimator.Frame?
        a.step(now: 0.008, dt: 1.0 / 120) { first = $0 }
        XCTAssertNotNil(first)
        XCTAssertGreaterThanOrEqual(first!.dy, 1)
        XCTAssertEqual(first!.scrollPhase, ScrollAnimator.PhaseValue.began)
    }

    func testPhaseSequenceTrackingThenMomentum() {
        var a = ScrollAnimator()
        a.input(dy: 200, dx: 0, now: 0) { _ in }
        let (frames, _) = run(&a, from: 0, hz: 120)
        let motion = frames.filter { !$0.isMarker }
        XCTAssertEqual(motion.first?.scrollPhase, 1)  // began
        XCTAssertEqual(motion[1].scrollPhase, 2)       // changed
        // A tracking-ended marker precedes momentum.
        let endIdx = frames.firstIndex { $0.isMarker && $0.scrollPhase == 4 }!
        XCTAssertEqual(frames[endIdx + 1].momentumPhase, 1)  // momentum began
        XCTAssertEqual(frames[endIdx + 2].momentumPhase, 2)
        XCTAssertEqual(frames.last, .init(dy: 0, dx: 0, scrollPhase: 0, momentumPhase: 3, isMarker: true, isFinal: true))
    }

    func testInputDuringMomentumEndsMomentumAndBeginsTracking() {
        var a = ScrollAnimator()
        a.input(dy: 500, dx: 0, now: 0) { _ in }
        var t = 0.0
        while a.state != .momentum { t += 1 / 120; a.step(now: t, dt: 1 / 120) { _ in } }
        var emitted: [ScrollAnimator.Frame] = []
        a.input(dy: 50, dx: 0, now: t) { emitted.append($0) }
        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted[0].momentumPhase, 3)
        XCTAssertFalse(emitted[0].isFinal)
        XCTAssertEqual(a.state, .tracking)
        var next: ScrollAnimator.Frame?
        a.step(now: t + 1 / 120, dt: 1 / 120) { next = $0 }
        XCTAssertEqual(next?.scrollPhase, 1)
    }

    func testDirectionReversalDropsOldGlide() {
        var a = ScrollAnimator()
        a.input(dy: 500, dx: 0, now: 0) { _ in }
        a.step(now: 0.01, dt: 1 / 120) { _ in }
        a.input(dy: -40, dx: 0, now: 0.02) { _ in }
        var f: ScrollAnimator.Frame?
        a.step(now: 0.03, dt: 1 / 120) { f = $0 }
        XCTAssertLessThan(f!.dy, 0)
        let (rest, _) = run(&a, from: 0.03, hz: 120)
        let total = rest.filter { !$0.isMarker }.reduce(f!.dy) { $0 + $1.dy }
        XCTAssertEqual(total, -40, accuracy: 2)
    }

    func testHorizontalTickDoesNotKillVerticalGlide() {
        var a = ScrollAnimator()
        a.input(dy: 300, dx: 0, now: 0) { _ in }
        a.input(dy: 0, dx: 50, now: 0.01) { _ in }
        let (frames, _) = run(&a, from: 0.01, hz: 120)
        let y = frames.reduce(0) { $0 + $1.dy }
        let x = frames.reduce(0) { $0 + $1.dx }
        XCTAssertEqual(y, 300, accuracy: 3)
        XCTAssertEqual(x, 50, accuracy: 3)
    }

    func testStopEmitsFinalAndGoesIdle() {
        var a = ScrollAnimator()
        a.input(dy: 300, dx: 0, now: 0) { _ in }
        a.step(now: 0.01, dt: 1 / 120) { _ in }
        var f: ScrollAnimator.Frame?
        a.stop { f = $0 }
        XCTAssertEqual(f?.isFinal, true)
        XCTAssertEqual(f?.scrollPhase, 4)
        XCTAssertFalse(a.isActive)
        a.stop { _ in XCTFail("an idle stop must not emit") }
    }

    func testSameDistanceAtEveryFrameRate() {
        // The event's point delta is an integer field, so only whole points
        // survive posting. None may be dropped, at any refresh rate.
        for hz in [60.0, 120.0, 144.0, 240.0] {
            var a = ScrollAnimator()
            a.input(dy: 90.72, dx: -12.5, now: 0) { _ in }
            let frames = run(&a, from: 0, hz: hz).frames
            for f in frames {
                XCTAssertEqual(f.dy, f.dy.rounded(), "whole points only (\(hz) Hz)")
                XCTAssertEqual(f.dx, f.dx.rounded(), "whole points only (\(hz) Hz)")
            }
            XCTAssertEqual(frames.reduce(0) { $0 + $1.dy }, 90.72, accuracy: 0.5, "\(hz) Hz")
            XCTAssertEqual(frames.reduce(0) { $0 + $1.dx }, -12.5, accuracy: 0.5, "\(hz) Hz")
            XCTAssertFalse(frames.contains { $0.dy < 0 || $0.dx > 0 }, "never backwards (\(hz) Hz)")
        }
    }

    func testManyNotchesStayWithinHalfAPoint() {
        var a = ScrollAnimator()
        var t = 0.0, posted = 0.0
        for _ in 0..<7 {
            a.input(dy: 80, dx: 0, now: t) { _ in }
            for _ in 0..<6 { t += 1 / 120; a.step(now: t, dt: 1 / 120) { posted += $0.dy } }
        }
        posted += run(&a, from: t, hz: 120).frames.reduce(0) { $0 + $1.dy }
        XCTAssertEqual(posted, 7 * 80, accuracy: 0.5)
    }

    func testNoEmptyFrames() {
        // Every motion frame costs the target app an event, so each must move it.
        var a = ScrollAnimator()
        a.input(dy: 400, dx: 0, now: 0) { _ in }
        let motion = run(&a, from: 0, hz: 144).frames.filter { !$0.isMarker }
        for f in motion {
            XCTAssertGreaterThanOrEqual(abs(f.dy), 1)
        }
    }

    func testEventBudgetPerNotch() {
        // One default notch at 120 Hz glides for 73 frames; whole-point frames
        // need 42 motion events, each of which moves the page.
        var a = ScrollAnimator()
        a.input(dy: Settings().notchDistance, dx: 0, now: 0) { _ in }
        let (frames, end) = run(&a, from: 0, hz: 120)
        XCTAssertEqual(end * 120, 73, accuracy: 0.5)
        XCTAssertLessThanOrEqual(frames.filter { !$0.isMarker }.count, 42)
    }

    func testTinyGlideRoundsToTheNearestPoint() {
        var a = ScrollAnimator()
        a.input(dy: 0.6, dx: 0, now: 0) { _ in }
        XCTAssertEqual(run(&a, from: 0, hz: 120).frames.reduce(0) { $0 + $1.dy }, 1)
        a.input(dy: 0.4, dx: 0, now: 1) { _ in }
        let frames = run(&a, from: 1, hz: 120).frames
        XCTAssertEqual(frames.count, 1, "only the closing marker")
        XCTAssertTrue(frames[0].isMarker && frames[0].isFinal)
    }

    func testChangingIntervalsConserveBothAxesAndFinish() {
        let sequences: [[Double]] = [
            [1/60, 1/120], [1/120, 1/60], [1/144, 1/60], [1/60, 1/144],
            [1/144, 0.027, 1/60, 0.003, 0.05], [1/60, 1/60, 1/120]
        ]
        for intervals in sequences {
            for extra in [0.0, 100.25] {
                var a = ScrollAnimator()
                var frames: [ScrollAnimator.Frame] = []
                var t = 0.0
                a.input(dy: 100.25, dx: -73.75, now: t) { frames.append($0) }
                for i in 0..<1000 where a.isActive {
                    if i == 6 { a.input(dy: extra, dx: -extra, now: t) { frames.append($0) } }
                    let dt = i < 6 ? intervals[0] : intervals[1 + (i - 6) % (intervals.count - 1)]
                    t += dt
                    a.step(now: t, dt: dt) { frames.append($0) }
                }
                XCTAssertFalse(a.isActive, "intervals: \(intervals)")
                XCTAssertLessThan(t, 2, "default decay should settle within 18 time constants")
                XCTAssertEqual(frames.reduce(0) { $0 + $1.dy }, 100.25 + extra, accuracy: 0.5)
                XCTAssertEqual(frames.reduce(0) { $0 + $1.dx }, -73.75 - extra, accuracy: 0.5)
                XCTAssertEqual(frames.filter(\.isFinal).count, 1)
                XCTAssertTrue(frames.last?.isFinal == true)
            }
        }
    }

    func testAccountingInvariantAtEveryStepIncludingEqualTimeConstants() {
        for decay in [0.01, ScrollAnimator.rise, 0.5 / log(100), 0.65] {
            var a = ScrollAnimator(decay: decay)
            a.settleThreshold = 0
            a.input(dy: 107.25, dx: -83.7, now: 0) { _ in }
            var t = 0.0, y = 0.0, x = 0.0
            for i in 0..<4000 where a.isActive {
                let dt = [1/144.0, 1/60.0, 0.031, 0.003][i % 4]
                t += dt
                a.step(now: t, dt: dt) { y += $0.dy; x += $0.dx }
                if a.isActive {
                    let values = Dictionary(uniqueKeysWithValues: Mirror(reflecting: a).children.compactMap { child -> (String, Double)? in
                        guard let name = child.label, let value = child.value as? Double else { return nil }
                        return (name, value)
                    })
                    for axis in ["Y", "X"] {
                        let stored = values["rem" + axis]! + values["speed" + axis]! * ScrollAnimator.rise + values["carry" + axis]!
                        XCTAssertEqual(stored, values["owed" + axis]!, accuracy: 1e-10)
                    }
                }
            }
            XCTAssertFalse(a.isActive, "numerical exhaustion must finish even with a zero threshold")
            XCTAssertEqual(y, 107.25, accuracy: 0.5)
            XCTAssertEqual(x, -83.7, accuracy: 0.5)
        }
    }

    func testVariableTimingReversalCancelsOnlyReversedAxis() {
        var a = ScrollAnimator()
        a.input(dy: 100, dx: 70, now: 0) { _ in }
        var x = 0.0, reversedY = 0.0, t = 0.0
        for dt in [1/120.0, 1/60.0, 1/144.0] {
            t += dt
            a.step(now: t, dt: dt) { x += $0.dx }
        }
        a.input(dy: -40.25, dx: 0, now: t) { _ in }
        for i in 0..<300 where a.isActive {
            let dt = i % 2 == 0 ? 1/60.0 : 1/144.0
            t += dt
            a.step(now: t, dt: dt) { x += $0.dx; reversedY += $0.dy }
        }
        XCTAssertFalse(a.isActive)
        XCTAssertEqual(reversedY, -40.25, accuracy: 0.5)
        XCTAssertEqual(x, 70, accuracy: 0.5)
    }

    func testNotchDistanceGrowsWithTheSquareRootOfLines() {
        XCTAssertEqual(ScrollMath.distance(lines: 1, notch: 80), 80)
        XCTAssertEqual(ScrollMath.distance(lines: 0.3, notch: 80), 80, "a slow notch never moves less than one notch")
        XCTAssertEqual(ScrollMath.distance(lines: -4, notch: 80), -160)
        XCTAssertEqual(ScrollMath.distance(lines: 9, notch: 80), 240)
        XCTAssertEqual(ScrollMath.distance(lines: 0, notch: 80), 0)
    }

    func testLineDeltaMatchesCoreGraphicsPixelScrolls() {
        // Measured from CGEvent(scrollWheelEvent2Source:units:.pixel ...).
        for (points, lines) in [(0.0, 0.0), (1, 1), (9, 1), (19, 1), (20, 2), (29, 2), (30, 3), (99, 9), (-1, -1), (-16, -1), (-25, -2)] {
            XCTAssertEqual(ScrollMath.lineDelta(points: points), lines, "\(points) pt")
        }
    }
}
