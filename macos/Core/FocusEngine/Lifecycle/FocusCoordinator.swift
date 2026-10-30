import Foundation
import Observation

public enum FocusLifecycleEvent: Sendable { case willSleep, willTerminate }

@MainActor @Observable
public final class FocusCoordinator {
    public private(set) var accountId: String?
    public private(set) var lastFinished: LocalFocusRecord?
    public private(set) var persistenceError: String?
    public private(set) var notice: String?
    public var snapshot: FocusSnapshot? { engine.snapshot }
    @ObservationIgnored public var onSignals: (([FocusSignal]) -> Void)?
    @ObservationIgnored public var onPendingChange: (() -> Void)?
    @ObservationIgnored private let store: LocalFocusStore
    @ObservationIgnored private let clock: () -> ClockReading
    private var engine = FocusEngine()

    public init(store: LocalFocusStore, clock: @escaping () -> ClockReading = { .now() }) throws {
        self.store = store; self.clock = clock
        for saved in try store.activeSnapshots() where saved.status == .running {
            var recovered = FocusEngine()
            let signals = try recovered.restore(saved)
            try store.commit(accountId: saved.accountId, snapshot: recovered.snapshot, signals: signals)
        }
    }

    public func activate(accountId: String?) throws {
        if self.accountId == accountId { return }
        if engine.snapshot?.status == .running { try pause() }
        var next = FocusEngine()
        if let accountId, let saved = try store.active(accountId: accountId) {
            let signals = try next.restore(saved)
            if !signals.isEmpty { try store.commit(accountId: accountId, snapshot: next.snapshot, signals: signals) }
        }
        engine = next; self.accountId = accountId; lastFinished = nil; persistenceError = nil
        notice = next.snapshot == nil ? nil : "已恢复上次专注，点击继续开始计时。"
    }

    public func start(skillId: String, taskId: String? = nil, configuration: FocusConfiguration) throws {
        guard let accountId else { throw FocusEngineError.invalidIdentity }
        try mutate { try $0.start(accountId: accountId, skillId: skillId, taskId: taskId, configuration: configuration, at: clock()) }
        lastFinished = nil; notice = nil
    }
    public func tick() {
        guard snapshot?.status == .running else { return }
        do { try mutate { $0.tick(at: clock()) } } catch { persistenceError = "保存未完成：\(error.localizedDescription)" }
    }
    public func pause() throws { if snapshot?.status == .running { try mutate { try $0.pause(at: clock()) } } }
    public func resume() throws { try mutate { try $0.resume(at: clock()) }; notice = nil }
    public func updateNote(_ note: String) throws { try mutate { try $0.updateNote(note); return [] } }
    public func finish(note: String? = nil) throws {
        if snapshot == nil { return }
        try mutate { try $0.finish(at: clock(), note: note) }; notice = nil
    }
    public func handle(_ event: FocusLifecycleEvent) throws {
        try pause()
        if snapshot != nil { notice = event == .willSleep ? "已因系统睡眠暂停，点击继续恢复。" : "已保存并暂停当前专注。" }
    }
    public func addManual(_ submission: FocusSubmission) throws {
        guard let accountId, submission.source == "manual" else { throw FocusEngineError.invalidIdentity }
        try store.commit(accountId: accountId, snapshot: nil, signals: [], finished: submission)
        lastFinished = try store.record(accountId: accountId, id: submission.id)
        onPendingChange?()
    }
    private func mutate(_ operation: (inout FocusEngine) throws -> [FocusSignal]) throws {
        guard let accountId else { throw FocusEngineError.invalidIdentity }
        var next = engine
        let signals = try operation(&next)
        do {
            if let ended = next.snapshot, ended.status == .finished {
                let submission = try FocusSubmission(snapshot: ended)
                try store.commit(accountId: accountId, snapshot: nil, signals: signals, finished: submission)
                lastFinished = try store.record(accountId: accountId, id: ended.id)
                try next.clearFinished()
            } else { try store.commit(accountId: accountId, snapshot: next.snapshot, signals: signals) }
            engine = next; persistenceError = nil
            if !signals.isEmpty { onSignals?(signals); onPendingChange?() }
        } catch { persistenceError = "保存未完成：\(error.localizedDescription)"; throw error }
    }
}
