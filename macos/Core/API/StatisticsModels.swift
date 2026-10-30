import Foundation

public struct StatisticsTotals: Codable, Sendable {
    public let focusSeconds: Int64
    public let timerSeconds: Int64
    public let manualSeconds: Int64
    public let focusCount: Int64
    public let timeXp: Int64
    public let taskBonusXp: Int64
    public let totalXp: Int64
    public let attempts: AttemptSummary
}
public struct StatisticsSources: Codable, Sendable {
    public let focusIds: [String]
    public let growthIds: [String]
    public let attemptIds: [String]
    public let retryIds: [String]
    public var records: [RecordSource] {
        focusIds.map { .init(kind: "focus_session", id: $0) } + growthIds.map { .init(kind: "growth_event", id: $0) } + attemptIds.map { .init(kind: "task_attempt", id: $0) } + retryIds.map { .init(kind: "task_retry", id: $0) }
    }
}
public struct StatisticsBucket: Codable, Sendable, Identifiable {
    public let start: Date
    public let label: String
    public let totals: StatisticsTotals
    public let sources: StatisticsSources
    public var id: Date { start }
}
public struct SkillStatistics: Codable, Sendable, Identifiable {
    public let skillId: String
    public let treeId: String
    public let name: String
    public let totals: StatisticsTotals
    public var id: String { skillId }
}
public struct StatisticsSummary: Codable, Sendable {
    public let timezone: String
    public let from: Date
    public let to: Date
    public let bucket: String
    public let allTime: StatisticsTotals
    public let totals: StatisticsTotals
    public let series: [StatisticsBucket]
    public let skills: [SkillStatistics]
    public let sources: StatisticsSources
    public let careerHistory: [CareerTransition]
    public let titleHistory: [ActivityRecord]
    public let historyScope: String
}
