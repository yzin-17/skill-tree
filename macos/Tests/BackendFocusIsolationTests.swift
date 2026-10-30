import Foundation
import Testing
@testable import SkillAtlasCore

@Suite @MainActor
struct BackendFocusIsolationTests {
    @Test func sameAccountOnTwoBackendsKeepsSeparateSnapshotsAndQueues() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillatlas-backend-scope-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try BackendAddress("https://localhost:8447")
        let a = BackendScope(address: original, defaultAddress: original)
        let b = BackendScope(address: try BackendAddress("https://127.0.0.1:8447"), defaultAddress: original)
        let old = try LocalFocusStore(url: a.directory(in: root).appendingPathComponent("focus.sqlite"))
        let other = try LocalFocusStore(url: b.directory(in: root).appendingPathComponent("focus.sqlite"))
        let account = UUID().uuidString, skill = UUID().uuidString
        var now = ClockReading(monotonic: 0, wall: Date(timeIntervalSince1970: 1_798_000_000))
        let coordinator = try FocusCoordinator(store: old, clock: { now })
        try coordinator.activate(accountId: account); try coordinator.start(skillId: skill, configuration: .init())
        now = .init(monotonic: 45, wall: now.wall.addingTimeInterval(45)); try coordinator.pause()
        let id = coordinator.snapshot?.id
        #expect(try old.active(accountId: account)?.effectiveSeconds == 45)
        #expect(try other.active(accountId: account) == nil && other.activities(accountId: account).isEmpty)
        #expect(try other.records(accountId: account).isEmpty)
        let returned = try FocusCoordinator(store: old, clock: { now }); try returned.activate(accountId: account)
        #expect(returned.snapshot?.id == id && returned.snapshot?.status == .paused)
        try returned.finish()
        #expect(try old.records(accountId: account).count == 1)
        #expect(try other.records(accountId: account).isEmpty && other.activities(accountId: account).isEmpty)
    }

    @Test func pauseFailureDoesNotAcknowledgeSavedSnapshot() throws {
        enum Failure: Error { case storage }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skillatlas-backend-pause-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try LocalFocusStore(url: root.appendingPathComponent("focus.sqlite"))
        let account = UUID().uuidString
        let coordinator = try FocusCoordinator(store: local)
        try coordinator.activate(accountId: account)
        try coordinator.start(skillId: UUID().uuidString, configuration: .init())
        local.beforeSave = { throw Failure.storage }
        #expect(throws: Failure.self) { try coordinator.pause() }
        #expect(coordinator.snapshot?.status == .running)
        #expect(try local.active(accountId: account)?.status == .running)
    }
}
