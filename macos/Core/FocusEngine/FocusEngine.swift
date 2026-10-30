import Foundation

public struct FocusEngine: Sendable {
    public private(set) var snapshot: FocusSnapshot?
    public init() {}

    @discardableResult
    public mutating func start(accountId: String, skillId: String, taskId: String? = nil,
                               configuration: FocusConfiguration, at reading: ClockReading,
                               id: String = UUID().uuidString.lowercased()) throws -> [FocusSignal] {
        guard snapshot == nil else { throw FocusEngineError.alreadyActive }
        try configuration.validate()
        guard UUID(uuidString: accountId) != nil, UUID(uuidString: skillId) != nil,
              taskId == nil || UUID(uuidString: taskId!) != nil, UUID(uuidString: id) != nil else { throw FocusEngineError.invalidIdentity }
        let value = FocusSnapshot(id: id, accountId: accountId, skillId: skillId, taskId: taskId,
            configuration: configuration, startedAt: reading.wall, endedAt: nil, status: .running,
            phase: .focus, round: 1, phaseElapsed: 0, effectiveElapsed: 0, lastMonotonic: reading.monotonic,
            lastObservedAt: reading.wall, finishReason: nil, note: "")
        try value.validate()
        snapshot = value
        return [signal(.started, value, at: reading.wall)]
    }

    @discardableResult
    public mutating func tick(at reading: ClockReading) -> [FocusSignal] {
        guard var value = snapshot, value.status == .running, let anchor = value.lastMonotonic,
              reading.monotonic.isFinite, reading.monotonic >= 0 else { return [] }
        var remaining = max(0, reading.monotonic - anchor)
        var signals: [FocusSignal] = []
        repeat {
            let duration: Double = value.configuration.mode == .countUp ? 2_678_400 : Double(value.phase == .rest ? value.configuration.restSeconds : value.configuration.targetSeconds)
            let available = max(0, duration - value.phaseElapsed)
            let consumed = min(remaining, available)
            value.phaseElapsed += consumed
            if value.phase == .focus { value.effectiveElapsed += consumed }
            remaining -= consumed
            if consumed < available { break }
            let boundary = reading.wall.addingTimeInterval(-remaining)
            if value.configuration.mode == .pomodoro && value.phase == .focus && value.round < value.configuration.rounds {
                value.phaseElapsed = 0
                if value.configuration.restSeconds == 0 {
                    value.round += 1
                    signals.append(signal(.roundStarted, value, at: boundary))
                } else {
                    value.phase = .rest
                    signals.append(signal(.restStarted, value, at: boundary))
                }
            } else if value.configuration.mode == .pomodoro && value.phase == .rest {
                value.phase = .focus; value.round += 1; value.phaseElapsed = 0
                signals.append(signal(.roundStarted, value, at: boundary))
            } else {
                value.status = .finished; value.endedAt = boundary; value.finishReason = .completed
                signals.append(signal(.finished, value, at: boundary))
            }
        } while remaining > 0 && value.status == .running
        value.lastMonotonic = reading.monotonic; value.lastObservedAt = reading.wall
        if value.status == .finished { value.lastMonotonic = nil }
        snapshot = value
        return signals
    }

    @discardableResult
    public mutating func pause(at reading: ClockReading) throws -> [FocusSignal] {
        guard snapshot != nil else { throw FocusEngineError.noSession }
        var signals = tick(at: reading)
        guard var value = snapshot, value.status == .running else { return signals }
        value.status = .paused; value.lastMonotonic = nil; value.lastObservedAt = reading.wall
        snapshot = value; signals.append(signal(.paused, value, at: reading.wall))
        return signals
    }

    @discardableResult
    public mutating func resume(at reading: ClockReading) throws -> [FocusSignal] {
        guard var value = snapshot else { throw FocusEngineError.noSession }
        guard value.status == .paused else { if value.status == .running { return [] }; throw FocusEngineError.invalidState }
        value.status = .running; value.lastMonotonic = reading.monotonic; value.lastObservedAt = reading.wall
        snapshot = value
        return [signal(.resumed, value, at: reading.wall)]
    }

    @discardableResult
    public mutating func finish(at reading: ClockReading, note: String? = nil) throws -> [FocusSignal] {
        guard snapshot != nil else { throw FocusEngineError.noSession }
        let note = note ?? snapshot?.note ?? ""
        guard note.unicodeScalars.count <= 4000 else { throw APIError(code: "invalid_note", message: "备注不能超过 4000 个字符。") }
        var signals = tick(at: reading)
        guard var value = snapshot else { return signals }
        if value.status == .finished {
            if signals.contains(where: { $0.kind == .finished }) { value.note = note; snapshot = value }
            return signals
        }
        value.status = .finished; value.lastMonotonic = nil; value.endedAt = reading.wall
        value.lastObservedAt = reading.wall; value.finishReason = .manual; value.note = note
        snapshot = value; signals.append(signal(.finished, value, at: reading.wall))
        return signals
    }

    public mutating func updateNote(_ note: String) throws {
        guard var value = snapshot, value.status != .finished else { throw FocusEngineError.noSession }
        guard note.unicodeScalars.count <= 4000 else { throw APIError(code: "invalid_note", message: "备注不能超过 4000 个字符。") }
        value.note = note; snapshot = value
    }

    public mutating func clearFinished() throws {
        guard snapshot?.status == .finished else { throw FocusEngineError.invalidState }
        snapshot = nil
    }

    @discardableResult
    public mutating func restore(_ saved: FocusSnapshot) throws -> [FocusSignal] {
        guard snapshot == nil else { throw FocusEngineError.alreadyActive }
        try saved.validate()
        var value = saved; value.lastMonotonic = nil
        var signals: [FocusSignal] = []
        if value.status == .running {
            value.status = .paused
            signals = [signal(.paused, value, at: value.lastObservedAt)]
        }
        snapshot = value
        return signals
    }

    private func signal(_ kind: FocusSignalKind, _ value: FocusSnapshot, at date: Date) -> FocusSignal {
        FocusSignal(id: UUID().uuidString.lowercased(), kind: kind, sessionId: value.id, accountId: value.accountId,
                    skillId: value.skillId, taskId: value.taskId, occurredAt: date, effectiveSeconds: value.effectiveSeconds,
                    mode: value.configuration.mode, phase: value.phase, round: value.round)
    }
}
