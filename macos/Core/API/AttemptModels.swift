import Foundation

public struct TaskAttemptRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let taskId: String
    public let attemptNo: Int
    public let result: String
    public let reason: String
    public let skillSnapshot: [TaskSkillBinding]
    public let concludedAt: Date
    public let reversedAt: Date?
}
public struct TaskRewardRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let attemptId: String
    public let skillId: String
    public let rewardLevelsSnapshot: Int64
    public let xpAmount: Int64
    public let growthEventId: String
}
public struct TaskReversalRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let attemptId: String
    public let reason: String
    public let createdAt: Date
}
public struct TaskAttemptDetail: Codable, Sendable, Equatable, Identifiable {
    public let attempt: TaskAttemptRecord
    public let rewards: [TaskRewardRecord]
    public let reversal: TaskReversalRecord?
    public var id: String { attempt.id }
}
public struct TaskAttemptHistory: Codable, Sendable {
    public let items: [TaskAttemptDetail]
    public let summary: AttemptSummary
}
public struct TaskSettlement: Codable, Sendable {
    public let attempt: TaskAttemptRecord
    public let rewards: [TaskRewardRecord]
    public let reversal: TaskReversalRecord?
    public let task: TaskRecord
    public let settledProgress: [SkillProgress]
}
public struct ConclusionWrite: Codable, Sendable, Equatable {
    public var id = UUID().uuidString.lowercased()
    public let attemptNo: Int
    public let version: Int
    public let result: String
    public let reason: String
}
public struct RetryWrite: Codable, Sendable, Equatable {
    public var id = UUID().uuidString.lowercased()
    public let attemptNo: Int
    public let version: Int
}
public struct ReversalWrite: Codable, Sendable, Equatable {
    public var id = UUID().uuidString.lowercased()
    public let reason: String
}
