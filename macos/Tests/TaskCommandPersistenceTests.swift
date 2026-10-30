import XCTest
@testable import SkillAtlasCore

@MainActor
final class TaskCommandPersistenceTests: XCTestCase {
    let owner = UUID().uuidString.lowercased()
    let task = UUID().uuidString.lowercased()
    func location() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skillatlas-task-command-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent("focus.sqlite")
    }
    func command(_ id: String = UUID().uuidString.lowercased(), result: String = "success") throws -> DurableTaskCommand {
        let input = ConclusionWrite(id: id, attemptNo: 1, version: 1, result: result, reason: "")
        return .init(id: id, accountId: owner, taskId: task, kind: .conclude, path: "/v1/tasks/\(task)/attempts", payload: try APIClient.body(input))
    }
    func testUncertainResponseSurvivesRestartAndKeepsSamePayload() throws {
        let url = try location(); let local = try LocalFocusStore(url: url); let original = try command()
        try local.prepareCommand(original)
        try local.failCommand(accountId: owner, id: original.id, message: "连接中断", rejected: false)
        let reopened = try LocalFocusStore(url: url)
        let pending = try XCTUnwrap(reopened.taskCommands(accountId: owner).first)
        XCTAssertEqual(pending.id, original.id); XCTAssertEqual(pending.payload, original.payload)
        XCTAssertTrue(try reopened.taskCommands(accountId: UUID().uuidString).isEmpty)
        try reopened.prepareCommand(pending)
        XCTAssertThrowsError(try reopened.prepareCommand(command(original.id, result: "failed")))
        XCTAssertThrowsError(try reopened.prepareCommand(command()))
        XCTAssertThrowsError(try reopened.confirmCommand(accountId: UUID().uuidString, id: original.id))
        try reopened.confirmCommand(accountId: owner, id: original.id)
        XCTAssertTrue(try reopened.taskCommands(accountId: owner).isEmpty)
        try reopened.prepareCommand(command())
    }
    func testStorageFailureDoesNotLosePendingAndRejectedIsRetained() throws {
        enum Failure: Error { case storage }
        let local = try LocalFocusStore(url: location()); let original = try command()
        local.beforeSave = { throw Failure.storage }
        XCTAssertThrowsError(try local.prepareCommand(original))
        XCTAssertTrue(try local.taskCommands(accountId: owner).isEmpty)
        local.beforeSave = nil; try local.prepareCommand(original)
        local.beforeSave = { throw Failure.storage }
        XCTAssertThrowsError(try local.confirmCommand(accountId: owner, id: original.id))
        XCTAssertEqual(try local.taskCommands(accountId: owner).count, 1)
        local.beforeSave = nil
        try local.failCommand(accountId: owner, id: original.id, message: "版本冲突", rejected: true)
        XCTAssertTrue(try local.taskCommands(accountId: owner).isEmpty)
        XCTAssertTrue(try XCTUnwrap(local.taskCommands(accountId: owner, includeRejected: true).first).rejected)
        try local.prepareCommand(command())
        XCTAssertEqual(try local.taskCommands(accountId: owner, includeRejected: true).count, 2)
    }
}
