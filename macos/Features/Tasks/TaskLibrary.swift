import SwiftUI

@MainActor @Observable
final class TaskLibrary {
    private(set) var items: [TaskRecord] = []
    private(set) var isLoading = false
    var errorMessage: String?
    private(set) var commands: [DurableTaskCommand] = []
    private(set) var actingTaskIds: Set<String> = []
    private let account: AccountController
    private let local: LocalFocusStore?
    init(account: AccountController, local: LocalFocusStore?) { self.account = account; self.local = local }
    func clear() { items = []; commands = []; errorMessage = nil; isLoading = false; actingTaskIds = [] }
    func restoreCache() throws {
        clear()
        if let owner = account.user?.id { items = try local?.cache(accountId: owner, topic: .tasks) ?? []; commands = try local?.taskCommands(accountId: owner) ?? [] }
    }
    var sorted: [TaskRecord] {
        items.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            if $0.dueAt != $1.dueAt { return ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            return $0.createdAt > $1.createdAt
        }
    }
    func refresh() async {
        guard let owner = account.user?.id else { return }
        isLoading = true
        defer { if account.user?.id == owner { isLoading = false } }
        do {
            let values: [TaskRecord] = try await account.request("/v1/tasks")
            items = values; errorMessage = nil; persist()
        } catch { if account.user?.id == owner { errorMessage = error.localizedDescription } }
    }
    @discardableResult
    func save(_ input: TaskWrite) async throws -> TaskRecord {
        try input.validate()
        let value: TaskRecord = try await account.request(input.version == 0 ? "/v1/tasks" : "/v1/tasks/\(input.id)", method: input.version == 0 ? "POST" : "PATCH", body: APIClient.body(input))
        apply(value); return value
    }
    @discardableResult
    func reload(_ id: String) async throws -> TaskRecord {
        let value: TaskRecord = try await account.request("/v1/tasks/\(id)"); apply(value); return value
    }
    func apply(_ value: TaskRecord) { items.removeAll { $0.id == value.id }; items.append(value); errorMessage = nil; persist() }
    private func persist() {
        guard let owner = account.user?.id else { return }
        do { try local?.saveCache(items, accountId: owner, topic: .tasks) }
        catch { errorMessage = "服务端数据已读取，但本机缓存保存失败：\(error.localizedDescription)" }
    }
    func history(_ taskId: String) async throws -> TaskAttemptHistory { try await account.request("/v1/tasks/\(taskId)/attempts") }
    func conclude(_ task: TaskRecord, result: String, reason: String) async throws {
        let input = ConclusionWrite(attemptNo: task.currentAttemptNo, version: task.version, result: result, reason: reason)
        try await execute(makeCommand(id: input.id, taskId: task.id, kind: .conclude, path: "/v1/tasks/\(task.id)/attempts", body: APIClient.body(input)))
    }
    func retry(_ task: TaskRecord) async throws {
        let input = RetryWrite(attemptNo: task.currentAttemptNo, version: task.version)
        try await execute(makeCommand(id: input.id, taskId: task.id, kind: .retry, path: "/v1/tasks/\(task.id)/retry", body: APIClient.body(input)))
    }
    func reverse(_ attempt: TaskAttemptRecord, reason: String) async throws {
        let input = ReversalWrite(reason: reason)
        try await execute(makeCommand(id: input.id, taskId: attempt.taskId, kind: .reverse, path: "/v1/task-attempts/\(attempt.id)/reverse", body: APIClient.body(input)))
    }
    private func makeCommand(id: String, taskId: String, kind: TaskCommandKind, path: String, body: Data) throws -> DurableTaskCommand {
        guard let owner = account.user?.id, local != nil else { throw APIError(code: "local_store", message: "请先恢复本机记录存储，再进行结算。") }
        return .init(id: id, accountId: owner, taskId: taskId, kind: kind, path: path, payload: body)
    }
    func execute(_ command: DurableTaskCommand) async throws {
        guard let local, command.accountId == account.user?.id else { throw FocusEngineError.invalidIdentity }
        guard !actingTaskIds.contains(command.taskId) else { return }
        try local.prepareCommand(command); commands = try local.taskCommands(accountId: command.accountId)
        actingTaskIds.insert(command.taskId)
        defer { if command.accountId == account.user?.id { actingTaskIds.remove(command.taskId) } }
        do {
            let task: TaskRecord
            if command.kind == .retry { task = try await account.request(command.path, method: "POST", body: command.payload) }
            else {
                let result: TaskSettlement = try await account.request(command.path, method: "POST", body: command.payload)
                guard (command.kind == .conclude ? result.attempt.id : result.reversal?.id) == command.id else { throw APIError(code: "confirmation_mismatch", message: "结算确认不一致，原请求已保留。") }
                task = result.task
            }
            guard task.id == command.taskId else { throw APIError(code: "confirmation_mismatch", message: "任务确认不一致，原请求已保留。") }
            try local.confirmCommand(accountId: command.accountId, id: command.id)
            commands = try local.taskCommands(accountId: command.accountId); apply(task)
            do { _ = try await reload(task.id) } catch { errorMessage = "结果已确认，最新任务状态暂时无法刷新。" }
        } catch {
            let api = error as? APIError
            let rejected = api?.httpStatus.map { (400..<500).contains($0) && ![401, 408, 429].contains($0) } ?? false
            try local.failCommand(accountId: command.accountId, id: command.id, message: error.localizedDescription, rejected: rejected)
            if account.user?.id == command.accountId { commands = try local.taskCommands(accountId: command.accountId); errorMessage = error.localizedDescription }
            throw error
        }
    }
}
