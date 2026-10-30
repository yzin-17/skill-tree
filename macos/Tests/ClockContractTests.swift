import XCTest
@testable import SkillAtlasCore

final class ClockContractTests: XCTestCase {
    func testConfigurationBoundariesAndContract() throws {
        XCTAssertNoThrow(try FocusConfiguration().validate())
        XCTAssertNoThrow(try FocusConfiguration(mode: .pomodoro, targetSeconds: 1500, restSeconds: 300, rounds: 4).validate())
        XCTAssertThrowsError(try FocusConfiguration(mode: .countdown, targetSeconds: 0).validate())
        XCTAssertThrowsError(try FocusConfiguration(mode: .pomodoro, rounds: 0).validate())
        XCTAssertThrowsError(try FocusConfiguration(mode: .pomodoro, restSeconds: -1).validate())
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Core/FocusEngine/clock-contract.json"))) as! [String: Any]
        XCTAssertEqual(json["contract"] as? String, "C-CLOCK")
        XCTAssertEqual(json["states"] as? [String], ["running", "paused", "finished"])
    }
}
