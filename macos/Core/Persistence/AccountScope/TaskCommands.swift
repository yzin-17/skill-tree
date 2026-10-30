import Foundation
import SwiftData

public enum TaskCommandKind: String, Codable, Sendable { case conclude, retry, reverse }
public struct DurableTaskCommand: Sendable, Identifiable {
    public let id: String
    public let accountId: String
    public let taskId: String
    public let kind: TaskCommandKind
    public let path: String
    public let payload: Data
    public let failure: String?
    public let rejected: Bool
    public init(id: String, accountId: String, taskId: String, kind: TaskCommandKind, path: String, payload: Data, failure: String? = nil, rejected: Bool = false) {
        self.id = id; self.accountId = accountId; self.taskId = taskId; self.kind = kind; self.path = path; self.payload = payload; self.failure = failure; self.rejected = rejected
    }
}
@Model
final class PendingTaskCommandRow {
    @Attribute(.unique) var id: String
    var accountId: String
    var taskId: String
    var kind: String
    var path: String
    var payload: Data
    var failure: String?
    var rejected: Bool
    var createdAt: Date
    init(_ command: DurableTaskCommand) {
        id = command.id; accountId = command.accountId; taskId = command.taskId; kind = command.kind.rawValue
        path = command.path; payload = command.payload; failure = nil; rejected = false; createdAt = .now
    }
}
