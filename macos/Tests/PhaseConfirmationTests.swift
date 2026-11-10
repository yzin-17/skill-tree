import XCTest
@testable import SkillAtlasCore

@MainActor
final class PhaseConfirmationTests: XCTestCase {
    func testWaitingPersistsRecoversAndOnlyConfirmationStartsNextPhase() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = try LocalFocusStore(url: directory.appendingPathComponent("focus.sqlite"))
        var elapsed: Double = 0
        let clock: () -> ClockReading = { .init(monotonic: elapsed, wall: Date(timeIntervalSince1970: 1_798_000_000 + elapsed)) }
        let focus = try FocusCoordinator(store: local, clock: clock)
        let owner = UUID().uuidString
        try focus.activate(accountId: owner)
        try focus.start(skillId: UUID().uuidString, configuration: .init(mode: .pomodoro, targetSeconds: 10, restSeconds: 3, rounds: 2))
        elapsed = 100; focus.tick()
        let restID = try XCTUnwrap(focus.snapshot?.phaseConfirmationID)
        XCTAssertEqual(try local.active(accountId: owner)?.pendingPhase, .rest)
        XCTAssertEqual(focus.snapshot?.effectiveSeconds, 10)
        let recovered = try FocusCoordinator(store: local, clock: clock)
        try recovered.activate(accountId: owner)
        elapsed = 1000; recovered.tick()
        XCTAssertEqual(recovered.snapshot?.phaseConfirmationID, restID)
        XCTAssertEqual(recovered.snapshot?.effectiveSeconds, 10)
        try recovered.handle(.willSleep)
        XCTAssertEqual(recovered.snapshot?.phaseConfirmationID, restID)
        try recovered.confirmPhase(id: restID)
        XCTAssertEqual(recovered.snapshot?.phase, .rest)
        XCTAssertEqual(recovered.snapshot?.phaseElapsed, 0)
        XCTAssertEqual(recovered.snapshot?.status, .running)
        elapsed = 1003; recovered.tick()
        let nextID = try XCTUnwrap(recovered.snapshot?.phaseConfirmationID)
        try recovered.confirmPhase(id: restID)
        XCTAssertEqual(recovered.snapshot?.phaseConfirmationID, nextID)
        elapsed = 2000; recovered.tick()
        XCTAssertEqual(recovered.snapshot?.effectiveSeconds, 10)
        try recovered.confirmPhase(id: nextID)
        XCTAssertEqual(recovered.snapshot?.round, 2)
        elapsed = 2010; recovered.tick()
        XCTAssertNil(recovered.snapshot)
        XCTAssertEqual(recovered.lastFinished?.submission.effectiveSeconds, 20)
    }

    func testSaveFailureKeepsBoundaryOrConfirmationUncommitted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = try LocalFocusStore(url: directory.appendingPathComponent("focus.sqlite"))
        var elapsed: Double = 0
        let focus = try FocusCoordinator(store: local, clock: { .init(monotonic: elapsed, wall: Date(timeIntervalSince1970: 1_798_000_000 + elapsed)) })
        try focus.activate(accountId: UUID().uuidString)
        var signals: [FocusSignal] = []
        focus.onSignals = { signals += $0 }
        try focus.start(skillId: UUID().uuidString, configuration: .init(mode: .pomodoro, targetSeconds: 10, restSeconds: 3, rounds: 2))
        signals.removeAll()
        local.beforeSave = { throw CocoaError(.fileWriteUnknown) }
        elapsed = 20; focus.tick()
        XCTAssertEqual(focus.snapshot?.status, .running)
        XCTAssertNil(focus.snapshot?.pendingPhase)
        XCTAssertTrue(signals.isEmpty)
        local.beforeSave = nil; focus.tick()
        let id = try XCTUnwrap(focus.snapshot?.phaseConfirmationID)
        XCTAssertEqual(signals.map(\.kind), [.phaseEnded, .paused])
        local.beforeSave = { throw CocoaError(.fileWriteUnknown) }
        XCTAssertThrowsError(try focus.confirmPhase(id: id))
        XCTAssertEqual(focus.snapshot?.phaseConfirmationID, id)
        local.beforeSave = nil
        try focus.confirmPhase(id: id, finish: true)
        XCTAssertNil(focus.snapshot)
        XCTAssertEqual(focus.lastFinished?.submission.effectiveSeconds, 10)
        try focus.start(skillId: UUID().uuidString, configuration: .init(mode: .pomodoro, targetSeconds: 10, rounds: 2))
        try focus.confirmPhase(id: id, finish: true)
        XCTAssertNotNil(focus.snapshot)
    }

    func testAccountChangeKeepsPendingPhaseIsolated() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = try LocalFocusStore(url: directory.appendingPathComponent("focus.sqlite"))
        var elapsed: Double = 0
        let focus = try FocusCoordinator(store: local, clock: { .init(monotonic: elapsed, wall: Date(timeIntervalSince1970: 1_798_000_000 + elapsed)) })
        let firstOwner = UUID().uuidString
        try focus.activate(accountId: firstOwner)
        try focus.start(skillId: UUID().uuidString, configuration: .init(mode: .pomodoro, targetSeconds: 1, rounds: 2))
        elapsed = 1; focus.tick()
        let pendingID = try XCTUnwrap(focus.snapshot?.phaseConfirmationID)
        try focus.activate(accountId: UUID().uuidString)
        try focus.start(skillId: UUID().uuidString, configuration: .init(mode: .countdown, targetSeconds: 10))
        let otherSession = focus.snapshot?.id
        try focus.confirmPhase(id: pendingID, finish: true)
        XCTAssertEqual(focus.snapshot?.id, otherSession)
        try focus.activate(accountId: firstOwner)
        XCTAssertEqual(focus.snapshot?.phaseConfirmationID, pendingID)
        XCTAssertEqual(focus.snapshot?.status, .paused)
    }
}
