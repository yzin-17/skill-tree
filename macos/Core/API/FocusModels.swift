import Foundation

public struct FocusSubmission: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var skillId: String
    public var taskId: String?
    public var mode: String
    public var targetSeconds: Int?
    public var effectiveSeconds: Int
    public var startedAt: Date
    public var endedAt: Date
    public var note: String
    public var source: String
    public var pomodoroRounds: Int

    public init(snapshot: FocusSnapshot) throws {
        guard snapshot.status == .finished, let endedAt = snapshot.endedAt else { throw FocusEngineError.invalidState }
        id = snapshot.id; skillId = snapshot.skillId; taskId = snapshot.taskId; mode = snapshot.configuration.mode.rawValue
        targetSeconds = snapshot.configuration.mode == .countUp ? nil : snapshot.configuration.targetSeconds
        effectiveSeconds = snapshot.effectiveSeconds; startedAt = snapshot.startedAt; self.endedAt = endedAt
        note = snapshot.note; source = "timer"; pomodoroRounds = snapshot.configuration.mode == .pomodoro ? snapshot.configuration.rounds : 0
    }
    public init(id: String = UUID().uuidString.lowercased(), skillId: String, taskId: String? = nil,
                startedAt: Date, endedAt: Date, effectiveSeconds: Int, note: String = "") {
        self.id = id; self.skillId = skillId; self.taskId = taskId; self.startedAt = startedAt; self.endedAt = endedAt
        self.effectiveSeconds = effectiveSeconds; self.note = note; mode = "manual"; source = "manual"; targetSeconds = nil; pomodoroRounds = 0
    }
    public func validate() throws {
        guard UUID(uuidString: id) != nil, UUID(uuidString: skillId) != nil, taskId == nil || UUID(uuidString: taskId!) != nil,
              (0...2_678_400).contains(effectiveSeconds), note.unicodeScalars.count <= 4000 else { throw APIError(code: "invalid_focus", message: "专注字段或有效时长无效。") }
        switch mode {
        case "manual":
            guard source == "manual", effectiveSeconds > 0, targetSeconds == nil, endedAt >= startedAt,
                  Double(effectiveSeconds) <= endedAt.timeIntervalSince(startedAt) + 1 else { throw APIError(code: "invalid_manual", message: "补录区间必须容纳有效时长。") }
        case "count_up": guard source == "timer", targetSeconds == nil else { throw FocusEngineError.invalidConfiguration }
        case "countdown", "pomodoro":
            guard source == "timer", let targetSeconds, (1...86400).contains(targetSeconds) else { throw FocusEngineError.invalidConfiguration }
            if mode == "countdown" && effectiveSeconds > targetSeconds { throw FocusEngineError.invalidConfiguration }
            if mode == "pomodoro" && (!(1...24).contains(pomodoroRounds) || effectiveSeconds > targetSeconds * pomodoroRounds) { throw FocusEngineError.invalidConfiguration }
        default: throw FocusEngineError.invalidConfiguration
        }
        if mode != "pomodoro" && pomodoroRounds != 0 { throw FocusEngineError.invalidConfiguration }
    }
}

public struct FocusRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let skillId: String
    public var taskId: String?
    public let mode: String
    public let targetSeconds: Int?
    public let effectiveSeconds: Int
    public let startedAt: Date
    public let endedAt: Date
    public let note: String
    public let source: String
    public let pomodoroRounds: Int
    public let version: Int
    public let createdAt: Date
    public let invalidatedAt: Date?
    public let clockAdjusted: Bool
}
public struct MissingPrerequisiteRecord: Codable, Sendable, Equatable, Identifiable {
    public let skillId: String
    public let name: String
    public let requiredLevel: Int64
    public let currentLevel: Int64
    public var id: String { skillId }
}
public struct SkillProgress: Codable, Sendable, Equatable, Identifiable {
    public let skillId: String
    public let totalFocusSeconds: Int64
    public let timeXp: Int64
    public let taskBonusXp: Int64
    public let totalXp: Int64
    public let level: Int64
    public let xpCurrent: Int64
    public let xpRequired: Int64
    public let unlocked: Bool
    public let missingPrerequisites: [MissingPrerequisiteRecord]
    public var id: String { skillId }
}
public struct FocusSettlement: Codable, Sendable, Equatable {
    public let session: FocusRecord
    public let awardedXp: Int64
    public let settledProgress: SkillProgress
}
public struct FocusPage: Codable, Sendable {
    public let items: [FocusRecord]
    public let nextCursor: String
    public let totalSeconds: Int64
    public let count: Int64
}
public struct FocusActivitySubmission: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let type: String
    public let entityId: String
    public let skillId: String
    public let taskId: String?
    public let occurredAt: Date
    public let mode: String
    public let effectiveSeconds: Int
    public init(_ signal: FocusSignal) {
        id = signal.id; type = signal.kind == .finished ? "focus.ended" : "focus.\(signal.kind.rawValue)"; entityId = signal.sessionId; skillId = signal.skillId
        taskId = signal.taskId; occurredAt = signal.occurredAt; mode = signal.mode.rawValue; effectiveSeconds = signal.effectiveSeconds
    }
}
