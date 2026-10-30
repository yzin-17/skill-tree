import Foundation

public enum TaskStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case todo, inProgress = "in_progress", success, failed, canceled
    public var id: String { rawValue }
    public var label: String {
        switch self { case .todo: "待开始"; case .inProgress: "进行中"; case .success: "已成功"; case .failed: "失败"; case .canceled: "已取消" }
    }
    public var canConclude: Bool { self == .todo || self == .inProgress }
    public var canCancel: Bool { canConclude || self == .failed }
}
public struct TaskSkillBinding: Codable, Sendable, Equatable, Identifiable {
    public var skillId: String
    public var rewardLevels: Int64
    public var id: String { skillId }
}
public struct AttemptSummary: Codable, Sendable, Equatable {
    public let total: Int64
    public let successes: Int64
    public let failures: Int64
    public let retries: Int64
    public let successRate: Double?
}
public struct TaskWrite: Codable, Sendable, Equatable {
    public var id = UUID().uuidString.lowercased()
    public var title = ""
    public var description = ""
    public var successCriteria = ""
    public var status = TaskStatus.todo
    public var dueAt: Date?
    public var pinned = false
    public var skills: [TaskSkillBinding] = []
    public var version = 0
    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 140, description.count <= 10000, successCriteria.count <= 4000,
              skills.count <= 64, Set(skills.map(\.skillId)).count == skills.count,
              skills.allSatisfy({ UUID(uuidString: $0.skillId) != nil && (0...1_000_000).contains($0.rewardLevels) }) else {
            throw APIError(code: "invalid_task", message: "请输入有效标题，每项技能只能关联一次，奖励须为 0–1000000 的整数。")
        }
    }
}
public struct TaskRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var title: String
    public var description: String
    public var successCriteria: String
    public var status: TaskStatus
    public var dueAt: Date?
    public var pinned: Bool
    public var skills: [TaskSkillBinding]
    public let version: Int
    public let currentAttemptNo: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let totalFocusSeconds: Int64
    public let focusCount: Int64
    public let attemptSummary: AttemptSummary
    public var write: TaskWrite { TaskWrite(id: id, title: title, description: description, successCriteria: successCriteria, status: status, dueAt: dueAt, pinned: pinned, skills: skills, version: version) }
    public var isOverdue: Bool { status.canConclude && dueAt.map { $0 < .now } == true }
}
