import Foundation

public enum FocusMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case countUp = "count_up", countdown, pomodoro
    public var id: String { rawValue }
    public var name: String { switch self { case .countUp: "正计时"; case .countdown: "倒计时"; case .pomodoro: "番茄钟" } }
}
public enum FocusStatus: String, Codable, Sendable { case running, paused, finished }
public enum FocusPhase: String, Codable, Sendable { case focus, rest }
public enum FocusFinishReason: String, Codable, Sendable { case manual, completed }

public struct FocusConfiguration: Codable, Sendable, Equatable {
    public var mode: FocusMode
    public var targetSeconds: Int
    public var restSeconds: Int
    public var rounds: Int
    public init(mode: FocusMode = .countUp, targetSeconds: Int = 1500, restSeconds: Int = 300, rounds: Int = 4) {
        self.mode = mode; self.targetSeconds = targetSeconds; self.restSeconds = restSeconds; self.rounds = rounds
    }
    public func validate() throws {
        if mode != .countUp && !(1...86400).contains(targetSeconds) { throw FocusEngineError.invalidConfiguration }
        if mode == .pomodoro && (!(0...86400).contains(restSeconds) || !(1...24).contains(rounds)) { throw FocusEngineError.invalidConfiguration }
    }
}

public struct ClockReading: Sendable {
    public let monotonic: TimeInterval
    public let wall: Date
    public init(monotonic: TimeInterval, wall: Date) { self.monotonic = monotonic; self.wall = wall }
    public static func now() -> ClockReading { .init(monotonic: TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000, wall: .now) }
}

public enum FocusEngineError: String, Error, LocalizedError, Sendable {
    case invalidConfiguration, alreadyActive, noSession, invalidState, invalidIdentity, damagedSnapshot
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "计时时长或番茄轮数无效。"
        case .alreadyActive: "请先结束当前专注，再开始下一次。"
        case .noSession: "当前没有专注会话。"
        case .invalidState: "当前状态不支持此操作。"
        case .invalidIdentity: "请先选择账号和主技能。"
        case .damagedSnapshot: "本地计时现场无法读取，原记录已保留。"
        }
    }
}

public struct FocusSnapshot: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let accountId: String
    public let skillId: String
    public var taskId: String?
    public let configuration: FocusConfiguration
    public let startedAt: Date
    public var endedAt: Date?
    public var status: FocusStatus
    public var phase: FocusPhase
    public var round: Int
    public var phaseElapsed: TimeInterval
    public var effectiveElapsed: TimeInterval
    public var lastMonotonic: TimeInterval?
    public var lastObservedAt: Date
    public var finishReason: FocusFinishReason?
    public var note: String
    public var effectiveSeconds: Int { Int(floor(max(0, effectiveElapsed))) }
    public var remainingSeconds: Int? {
        guard configuration.mode != .countUp else { return nil }
        let duration = phase == .rest ? configuration.restSeconds : configuration.targetSeconds
        return Int(ceil(max(0, Double(duration) - phaseElapsed)))
    }
    public func validate() throws {
        try configuration.validate()
        guard UUID(uuidString: id) != nil, UUID(uuidString: accountId) != nil, UUID(uuidString: skillId) != nil,
              taskId == nil || UUID(uuidString: taskId!) != nil,
              note.unicodeScalars.count <= 4000,
              effectiveElapsed.isFinite, effectiveElapsed >= 0, effectiveElapsed <= 2_678_400,
              phaseElapsed.isFinite, phaseElapsed >= 0, (1...24).contains(round),
              lastMonotonic == nil || (lastMonotonic!.isFinite && lastMonotonic! >= 0) else { throw FocusEngineError.damagedSnapshot }
        if configuration.mode != .pomodoro && (phase != .focus || round != 1) { throw FocusEngineError.damagedSnapshot }
        if configuration.mode == .pomodoro && round > configuration.rounds { throw FocusEngineError.damagedSnapshot }
        if configuration.mode != .countUp && phaseElapsed > Double(phase == .rest ? configuration.restSeconds : configuration.targetSeconds) { throw FocusEngineError.damagedSnapshot }
    }
}

public enum FocusSignalKind: String, Codable, Sendable { case started, paused, resumed, finished, restStarted, roundStarted }
public struct FocusSignal: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let kind: FocusSignalKind
    public let sessionId: String
    public let accountId: String
    public let skillId: String
    public let taskId: String?
    public let occurredAt: Date
    public let effectiveSeconds: Int
    public let mode: FocusMode
    public let phase: FocusPhase
    public let round: Int
    public var isLifecycleEvent: Bool { [.started, .paused, .resumed, .finished].contains(kind) }
}
