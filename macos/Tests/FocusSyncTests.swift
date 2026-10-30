import XCTest
@testable import SkillAtlasCore

private actor ControlledFocusRemote: FocusRemote {
    var sessions: [String: (String, FocusSubmission, FocusSettlement)] = [:]
    var events: [String: (String, FocusActivitySubmission)] = [:]
    var focusCalls: [(String, String)] = []
    var activityCalls: [String] = []
    var dropFocus = false
    var dropActivity = false
    var focusError: APIError?
    var suspendNextFocus = false
    var focusStarted = false
    var waitingForStart: CheckedContinuation<Void, Never>?
    var release: CheckedContinuation<Void, Never>?
    func configure(dropFocus: Bool = false, dropActivity: Bool = false, error: APIError? = nil, suspend: Bool = false) {
        self.dropFocus = dropFocus; self.dropActivity = dropActivity; focusError = error; suspendNextFocus = suspend
    }
    func waitForStart() async { if !focusStarted { await withCheckedContinuation { waitingForStart = $0 } } }
    func releaseFocus() { release?.resume(); release = nil }
    func uploadFocus(_ value: FocusSubmission, token: String) async throws -> FocusSettlement {
        focusCalls.append((value.id, token))
        if suspendNextFocus {
            suspendNextFocus = false; focusStarted = true; waitingForStart?.resume(); waitingForStart = nil
            await withCheckedContinuation { release = $0 }
        }
        if let focusError { throw focusError }
        if let old = sessions[value.id] {
            guard old.0 == token, old.1 == value else { throw APIError(code: "id_conflict", message: "验收冲突", httpStatus: 409) }
            return old.2
        }
        let prior = sessions.values.filter { $0.0 == token && $0.1.skillId == value.skillId }.reduce(0) { $0 + $1.1.effectiveSeconds }
        let progress = makeProgress(skill: value.skillId, seconds: prior + value.effectiveSeconds)
        let record = FocusRecord(id: value.id, skillId: value.skillId, taskId: value.taskId, mode: value.mode, targetSeconds: value.targetSeconds,
                                 effectiveSeconds: value.effectiveSeconds, startedAt: value.startedAt, endedAt: value.endedAt, note: value.note, source: value.source,
                                 pomodoroRounds: value.pomodoroRounds, version: 1, createdAt: .now, invalidatedAt: nil, clockAdjusted: false)
        let result = FocusSettlement(session: record, awardedXp: Int64((prior + value.effectiveSeconds) / 60 - prior / 60), settledProgress: progress)
        sessions[value.id] = (token, value, result)
        if dropFocus { dropFocus = false; throw URLError(.networkConnectionLost) }
        return result
    }
    func uploadActivity(_ value: FocusActivitySubmission, token: String) async throws -> String {
        activityCalls.append(value.id)
        if let old = events[value.id] {
            guard old.0 == token && old.1 == value else { throw APIError(code: "id_conflict", message: "验收事件冲突", httpStatus: 409) }
            return value.id
        }
        events[value.id] = (token, value)
        if dropActivity { dropActivity = false; throw URLError(.networkConnectionLost) }
        return value.id
    }
    func fetchProgress(token: String) async throws -> [SkillProgress] {
        let owned = sessions.values.filter { $0.0 == token }.map(\.1)
        return Dictionary(grouping: owned, by: \.skillId).map { makeProgress(skill: $0.key, seconds: $0.value.reduce(0) { $0 + $1.effectiveSeconds }) }
    }
    private func makeProgress(skill: String, seconds: Int) -> SkillProgress {
        let xp = Int64(seconds / 60)
        return SkillProgress(skillId: skill, totalFocusSeconds: Int64(seconds), timeXp: xp, taskBonusXp: 0, totalXp: xp, level: 1 + xp / 60, xpCurrent: xp % 60, xpRequired: 60, unlocked: true, missingPrerequisites: [])
    }
}

@MainActor
final class FocusSyncTests: XCTestCase {
    func location() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("skillatlas-sync-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("focus.sqlite")
    }
    @discardableResult
    func queue(_ store: LocalFocusStore, owner: String, skill: String, seconds: Int = 70, events: Bool = true) throws -> String {
        let base = Date(timeIntervalSince1970: 1_798_000_000)
        var engine = FocusEngine()
        let started = try engine.start(accountId: owner, skillId: skill, configuration: .init(), at: .init(monotonic: 0, wall: base))
        if events { try store.commit(accountId: owner, snapshot: engine.snapshot, signals: started) }
        let ended = try engine.finish(at: .init(monotonic: Double(seconds), wall: base.addingTimeInterval(Double(seconds))))
        let submission = try FocusSubmission(snapshot: XCTUnwrap(engine.snapshot))
        try store.commit(accountId: owner, snapshot: nil, signals: events ? ended : [], finished: submission)
        return submission.id
    }
    func testLostResponsesRestartAndStableReplays() async throws {
        let url = location(), owner = UUID().uuidString, skill = UUID().uuidString
        let local = try LocalFocusStore(url: url); let id = try queue(local, owner: owner, skill: skill)
        let remote = ControlledFocusRemote(); await remote.configure(dropFocus: true, dropActivity: true)
        let identity = SyncIdentity(accountId: owner, token: "isolated-test-session")
        let sync = FocusSynchronizer(local: local, remote: remote, identity: { identity }); try sync.activate()
        await sync.synchronize(force: true)
        XCTAssertEqual(sync.pendingCount, 1); XCTAssertEqual(sync.activityCount, 2)
        await sync.synchronize(force: true)
        XCTAssertEqual(sync.pendingCount, 1); XCTAssertEqual(sync.activityCount, 0)
        XCTAssertEqual(try local.record(accountId: owner, id: id)?.state, .pending)
        let reopened = try LocalFocusStore(url: url)
        let restored = FocusSynchronizer(local: reopened, remote: remote, identity: { identity }); try restored.activate()
        await restored.synchronize(force: true)
        XCTAssertEqual(restored.pendingCount, 0); XCTAssertEqual(restored.records.first?.state, .confirmed)
        XCTAssertEqual(restored.progress.first?.timeXp, 1)
        let sessions = await remote.sessions, events = await remote.events, calls = await remote.focusCalls
        XCTAssertEqual(sessions.count, 1); XCTAssertEqual(events.count, 2); XCTAssertEqual(calls.map(\.0), [id, id])
        let cached: [SkillProgress]? = try reopened.cache(accountId: owner, topic: .progress)
        XCTAssertEqual(cached?.first?.totalFocusSeconds, 70)
        let other: [SkillProgress]? = try reopened.cache(accountId: UUID().uuidString, topic: .progress)
        XCTAssertNil(other)
    }
    func testAccountChangeDuringUploadNeverAppliesOtherIdentity() async throws {
        let local = try LocalFocusStore(url: location()); let first = UUID().uuidString, second = UUID().uuidString
        let firstID = try queue(local, owner: first, skill: UUID().uuidString, seconds: 60, events: false)
        let secondSkill = UUID().uuidString; let secondID = try queue(local, owner: second, skill: secondSkill, seconds: 120, events: false)
        var identity: SyncIdentity? = .init(accountId: first, token: "first-session")
        let remote = ControlledFocusRemote(); await remote.configure(suspend: true)
        let sync = FocusSynchronizer(local: local, remote: remote, identity: { identity }); try sync.activate()
        let work = Task { await sync.synchronize(force: true) }
        await remote.waitForStart()
        identity = .init(accountId: second, token: "second-session"); try sync.activate()
        XCTAssertTrue(sync.progress.isEmpty); XCTAssertEqual(sync.records.map(\.id), [secondID])
        await remote.releaseFocus(); await work.value
        XCTAssertEqual(try local.record(accountId: first, id: firstID)?.state, .pending)
        XCTAssertEqual(try local.record(accountId: second, id: secondID)?.state, .confirmed)
        XCTAssertEqual(sync.progress.map(\.skillId), [secondSkill])
        let calls = await remote.focusCalls
        XCTAssertEqual(calls.map(\.1), ["first-session", "second-session"])
        identity = .init(accountId: first, token: "first-session"); try sync.activate(); await sync.synchronize(force: true)
        XCTAssertEqual(try local.record(accountId: first, id: firstID)?.state, .confirmed)
        XCTAssertEqual(sync.progress.first?.timeXp, 1)
    }
    func testConflictRetentionAuthenticationAndServerFailure() async throws {
        let local = try LocalFocusStore(url: location()), owner = UUID().uuidString
        let id = try queue(local, owner: owner, skill: UUID().uuidString, events: false)
        var identity: SyncIdentity? = .init(accountId: owner, token: "isolated-session")
        let remote = ControlledFocusRemote(); await remote.configure(error: APIError(code: "id_conflict", message: "原记录冲突", httpStatus: 409))
        let sync = FocusSynchronizer(local: local, remote: remote, identity: { identity }); try sync.activate()
        await sync.synchronize(force: true)
        XCTAssertEqual(sync.blockedCount, 1); XCTAssertEqual(try local.record(accountId: owner, id: id)?.failure, "原记录冲突")
        await remote.configure(error: APIError(code: "internal", message: "服务暂不可用", httpStatus: 500))
        await sync.synchronize(force: true); XCTAssertEqual(sync.pendingCount, 1); XCTAssertEqual(sync.blockedCount, 0)
        var expired: String?
        sync.onAuthenticationFailure = { value in expired = value; identity = nil; try? sync.activate() }
        await remote.configure(error: APIError(code: "unauthenticated", message: "重新登录", httpStatus: 401))
        await sync.synchronize(force: true)
        XCTAssertEqual(expired, owner); XCTAssertTrue(sync.records.isEmpty)
        XCTAssertEqual(try local.record(accountId: owner, id: id)?.state, .pending)
    }
}
