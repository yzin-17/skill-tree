import XCTest
@testable import SkillAtlasCore

@MainActor
final class FocusLifecycleTests: XCTestCase {
    func testSleepExitAndAccountRestoreKeepObservedTime() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("skillatlas-lifecycle-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalFocusStore(url: directory.appendingPathComponent("focus.sqlite"))
        let first = UUID().uuidString, second = UUID().uuidString, skill = UUID().uuidString
        let base = Date(timeIntervalSince1970: 1_798_000_000)
        var now = ClockReading(monotonic: 0, wall: base)
        let coordinator = try FocusCoordinator(store: store, clock: { now })
        try coordinator.activate(accountId: first); try coordinator.start(skillId: skill, configuration: .init())
        let id = coordinator.snapshot?.id
        now = .init(monotonic: 20, wall: base.addingTimeInterval(20)); try coordinator.handle(.willSleep)
        now = .init(monotonic: 1000, wall: base.addingTimeInterval(1000)); coordinator.tick()
        XCTAssertEqual(coordinator.snapshot?.effectiveSeconds, 20)
        XCTAssertEqual(coordinator.snapshot?.status, .paused)
        try coordinator.activate(accountId: second)
        XCTAssertNil(coordinator.snapshot)
        try coordinator.start(skillId: skill, configuration: .init(mode: .countdown, targetSeconds: 30))
        now = .init(monotonic: 1010, wall: base.addingTimeInterval(1010)); try coordinator.handle(.willTerminate)
        let restarted = try FocusCoordinator(store: LocalFocusStore(url: directory.appendingPathComponent("focus.sqlite")), clock: { now })
        try restarted.activate(accountId: first)
        XCTAssertEqual(restarted.snapshot?.id, id)
        XCTAssertEqual(restarted.snapshot?.effectiveSeconds, 20)
        try restarted.resume()
        now = .init(monotonic: 1025, wall: base.addingTimeInterval(-3600)); try restarted.finish()
        XCTAssertNil(restarted.snapshot)
        XCTAssertEqual(restarted.lastFinished?.submission.effectiveSeconds, 35)
        XCTAssertEqual(try store.active(accountId: second)?.effectiveSeconds, 10)
    }
    func testStorageFailureDoesNotAcknowledgeCompletionOrNotify() async throws {
        enum Failure: Error { case simulated }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("skillatlas-finish-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LocalFocusStore(url: directory.appendingPathComponent("focus.sqlite"))
        var now = ClockReading(monotonic: 0, wall: Date(timeIntervalSince1970: 1_798_000_000))
        let coordinator = try FocusCoordinator(store: store, clock: { now }); var finishedSignals = 0
        coordinator.onSignals = { finishedSignals += $0.filter { $0.kind == .finished }.count }
        try coordinator.activate(accountId: UUID().uuidString)
        try coordinator.start(skillId: UUID().uuidString, configuration: .init(mode: .countdown, targetSeconds: 5))
        store.beforeSave = { throw Failure.simulated }
        now = .init(monotonic: 10, wall: now.wall.addingTimeInterval(10)); coordinator.tick()
        XCTAssertNotNil(coordinator.persistenceError)
        XCTAssertEqual(coordinator.snapshot?.status, .running)
        XCTAssertNil(coordinator.lastFinished); XCTAssertEqual(finishedSignals, 0)
        store.beforeSave = nil; coordinator.tick()
        XCTAssertNil(coordinator.snapshot); XCTAssertEqual(coordinator.lastFinished?.submission.effectiveSeconds, 5)
        XCTAssertEqual(finishedSignals, 1)
        coordinator.tick(); try coordinator.finish(); XCTAssertEqual(finishedSignals, 1)
    }
}
