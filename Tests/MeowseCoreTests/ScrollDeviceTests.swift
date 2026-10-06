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

    func testPhasedContinuousScrollingIsTouch() {
        // Finger down (began), and the glide after lifting (momentum only).
        XCTAssertEqual(device(continuous: true, scrollPhase: 1), .touch)
        XCTAssertEqual(device(continuous: true, momentumPhase: 2), .touch)
    }

    func testUnphasedContinuousScrollingIsUnknown() {
        // Already-smooth remote sessions, or Meowse's frames without trackpad phases.
        XCTAssertNil(device(continuous: true))
    }

    func testMeowseFramesAreNotTouch() {
        // Copied from a hardware wheel event, with trackpad-style phases.
        XCTAssertNil(device(continuous: true, userData: ScrollDevice.frameTag, scrollPhase: 2))
        XCTAssertNil(device(continuous: true, userData: ScrollDevice.frameTag, momentumPhase: 3))
    }

    func testOtherAppsContinuousScrollingIsIgnored() {
        XCTAssertNil(device(continuous: true, sourcePID: 812, scrollPhase: 2))
    }
}
