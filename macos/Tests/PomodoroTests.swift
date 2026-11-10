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
        struct Example: Decodable { let target: Int; let rest: Int; let rounds: Int; let observedAfter: Double; let effectiveSeconds: Int; let phase: FocusPhase; let round: Int; let state: FocusStatus; let pendingPhase: FocusPhase }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let sample = try APIClient.decoder().decode(Contract.self, from: Data(contentsOf: root.appendingPathComponent("Core/FocusEngine/clock-contract.json"))).fixtures.pomodoro
        var engine = try start(.init(mode: .pomodoro, targetSeconds: sample.target, restSeconds: sample.rest, rounds: sample.rounds))
        engine.tick(at: time(sample.observedAfter))
        XCTAssertEqual(engine.snapshot?.effectiveSeconds, sample.effectiveSeconds)
        XCTAssertEqual(engine.snapshot?.phase, sample.phase)
        XCTAssertEqual(engine.snapshot?.round, sample.round)
        XCTAssertEqual(engine.snapshot?.status, sample.state)
        XCTAssertEqual(engine.snapshot?.pendingPhase, sample.pendingPhase)
        try engine.resume(at: time(1800))
        engine.tick(at: time(2100))
        XCTAssertEqual(engine.snapshot?.pendingPhase, .focus)
        try engine.resume(at: time(2500))
        let signals = engine.tick(at: time(5000))
        XCTAssertEqual(engine.snapshot?.effectiveSeconds, 3000)
        XCTAssertEqual(engine.snapshot?.endedAt, base.addingTimeInterval(4000))
        XCTAssertEqual(signals.map(\.kind), [.finished])
    }
    func testPauseDuringRestAndEarlyEnd() throws {
        var engine = try start(.init(mode: .pomodoro, targetSeconds: 1500, restSeconds: 300, rounds: 2))
        engine.tick(at: time(1500))
        try engine.resume(at: time(1500))
        try engine.pause(at: time(1600))
        XCTAssertEqual(engine.snapshot?.effectiveSeconds, 1500)
        XCTAssertEqual(engine.snapshot?.phase, .rest)
        try engine.resume(at: time(5200))
        engine.tick(at: time(5400))
        XCTAssertEqual(engine.snapshot?.pendingPhase, .focus)
        try engine.resume(at: time(5400))
        XCTAssertEqual(engine.snapshot?.phase, .focus)
        XCTAssertEqual(engine.snapshot?.round, 2)
        try engine.finish(at: time(5412))
        XCTAssertEqual(engine.snapshot?.effectiveSeconds, 1512)
    }
    func testLateObservationWaitsAtFirstBoundaryAndFinalRoundSaves() throws {
        var engine = try start(.init(mode: .pomodoro, targetSeconds: 10, restSeconds: 2, rounds: 3))
        let signals = engine.tick(at: time(10000))
        XCTAssertEqual(engine.snapshot?.effectiveSeconds, 10)
        XCTAssertEqual(engine.snapshot?.pendingPhase, .rest)
        XCTAssertEqual(engine.snapshot?.round, 1)
        XCTAssertEqual(signals.map(\.kind), [.phaseEnded, .paused])
        XCTAssertEqual(signals.first?.occurredAt, base.addingTimeInterval(10))
        XCTAssertTrue(engine.tick(at: time(20000)).isEmpty)
        for round in 1...2 {
            let start = Double(round * 20000)
            try engine.resume(at: time(start))
            XCTAssertEqual(engine.snapshot?.phaseElapsed, 0)
            engine.tick(at: time(start + 2))
            XCTAssertEqual(engine.snapshot?.pendingPhase, .focus)
            try engine.resume(at: time(start + 10))
            let ended = engine.tick(at: time(start + 20))
            if round == 2 { XCTAssertEqual(ended.map(\.kind), [.finished]) }
        }
        XCTAssertEqual(engine.snapshot?.effectiveSeconds, 30)
        XCTAssertEqual(engine.snapshot?.status, .finished)
        XCTAssertNil(engine.snapshot?.pendingPhase)
    }
    func testZeroRestRequiresConfirmationForNextRound() throws {
        var engine = try start(.init(mode: .pomodoro, targetSeconds: 10, restSeconds: 0, rounds: 3))
        let signals = engine.tick(at: time(30))
        XCTAssertEqual(engine.snapshot?.effectiveSeconds, 10)
        XCTAssertEqual(engine.snapshot?.status, .paused)
        XCTAssertEqual(engine.snapshot?.pendingPhase, .focus)
        XCTAssertEqual(engine.snapshot?.round, 1)
        try engine.resume(at: time(40))
        engine.tick(at: time(50))
        try engine.resume(at: time(90))
        engine.tick(at: time(100))
        XCTAssertEqual(engine.snapshot?.effectiveSeconds, 30)
        XCTAssertEqual(engine.snapshot?.status, .finished)
        XCTAssertFalse(signals.contains { $0.kind == .restStarted })
    }
    func testPendingPhaseCompatibilityAndValidation() throws {
        var engine = try start(.init(mode: .pomodoro, targetSeconds: 10, restSeconds: 2, rounds: 2))
        let initial = try JSONEncoder().encode(engine.snapshot!)
        let old = try JSONDecoder().decode(FocusSnapshot.self, from: initial)
        XCTAssertNil(old.pendingPhase)
        engine.tick(at: time(10))
        let pending = try JSONDecoder().decode(FocusSnapshot.self, from: JSONEncoder().encode(engine.snapshot!))
        XCTAssertEqual(pending.pendingPhase, .rest)
        XCTAssertNoThrow(try pending.validate())
        var damaged = pending
        damaged.status = .running
        XCTAssertThrowsError(try damaged.validate())
        damaged = pending; damaged.pendingPhase = .focus
        XCTAssertThrowsError(try damaged.validate())
    }
}
