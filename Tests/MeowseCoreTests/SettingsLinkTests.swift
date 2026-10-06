import XCTest
@testable import MeowseCore

final class SettingsLinkTests: XCTestCase {

    func testLinesArriveWholeHoweverTheyreSplit() {
        var reader = LineReader()
        XCTAssertEqual(reader.feed(Data("{\"a\":1}\n{\"b\"".utf8)), [Data("{\"a\":1}".utf8)])
        XCTAssertEqual(reader.feed(Data(":2}".utf8)), [])
        XCTAssertEqual(reader.feed(Data("\n\n{\"c\":3}\n".utf8)), [Data("{\"b\":2}".utf8), Data("{\"c\":3}".utf8)])
    }

    func testStateRoundTrips() throws {
        var state = SettingsState()
        state.settings = Settings()
        state.trusted = true
        state.engine = .active
        state.device = .touch
        state.touch = .magicMouse
        state.update = .available(version: "1.3.0", notes: "Line one\nLine two")
        state.releasePage = URL(string: "https://github.com/bunnyies/meowse/releases/tag/v1.3.0")
        let line = try XCTUnwrap(SettingsLink.encode(ToSettings.state(state)))
        // Exactly one newline: the one that ends the message.
        XCTAssertEqual(line.filter { $0 == 0x0A }.count, 1)
        var reader = LineReader()
        let lines = reader.feed(line)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(SettingsLink.decode(ToSettings.self, from: lines[0]), .state(state))
    }

    func testActionsRoundTrip() throws {
        var edited = Settings()
        edited.notchDistance = 140
        for action in [SettingsAction.settings(edited), .keepAwake(true), .launchAtLogin(false), .installUpdate] {
            let line = try XCTUnwrap(SettingsLink.encode(action))
            XCTAssertEqual(SettingsLink.decode(SettingsAction.self, from: line.dropLast()), action)
        }
    }

    func testShowWithAndWithoutTab() throws {
        for message in [ToSettings.show(nil), .show(.updates)] {
            let line = try XCTUnwrap(SettingsLink.encode(message))
            XCTAssertEqual(SettingsLink.decode(ToSettings.self, from: line.dropLast()), message)
        }
    }

    func testGarbageIsIgnored() {
        XCTAssertNil(SettingsLink.decode(SettingsAction.self, from: Data("not json".utf8)))
    }
}
