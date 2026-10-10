import XCTest
@testable import MeowseCore

final class RefreshTests: XCTestCase {

    private let mb = 1 << 20
    private let day: TimeInterval = 24 * 3600

    func testRestartsOnceMemoryHasDoubled() {
        XCTAssertFalse(Refresh.isDue(footprint: 16 * mb, atLaunch: 9 * mb, uptime: day, busy: false))
        XCTAssertTrue(Refresh.isDue(footprint: 18 * mb, atLaunch: 9 * mb, uptime: day, busy: false))
        XCTAssertTrue(Refresh.isDue(footprint: 24 * mb, atLaunch: 9 * mb, uptime: day, busy: false))
    }

    func testOpeningTheMenuIsNotEnough() {
        // Launch is about 8.5 MB and the first menu open adds about 5.5 MB.
        XCTAssertFalse(Refresh.isDue(footprint: 14 * mb, atLaunch: 17 * mb / 2, uptime: day, busy: false))
    }

    func testNeverCutsAnythingShort() {
        XCTAssertFalse(Refresh.isDue(footprint: 24 * mb, atLaunch: 9 * mb, uptime: day, busy: true))
    }

    func testARecentStartIsLeftAlone() {
        // A restart resets the uptime, so it can't lead straight to another.
        XCTAssertFalse(Refresh.isDue(footprint: 24 * mb, atLaunch: 9 * mb, uptime: 59 * 60, busy: false))
        XCTAssertTrue(Refresh.isDue(footprint: 24 * mb, atLaunch: 9 * mb, uptime: Refresh.minimumUptime, busy: false))
    }

    func testNothingHappensBeforeLaunchIsMeasured() {
        XCTAssertFalse(Refresh.isDue(footprint: 24 * mb, atLaunch: 0, uptime: day, busy: false))
    }
}
