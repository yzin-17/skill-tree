import XCTest
@testable import SkillAtlasCore

@MainActor
final class FocusNoteTests: XCTestCase {
    func testNoteSurvivesRecoveryAndAutomaticFinish() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("skillatlas-note-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID().uuidString; let skill = UUID().uuidString
        let base = Date.now; var reading = ClockReading(monotonic: 0, wall: base)
        let local = try LocalFocusStore(url: directory.appendingPathComponent("focus.sqlite"))
        let original = try FocusCoordinator(store: local, clock: { reading })
        try original.activate(accountId: owner)
        try original.start(skillId: skill, configuration: .init(mode: .countdown, targetSeconds: 60))
        reading = .init(monotonic: 20, wall: base.addingTimeInterval(20)); original.tick()
        try original.updateNote("到点后也应保留的备注")
        let reopened = try LocalFocusStore(url: directory.appendingPathComponent("focus.sqlite"))
        let recovered = try FocusCoordinator(store: reopened, clock: { reading })
        try recovered.activate(accountId: owner)
        XCTAssertEqual(recovered.snapshot?.note, "到点后也应保留的备注")
        XCTAssertEqual(recovered.snapshot?.status, .paused)
        reading = .init(monotonic: 100, wall: base.addingTimeInterval(100)); try recovered.resume()
        reading = .init(monotonic: 150, wall: base.addingTimeInterval(150)); recovered.tick()
        XCTAssertNil(recovered.snapshot)
        XCTAssertEqual(recovered.lastFinished?.submission.note, "到点后也应保留的备注")
        XCTAssertEqual(recovered.lastFinished?.submission.effectiveSeconds, 60)
    }
    func testFailedSaveKeepsOriginalAndMenuFinishDoesNotEraseNote() throws {
        enum Failure: Error { case storage }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("skillatlas-note-fault-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID().uuidString; let local = try LocalFocusStore(url: directory.appendingPathComponent("focus.sqlite"))
        let coordinator = try FocusCoordinator(store: local)
        try coordinator.activate(accountId: owner); try coordinator.start(skillId: UUID().uuidString, configuration: .init())
        try coordinator.updateNote("原始备注")
        local.beforeSave = { throw Failure.storage }
        XCTAssertThrowsError(try coordinator.updateNote("未保存的编辑"))
        XCTAssertEqual(coordinator.snapshot?.note, "原始备注")
        local.beforeSave = nil
        XCTAssertThrowsError(try coordinator.updateNote(String(repeating: "👨‍👩‍👧‍👦", count: 1000)))
        try coordinator.finish()
        XCTAssertEqual(coordinator.lastFinished?.submission.note, "原始备注")
    }
}
