import XCTest
@testable import SkillAtlasCore

final class PomodoroTests: XCTestCase {
    let base = Date(timeIntervalSince1970: 1_798_000_000)
    func time(_ value: Double) -> ClockReading { .init(monotonic: value, wall: base.addingTimeInterval(value)) }
    func start(_ configuration: FocusConfiguration) throws -> FocusEngine {
        var engine = FocusEngine()
        try engine.start(accountId: UUID().uuidString, skillId: UUID().uuidString, configuration: configuration, at: time(0))
        return engine
    }
    func testSharedPomodoroBoundary() throws {
        struct Contract: Decodable { let fixtures: Fixtures }
        struct Fixtures: Decodable { let pomodoro: Example }
        struct Example: Decodable { let target: Int; let rest: Int; let rounds: Int; let observedAfter: Double; let effectiveSeconds: Int; let phase: FocusPhase; let round: Int }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let sample = try APIClient.decoder().decode(Contract.self, from: Data(contentsOf: root.appendingPathComponent("Core/FocusEngine/clock-contract.json"))).fixtures.pomodoro
        var engine = try start(.init(mode: .pomodoro, targetSeconds: sample.target, restSeconds: sample.rest, rounds: sample.rounds))
        engine.tick(at: time(sample.observedAfter))
        XCTAssertEqual(engine.snapshot?.effectiveSeconds, sample.effectiveSeconds)
        XCTAssertEqual(engine.snapshot?.phase, sample.phase)
        XCTAssertEqual(engine.snapshot?.round, sample.round)
        let signals = engine.tick(at: time(5000))
        XCTAssertEqual(engine.snapshot?.effectiveSeconds, 3000)
        XCTAssertEqual(engine.snapshot?.endedAt, base.addingTimeInterval(3300))
        XCTAssertEqual(signals.map(\.kind), [.finished])
    }
    func testPauseDuringRestAndEarlyEnd() throws {
        var engine = try start(.init(mode: .pomodoro, targetSeconds: 1500, restSeconds: 300, rounds: 2))
        try engine.pause(at: time(1600))
        XCTAssertEqual(engine.snapshot?.effectiveSeconds, 1500)
        XCTAssertEqual(engine.snapshot?.phase, .rest)
        try engine.resume(at: time(5200))
        engine.tick(at: time(5400))
        XCTAssertEqual(engine.snapshot?.phase, .focus)
        XCTAssertEqual(engine.snapshot?.round, 2)
        try engine.finish(at: time(5412))
        XCTAssertEqual(engine.snapshot?.effectiveSeconds, 1512)
    }
    func testMultipleBoundariesAndNoFinalRest() throws {
        var engine = try start(.init(mode: .pomodoro, targetSeconds: 10, restSeconds: 2, rounds: 3))
        let signals = engine.tick(at: time(10000))
        XCTAssertEqual(engine.snapshot?.effectiveSeconds, 30)
        XCTAssertEqual(engine.snapshot?.endedAt, base.addingTimeInterval(34))
        XCTAssertEqual(signals.filter { $0.kind == .restStarted }.count, 2)
        XCTAssertEqual(signals.filter { $0.kind == .roundStarted }.count, 2)
        XCTAssertEqual(signals.filter { $0.kind == .finished }.count, 1)
    }
    func testZeroRestTransitionsImmediately() throws {
        var engine = try start(.init(mode: .pomodoro, targetSeconds: 10, restSeconds: 0, rounds: 3))
        let signals = engine.tick(at: time(30))
        XCTAssertEqual(engine.snapshot?.effectiveSeconds, 30)
        XCTAssertEqual(engine.snapshot?.status, .finished)
        XCTAssertFalse(signals.contains { $0.kind == .restStarted })
    }
}
