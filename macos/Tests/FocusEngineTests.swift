import XCTest
@testable import SkillAtlasCore

final class FocusEngineTests: XCTestCase {
    let account = UUID().uuidString
    let skill = UUID().uuidString
    let start = Date(timeIntervalSince1970: 1_798_000_000)
    func reading(_ seconds: Double, wall: Double? = nil) -> ClockReading { .init(monotonic: 1000 + seconds, wall: start.addingTimeInterval(wall ?? seconds)) }
    func engine(_ configuration: FocusConfiguration = .init()) throws -> FocusEngine {
        var value = FocusEngine(); try value.start(accountId: account, skillId: skill, configuration: configuration, at: reading(0)); return value
    }
    func testPauseFractionsAndRepeatedFinish() throws {
        var value = try engine()
        try value.pause(at: reading(20.5)); value.tick(at: reading(100))
        XCTAssertEqual(value.snapshot?.effectiveElapsed, 20.5)
        try value.resume(at: reading(110.5)); try value.finish(at: reading(161))
        XCTAssertEqual(value.snapshot?.effectiveSeconds, 71)
        XCTAssertEqual(value.snapshot?.status, .finished)
        XCTAssertEqual(try value.finish(at: reading(500)).count, 0)
        XCTAssertThrowsError(try value.start(accountId: account, skillId: skill, configuration: .init(), at: reading(600)))
        try value.clearFinished()
        XCTAssertNoThrow(try value.start(accountId: account, skillId: skill, configuration: .init(), at: reading(600)))
    }
    func testCountdownCapsLateRefreshAndNotifiesOnce() throws {
        var value = try engine(.init(mode: .countdown, targetSeconds: 60))
        let signals = value.tick(at: reading(75))
        XCTAssertEqual(value.snapshot?.effectiveSeconds, 60)
        XCTAssertEqual(value.snapshot?.endedAt, start.addingTimeInterval(60))
        XCTAssertEqual(signals.map(\.kind), [.finished])
        XCTAssertTrue(value.tick(at: reading(90)).isEmpty)
    }
    func testEarlyFinishAndClockAdjustment() throws {
        var value = try engine(.init(mode: .countdown, targetSeconds: 600))
        try value.finish(at: reading(47, wall: -3600))
        XCTAssertEqual(value.snapshot?.effectiveSeconds, 47)
        XCTAssertEqual(value.snapshot?.finishReason, .manual)
        XCTAssertEqual(value.snapshot?.endedAt, start.addingTimeInterval(-3600))
    }
    func testRefreshFrequencyDoesNotChangeTime() throws {
        var frequent = try engine(); var sparse = try engine()
        for number in 1...401 { frequent.tick(at: reading(Double(number) * 0.25)) }
        sparse.tick(at: reading(100.25))
        XCTAssertEqual(frequent.snapshot?.effectiveElapsed, sparse.snapshot?.effectiveElapsed)
    }
    func testRecoveryDoesNotInventUnobservedTime() throws {
        var running = try engine(); running.tick(at: reading(42))
        let encoded = try JSONEncoder().encode(XCTUnwrap(running.snapshot))
        let saved = try JSONDecoder().decode(FocusSnapshot.self, from: encoded)
        var restored = FocusEngine(); let signals = try restored.restore(saved)
        restored.tick(at: reading(542))
        XCTAssertEqual(restored.snapshot?.id, running.snapshot?.id)
        XCTAssertEqual(restored.snapshot?.accountId, account)
        XCTAssertEqual(restored.snapshot?.status, .paused)
        XCTAssertEqual(restored.snapshot?.effectiveSeconds, 42)
        XCTAssertEqual(signals.map(\.kind), [.paused])
        try restored.resume(at: reading(600)); try restored.finish(at: reading(610))
        XCTAssertEqual(restored.snapshot?.effectiveSeconds, 52)
    }
}
