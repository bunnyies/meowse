import XCTest
@testable import MeowseCore

final class ScrollDeviceTests: XCTestCase {

    private func device(continuous: Bool, sourcePID: Int64 = 0, userData: Int64 = 0,
                        scrollPhase: Int64 = 0, momentumPhase: Int64 = 0) -> ScrollDevice? {
        ScrollDevice.of(continuous: continuous, sourcePID: sourcePID, userData: userData,
                        scrollPhase: scrollPhase, momentumPhase: momentumPhase)
    }

    func testWheelTicksAreWheel() {
        XCTAssertEqual(device(continuous: false), .wheel)
        // Mouse utilities repost the wheel's ticks; Meowse smooths them all the same.
        XCTAssertEqual(device(continuous: false, sourcePID: 812), .wheel)
    }

    func testTrackpadMomentumEndIsNotAWheelTick() {
        // Seen when momentum is cut short: discrete, one point, momentum ended.
        XCTAssertFalse(ScrollDevice.isWheelTick(scrollPhase: 0, momentumPhase: 3))
        XCTAssertNil(device(continuous: false, momentumPhase: 3))
        XCTAssertTrue(ScrollDevice.isWheelTick(scrollPhase: 0, momentumPhase: 0))
    }

    func testTouchCountsWhenAGestureStarts() {
        XCTAssertEqual(device(continuous: true, scrollPhase: 1), .touch)    // began
        XCTAssertEqual(device(continuous: true, scrollPhase: 128), .touch)  // may begin
    }

    func testCoastingAndMidGestureEventsDontSwitch() {
        // Momentum still arriving after a switch to the wheel, or the middle of a gesture.
        XCTAssertNil(device(continuous: true, momentumPhase: 2))
        XCTAssertNil(device(continuous: true, scrollPhase: 2))
        XCTAssertNil(device(continuous: true, scrollPhase: 4))
    }

    func testUnphasedContinuousScrollingIsUnknown() {
        // Already-smooth remote sessions, or Meowse's frames without trackpad phases.
        XCTAssertNil(device(continuous: true))
    }

    func testMeowseFramesAreNotTouch() {
        // Copied from a hardware wheel event, with trackpad-style phases.
        XCTAssertNil(device(continuous: true, userData: ScrollDevice.frameTag, scrollPhase: 1))
    }

    func testOtherAppsContinuousScrollingIsIgnored() {
        XCTAssertNil(device(continuous: true, sourcePID: 812, scrollPhase: 1))
    }

    func testMomentumEchoes() {
        // The system's "momentum ended" copies of a wheel tick and of our frames.
        XCTAssertTrue(ScrollDevice.isMomentumEcho(continuous: false, scrollPhase: 0, momentumPhase: 3, tagged: false))
        XCTAssertTrue(ScrollDevice.isMomentumEcho(continuous: true, scrollPhase: 0, momentumPhase: 3, tagged: true))
        // The trackpad's own coasting and its real end, and our own frames, pass.
        XCTAssertFalse(ScrollDevice.isMomentumEcho(continuous: true, scrollPhase: 0, momentumPhase: 2, tagged: false))
        XCTAssertFalse(ScrollDevice.isMomentumEcho(continuous: true, scrollPhase: 0, momentumPhase: 3, tagged: false))
        XCTAssertFalse(ScrollDevice.isMomentumEcho(continuous: true, scrollPhase: 0, momentumPhase: 0, tagged: true))
    }

    func testTouchKindFromScrollAcceleration() {
        // As the trackpad and Magic Mouse drivers in macOS set it.
        XCTAssertEqual(TouchKind(scrollAcceleration: "HIDTrackpadScrollAcceleration", product: "Apple Internal Keyboard / Trackpad"), .trackpad)
        XCTAssertEqual(TouchKind(scrollAcceleration: "HIDTrackpadScrollAcceleration", product: nil), .trackpad)
        XCTAssertEqual(TouchKind(scrollAcceleration: "HIDMouseScrollAcceleration", product: nil), .magicMouse)
    }

    func testOriginalMagicMouseFallsBackToProductName() {
        XCTAssertEqual(TouchKind(scrollAcceleration: nil, product: "Magic Mouse"), .magicMouse)
        XCTAssertEqual(TouchKind(scrollAcceleration: nil, product: "Magic Trackpad"), .trackpad)
    }

    func testUnknownSurfaceIsUnnamed() {
        XCTAssertNil(TouchKind(scrollAcceleration: nil, product: nil))
        XCTAssertNil(TouchKind(scrollAcceleration: nil, product: "Remote Desktop"))
    }

    func testTouchKindNames() {
        XCTAssertEqual(TouchKind.trackpad.name, "trackpad")
        XCTAssertEqual(TouchKind.magicMouse.name, "Magic Mouse")
    }
}
