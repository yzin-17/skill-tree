import XCTest
@testable import SkillAtlasCore

@MainActor
final class FocusPersistenceTests: XCTestCase {
    let owner = UUID().uuidString
    let skill = UUID().uuidString
    let base = Date(timeIntervalSince1970: 1_798_000_000)
    func reading(_ time: Double) -> ClockReading { .init(monotonic: time, wall: base.addingTimeInterval(time)) }
    func location() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("skillatlas-persistence-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("focus.sqlite")
    }
    func testFinishAndEventsAreDurableAndIdempotent() async throws {
        let url = try location(); let store = try LocalFocusStore(url: url)
        var engine = FocusEngine()
        let started = try engine.start(accountId: owner, skillId: skill, configuration: .init(), at: reading(0))
        try store.commit(accountId: owner, snapshot: engine.snapshot, signals: started)
        let identifier = try XCTUnwrap(engine.snapshot?.id)
        let paused = try engine.pause(at: reading(20.5))
        try store.commit(accountId: owner, snapshot: engine.snapshot, signals: paused)
        let restored = try LocalFocusStore(url: url)
        XCTAssertEqual(try restored.active(accountId: owner)?.id, identifier)
        XCTAssertEqual(try restored.active(accountId: owner)?.effectiveElapsed, 20.5)
        let resumed = try engine.resume(at: reading(100))
        try store.commit(accountId: owner, snapshot: engine.snapshot, signals: resumed)
        let ended = try engine.finish(at: reading(150.5))
        let submission = try FocusSubmission(snapshot: XCTUnwrap(engine.snapshot))
        try store.commit(accountId: owner, snapshot: nil, signals: ended, finished: submission)
        try store.commit(accountId: owner, snapshot: nil, signals: ended, finished: submission)
        let reopened = try LocalFocusStore(url: url)
        XCTAssertNil(try reopened.active(accountId: owner))
        let records = try reopened.records(accountId: owner)
        XCTAssertEqual(records.count, 1); XCTAssertEqual(records[0].id, identifier)
        XCTAssertEqual(records[0].submission.effectiveSeconds, 71)
        XCTAssertEqual(records[0].state, .pending)
        let events = try reopened.activities(accountId: owner)
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(Set(events.map { $0.submission.type }), Set(["focus.started", "focus.paused", "focus.resumed", "focus.ended"]))
        XCTAssertTrue(try reopened.records(accountId: UUID().uuidString).isEmpty)
        XCTAssertThrowsError(try reopened.fail(accountId: UUID().uuidString, id: identifier, message: "测试", blocked: false))
    }
    func testFailedCommitPreservesActiveWithoutPartialQueue() async throws {
        enum Failure: Error { case storage }
        let url = try location(); let store = try LocalFocusStore(url: url)
        var engine = FocusEngine()
        let started = try engine.start(accountId: owner, skillId: skill, configuration: .init(), at: reading(0))
        try store.commit(accountId: owner, snapshot: engine.snapshot, signals: started)
        let ended = try engine.finish(at: reading(42)); let submission = try FocusSubmission(snapshot: XCTUnwrap(engine.snapshot))
        store.beforeSave = { throw Failure.storage }
        XCTAssertThrowsError(try store.commit(accountId: owner, snapshot: nil, signals: ended, finished: submission))
        let reopened = try LocalFocusStore(url: url)
        XCTAssertNotNil(try reopened.active(accountId: owner))
        XCTAssertTrue(try reopened.records(accountId: owner).isEmpty)
        XCTAssertEqual(try reopened.activities(accountId: owner).count, 1)
        store.beforeSave = nil
        try store.commit(accountId: owner, snapshot: nil, signals: ended, finished: submission)
        XCTAssertEqual(try store.records(accountId: owner).count, 1)
    }
    func testAccountPartitionSingleRunningAndConflictingPayload() async throws {
        let store = try LocalFocusStore(url: location()); var first = FocusEngine(); var second = FocusEngine()
        let other = UUID().uuidString
        let a = try first.start(accountId: owner, skillId: skill, configuration: .init(), at: reading(0))
        let b = try second.start(accountId: other, skillId: skill, configuration: .init(), at: reading(0))
        try store.commit(accountId: owner, snapshot: first.snapshot, signals: a)
        XCTAssertThrowsError(try store.commit(accountId: other, snapshot: second.snapshot, signals: b))
        let paused = try first.pause(at: reading(10)); try store.commit(accountId: owner, snapshot: first.snapshot, signals: paused)
        try store.commit(accountId: other, snapshot: second.snapshot, signals: b)
        let end = try first.finish(at: reading(20)); var submission = try FocusSubmission(snapshot: XCTUnwrap(first.snapshot))
        try store.commit(accountId: owner, snapshot: nil, signals: end, finished: submission)
        submission.note = "冲突内容"
        XCTAssertThrowsError(try store.commit(accountId: owner, snapshot: nil, signals: end, finished: submission))
        XCTAssertEqual(try store.records(accountId: owner).first?.submission.note, "")
        XCTAssertTrue(try store.records(accountId: other).isEmpty)
        XCTAssertNotNil(try store.active(accountId: other))
    }
}
