import Foundation

public enum ConditionKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case skillLevel = "skill_level", focusMinutes = "focus_minutes", taskSuccessCount = "task_success_count", specificTaskSuccess = "specific_task_success"
    public var id: String { rawValue }
    public var label: String { switch self { case .skillLevel: "技能等级"; case .focusMinutes: "计时专注分钟"; case .taskSuccessCount: "任务成功次数"; case .specificTaskSuccess: "指定任务成功" } }
}
public struct AchievementCondition: Codable, Sendable, Equatable {
    public var type: ConditionKind = .skillLevel
    public var skillId: String?
    public var taskId: String?
    public var gte: Int64? = 1
}
public struct AchievementConditions: Codable, Sendable, Equatable {
    public var all: [AchievementCondition] = []
    public func validate() throws {
        guard (1...32).contains(all.count) else { throw APIError(code: "invalid_conditions", message: "请配置 1–32 项条件。") }
        var keys = Set<String>()
        for condition in all {
            let skillValid = condition.skillId.map { UUID(uuidString: $0) != nil } ?? true
            let taskValid = condition.taskId.map { UUID(uuidString: $0) != nil } ?? true
            let thresholdValid = condition.gte.map { (1...1_000_000).contains($0) } ?? false
            var valid = skillValid && taskValid
            switch condition.type {
            case .skillLevel, .focusMinutes: valid = valid && condition.skillId != nil && condition.taskId == nil && thresholdValid
            case .taskSuccessCount: valid = valid && condition.taskId == nil && thresholdValid
            case .specificTaskSuccess: valid = valid && condition.skillId == nil && condition.taskId != nil && condition.gte == nil
            }
            guard valid else { throw APIError(code: "invalid_condition", message: "请完整选择条件对象；阈值须为 1–1000000 的整数。") }
            guard keys.insert("\(condition.type.rawValue):\(condition.skillId ?? ""):\(condition.taskId ?? "")").inserted else { throw APIError(code: "duplicate_condition", message: "相同对象的同类条件只能配置一次。") }
        }
    }
}
public struct ConditionEvidence: Codable, Sendable, Equatable {
    public let condition: AchievementCondition
    public let current: Int64
    public let required: Int64
    public let met: Bool
    public let unit: String
    public let sourceType: String
    public let sourceIds: [String]
    public let sourcesTruncated: Bool
}
public struct ConditionEvaluation: Codable, Sendable, Equatable {
    public let eligible: Bool
    public let evidence: [ConditionEvidence]
}
public struct CareerWrite: Codable, Sendable {
    public var id = UUID().uuidString.lowercased()
    public var name = ""
    public var description = ""
    public var conditions = AchievementConditions()
    public var version = 0
    public var badgeKey = "star"
    public var parentCareerId: String?
    public var sortOrder = 0
}
public struct CareerRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let conditions: AchievementConditions
    public let version: Int
    public let badgeKey: String
    public let parentCareerId: String?
    public let sortOrder: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let evaluation: ConditionEvaluation
    public let parentReached: Bool
    public var write: CareerWrite { .init(id: id, name: name, description: description, conditions: conditions, version: version, badgeKey: badgeKey, parentCareerId: parentCareerId, sortOrder: sortOrder) }
}
public struct CareerTransition: Codable, Sendable, Identifiable {
    public let id: String
    public let fromCareerId: String?
    public let toCareerId: String
    public let confirmedAt: Date
    public let evidenceSnapshot: ConditionEvaluation
}
public struct CareerCatalog: Codable, Sendable {
    public let items: [CareerRecord]
    public let history: [CareerTransition]
    public let currentCareerId: String?
}
public struct TitleWrite: Codable, Sendable {
    public var id = UUID().uuidString.lowercased()
    public var name = ""
    public var description = ""
    public var conditions = AchievementConditions()
    public var version = 0
    public var iconKey = "star"
}
public struct TitleRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let conditions: AchievementConditions
    public let version: Int
    public let iconKey: String
    public let createdAt: Date
    public let updatedAt: Date
    public let evaluation: ConditionEvaluation
    public let unlockedAt: Date?
    public let equippedAt: Date?
    public let unlockedEvidence: ConditionEvaluation?
    public var write: TitleWrite { .init(id: id, name: name, description: description, conditions: conditions, version: version, iconKey: iconKey) }
}
public struct TitleCatalog: Codable, Sendable {
    public let items: [TitleRecord]
    public let equippedTitleId: String?
}
public struct AchievementCommand: Codable, Sendable {
    public let id: String
    public let accountId: String
    public let path: String
    public let career: Bool
    public let payload: Data
}
