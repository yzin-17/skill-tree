import Foundation
import SwiftData

@MainActor
public final class LocalFocusStore {
    private let container: ModelContainer
    private let context: ModelContext
    public var beforeSave: (() throws -> Void)?

    public init(url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let schema = Schema([ActiveFocusRow.self, PendingFocusRow.self, PendingActivityRow.self, AccountCacheRow.self, PendingTaskCommandRow.self])
        let configuration = ModelConfiguration("SkillAtlasFocus", schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container); context.autosaveEnabled = false
    }
    private func save(_ operation: () throws -> Void) throws {
        do { try operation(); try beforeSave?(); try context.save() }
        catch { context.rollback(); throw error }
    }
    private func activeRow(_ owner: String) throws -> ActiveFocusRow? {
        try context.fetch(FetchDescriptor<ActiveFocusRow>(predicate: #Predicate { $0.accountId == owner })).first
    }
    private func focusRow(_ id: String, _ owner: String) throws -> PendingFocusRow? {
        let row = try context.fetch(FetchDescriptor<PendingFocusRow>(predicate: #Predicate { $0.id == id })).first
        if let row, row.accountId != owner { throw APIError(code: "local_owner", message: "本地记录属于其他账号。") }
        return row
    }
    private func activityRow(_ id: String, _ owner: String) throws -> PendingActivityRow? {
        let row = try context.fetch(FetchDescriptor<PendingActivityRow>(predicate: #Predicate { $0.id == id })).first
        if let row, row.accountId != owner { throw APIError(code: "local_owner", message: "本地事件属于其他账号。") }
        return row
    }
    public func active(accountId: String) throws -> FocusSnapshot? {
        guard let row = try activeRow(accountId) else { return nil }
        let value = try JSONDecoder().decode(FocusSnapshot.self, from: row.payload)
        try value.validate()
        guard value.accountId == accountId else { throw FocusEngineError.damagedSnapshot }
        return value
    }
    public func activeSnapshots() throws -> [FocusSnapshot] {
        try context.fetch(FetchDescriptor<ActiveFocusRow>()).map { row in
            let snapshot = try JSONDecoder().decode(FocusSnapshot.self, from: row.payload)
            try snapshot.validate()
            guard snapshot.accountId == row.accountId else { throw FocusEngineError.damagedSnapshot }
            return snapshot
        }
    }
    public func commit(accountId: String, snapshot: FocusSnapshot?, signals: [FocusSignal], finished: FocusSubmission? = nil) throws {
        guard UUID(uuidString: accountId) != nil, snapshot == nil || snapshot?.accountId == accountId,
              signals.allSatisfy({ $0.accountId == accountId }) else { throw FocusEngineError.invalidIdentity }
        if let snapshot { try snapshot.validate(); if snapshot.status == .finished { throw FocusEngineError.invalidState } }
        if let finished { try finished.validate() }
        try save {
            if let snapshot {
                if let old = try active(accountId: accountId), old.id != snapshot.id { throw FocusEngineError.alreadyActive }
                if snapshot.status == .running {
                    if try activeSnapshots().contains(where: { $0.accountId != accountId && $0.status == .running }) { throw FocusEngineError.alreadyActive }
                }
                let data = try JSONEncoder().encode(snapshot)
                if let row = try activeRow(accountId) { row.payload = data; row.updatedAt = .now }
                else { context.insert(ActiveFocusRow(accountId: accountId, payload: data)) }
            }
            if let finished {
                let data = try APIClient.body(finished)
                if let existing = try focusRow(finished.id, accountId) {
                    guard existing.payload == data else { throw APIError(code: "local_conflict", message: "同一会话的本地内容发生冲突，原记录已保留。") }
                } else { context.insert(PendingFocusRow(id: finished.id, accountId: accountId, payload: data)) }
                if let row = try activeRow(accountId), try JSONDecoder().decode(FocusSnapshot.self, from: row.payload).id == finished.id { context.delete(row) }
            }
            for signal in signals where signal.isLifecycleEvent {
                let data = try APIClient.body(FocusActivitySubmission(signal))
                if let existing = try activityRow(signal.id, accountId) {
                    guard existing.payload == data else { throw APIError(code: "local_conflict", message: "同一事件的本地内容发生冲突，原记录已保留。") }
                } else { context.insert(PendingActivityRow(id: signal.id, accountId: accountId, payload: data)) }
            }
        }
    }
    public func records(accountId: String) throws -> [LocalFocusRecord] {
        let descriptor = FetchDescriptor<PendingFocusRow>(predicate: #Predicate { $0.accountId == accountId }, sortBy: [SortDescriptor(\.createdAt)])
        return try context.fetch(descriptor).map { row in
            guard let state = LocalSyncState(rawValue: row.state) else { throw FocusEngineError.damagedSnapshot }
            return LocalFocusRecord(id: row.id, accountId: row.accountId, submission: try APIClient.decoder().decode(FocusSubmission.self, from: row.payload), state: state, failure: row.failure,
                                    confirmation: try row.confirmation.map { try APIClient.decoder().decode(FocusSettlement.self, from: $0) })
        }
    }
    public func record(accountId: String, id: String) throws -> LocalFocusRecord? {
        guard let row = try focusRow(id, accountId), let state = LocalSyncState(rawValue: row.state) else { return nil }
        return LocalFocusRecord(id: row.id, accountId: row.accountId, submission: try APIClient.decoder().decode(FocusSubmission.self, from: row.payload), state: state, failure: row.failure,
                                confirmation: try row.confirmation.map { try APIClient.decoder().decode(FocusSettlement.self, from: $0) })
    }
    public func cache<T: Codable & Sendable>(accountId: String, topic: CacheTopic, as type: T.Type = T.self) throws -> T? {
        let key = accountId + ":" + topic.rawValue
        guard let row = try context.fetch(FetchDescriptor<AccountCacheRow>(predicate: #Predicate { $0.key == key })).first else { return nil }
        guard row.accountId == accountId else { throw FocusEngineError.invalidIdentity }
        return try APIClient.decoder().decode(T.self, from: row.payload)
    }
    public func saveCache<T: Codable & Sendable>(_ value: T, accountId: String, topic: CacheTopic) throws {
        guard UUID(uuidString: accountId) != nil else { throw FocusEngineError.invalidIdentity }
        let key = accountId + ":" + topic.rawValue; let data = try APIClient.body(value)
        try save {
            if let row = try context.fetch(FetchDescriptor<AccountCacheRow>(predicate: #Predicate { $0.key == key })).first { row.payload = data; row.updatedAt = .now }
            else { context.insert(AccountCacheRow(accountId: accountId, topic: topic, payload: data)) }
        }
    }
    public func activities(accountId: String) throws -> [LocalActivityRecord] {
        let descriptor = FetchDescriptor<PendingActivityRow>(predicate: #Predicate { $0.accountId == accountId }, sortBy: [SortDescriptor(\.createdAt)])
        return try context.fetch(descriptor).map { LocalActivityRecord(id: $0.id, accountId: $0.accountId, submission: try APIClient.decoder().decode(FocusActivitySubmission.self, from: $0.payload), blocked: $0.blocked, failure: $0.failure) }
    }
    public func confirm(accountId: String, id: String, settlement: FocusSettlement) throws {
        guard settlement.session.id == id else { throw APIError(code: "confirmation_mismatch", message: "服务端返回了其他会话，原记录已保留。") }
        try save {
            guard let row = try focusRow(id, accountId) else { return }
            row.state = LocalSyncState.confirmed.rawValue; row.confirmation = try APIClient.body(settlement); row.failure = nil; row.updatedAt = .now
        }
    }
    public func fail(accountId: String, id: String, message: String, blocked: Bool) throws {
        try save {
            guard let row = try focusRow(id, accountId), row.state != LocalSyncState.confirmed.rawValue else { return }
            row.state = blocked ? LocalSyncState.blocked.rawValue : LocalSyncState.pending.rawValue
            row.failure = message; row.attempts += 1; row.updatedAt = .now
        }
    }
    public func confirmActivity(accountId: String, id: String) throws {
        try save { if let row = try activityRow(id, accountId) { context.delete(row) } }
    }
    public func failActivity(accountId: String, id: String, message: String, blocked: Bool) throws {
        try save { if let row = try activityRow(id, accountId) { row.failure = message; row.blocked = blocked } }
    }
    private func commandRow(_ id: String, _ owner: String) throws -> PendingTaskCommandRow? {
        let row = try context.fetch(FetchDescriptor<PendingTaskCommandRow>(predicate: #Predicate { $0.id == id })).first
        if let row, row.accountId != owner { throw FocusEngineError.invalidIdentity }
        return row
    }
    public func taskCommands(accountId: String, includeRejected: Bool = false) throws -> [DurableTaskCommand] {
        let rows = try context.fetch(FetchDescriptor<PendingTaskCommandRow>(predicate: #Predicate { $0.accountId == accountId }, sortBy: [SortDescriptor(\.createdAt)]))
        return try rows.filter { includeRejected || !$0.rejected }.map { row in
            guard let kind = TaskCommandKind(rawValue: row.kind) else { throw FocusEngineError.damagedSnapshot }
            return DurableTaskCommand(id: row.id, accountId: row.accountId, taskId: row.taskId, kind: kind, path: row.path, payload: row.payload, failure: row.failure, rejected: row.rejected)
        }
    }
    public func prepareCommand(_ command: DurableTaskCommand) throws {
        guard UUID(uuidString: command.id) != nil, UUID(uuidString: command.accountId) != nil, UUID(uuidString: command.taskId) != nil,
              let fields = try JSONSerialization.jsonObject(with: command.payload) as? [String: Any], fields["id"] as? String == command.id else { throw FocusEngineError.invalidIdentity }
        let taskPath = "/v1/tasks/\(command.taskId)"
        let parts = command.path.split(separator: "/")
        let reversePath = parts.count == 4 && parts[0] == "v1" && parts[1] == "task-attempts" && UUID(uuidString: String(parts[2])) != nil && parts[3] == "reverse"
        let validPath = command.kind == .conclude ? command.path == taskPath + "/attempts" : command.kind == .retry ? command.path == taskPath + "/retry" : reversePath
        guard validPath else { throw APIError(code: "invalid_command", message: "操作地址无效。") }
        try save {
            if let old = try commandRow(command.id, command.accountId) {
                guard old.taskId == command.taskId, old.kind == command.kind.rawValue, old.path == command.path, old.payload == command.payload else { throw APIError(code: "command_conflict", message: "同一操作标识的内容不同，原请求已保留。") }
                return
            }
            guard try !taskCommands(accountId: command.accountId).contains(where: { $0.taskId == command.taskId }) else { throw APIError(code: "command_pending", message: "这项任务还有待确认操作，请先重试确认原结果。") }
            context.insert(PendingTaskCommandRow(command))
        }
    }
    public func failCommand(accountId: String, id: String, message: String, rejected: Bool) throws {
        try save { if let row = try commandRow(id, accountId) { row.failure = message; row.rejected = rejected } }
    }
    public func confirmCommand(accountId: String, id: String) throws { try save { if let row = try commandRow(id, accountId) { context.delete(row) } } }
}
