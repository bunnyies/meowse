import XCTest
@testable import MeowseCore

final class AwakeTests: XCTestCase {

    func testWiggleOnlyWhenIdle() {
        // User active 10 s ago with a 60 s interval: don't wiggle, check again when they'd hit 60 s.
        let active = Awake.wigglePlan(idle: 10, interval: 60)
        XCTAssertFalse(active.wiggleNow)
        XCTAssertEqual(active.nextCheck, 50)

        let idle = Awake.wigglePlan(idle: 61, interval: 60)
        XCTAssertTrue(idle.wiggleNow)
        XCTAssertEqual(idle.nextCheck, 60)
    }

    func testWiggleToleratesTimerLeeway() {
        // A timer that fired a little early must not skip a whole cycle.
        XCTAssertTrue(Awake.wigglePlan(idle: 58, interval: 60).wiggleNow)
    }

    func testWiggleNeverSchedulesBusyLoop() {
        XCTAssertGreaterThanOrEqual(Awake.wigglePlan(idle: 56.9, interval: 60).nextCheck, 1)
    }

    func testWhileUserIsActiveTimerWakesAtMostOncePerInterval() {
        // The user is constantly active (idle ≈ 0): every check is a full interval away.
        XCTAssertEqual(Awake.wigglePlan(idle: 0, interval: 120).nextCheck, 120)
    }

    func testLabels() {
        XCTAssertEqual(Awake.durationLabel(0), "Until Turned Off")
        XCTAssertEqual(Awake.durationLabel(15 * 60), "15 Minutes")
        XCTAssertEqual(Awake.durationLabel(3600), "1 Hour")
        XCTAssertEqual(Awake.durationLabel(8 * 3600), "8 Hours")
        XCTAssertEqual(Awake.intervalLabel(30), "30 Seconds")
        XCTAssertEqual(Awake.intervalLabel(60), "1 Minute")
        XCTAssertEqual(Awake.remainingLabel(30), "Less than a minute left")
        XCTAssertEqual(Awake.remainingLabel(52 * 60), "52 min left")
        XCTAssertEqual(Awake.remainingLabel(65 * 60), "1 hr 5 min left")
        XCTAssertEqual(Awake.remainingLabel(2 * 3600), "2 hr left")
    }

    func testOldSettingsGainAwakeDefaults() throws {
        let s = try JSONDecoder().decode(Settings.self, from: #"{"speed": 3}"#.data(using: .utf8)!)
        XCTAssertEqual(s.awakeDuration, 0)
        XCTAssertEqual(s.wiggleInterval, 60)
        XCTAssertFalse(s.awakeAllowDisplaySleep)
    }

    func testNonScrollSettingsDoNotChangeEngineConfig() {
        var changed = Settings()
        changed.awakeDuration = 3600
        changed.wiggleInterval = 30
        changed.checkForUpdates = false
        XCTAssertEqual(EngineConfig(Settings()), EngineConfig(changed), "non-scroll settings must not rebuild the event tap")
    }
}
