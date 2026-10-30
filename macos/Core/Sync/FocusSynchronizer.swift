import Foundation
import Observation

public struct SyncIdentity: Equatable, Sendable {
    public let accountId: String
    public let token: String
    public init(accountId: String, token: String) { self.accountId = accountId; self.token = token }
}
public protocol FocusRemote: Sendable {
    func uploadFocus(_ value: FocusSubmission, token: String) async throws -> FocusSettlement
    func uploadActivity(_ value: FocusActivitySubmission, token: String) async throws -> String
    func fetchProgress(token: String) async throws -> [SkillProgress]
}
extension APIClient: FocusRemote {
    public func uploadFocus(_ value: FocusSubmission, token: String) async throws -> FocusSettlement {
        try await request("/v1/focus-sessions", method: "POST", token: token, body: Self.body(value))
    }
    public func uploadActivity(_ value: FocusActivitySubmission, token: String) async throws -> String {
        struct Reply: Decodable, Sendable { let id: String }
        let reply: Reply = try await request("/v1/activity-events", method: "POST", token: token, body: Self.body(value))
        return reply.id
    }
    public func fetchProgress(token: String) async throws -> [SkillProgress] { try await request("/v1/progress", token: token) }
}

@MainActor @Observable
public final class FocusSynchronizer {
    public private(set) var isSyncing = false
    public private(set) var records: [LocalFocusRecord] = []
    public private(set) var activityCount = 0
    public private(set) var blockedActivityCount = 0
    public private(set) var activities: [LocalActivityRecord] = []
    public private(set) var progress: [SkillProgress] = []
    public private(set) var lastSyncedAt: Date?
    public private(set) var confirmedFocusRevision = 0
    public private(set) var errorMessage: String?
    public var pendingCount: Int { records.filter { $0.state == .pending }.count }
    public var blockedCount: Int { records.filter { $0.state == .blocked }.count }
    @ObservationIgnored public var onAuthenticationFailure: ((String) -> Void)?
    @ObservationIgnored private let local: LocalFocusStore
    @ObservationIgnored private let remote: any FocusRemote
    @ObservationIgnored private let identity: () -> SyncIdentity?
    @ObservationIgnored private var owner: String?
    @ObservationIgnored private var requested = false
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var nextAttempt = Date.distantPast

    public init(local: LocalFocusStore, remote: any FocusRemote, identity: @escaping () -> SyncIdentity?) {
        self.local = local; self.remote = remote; self.identity = identity
    }
    public func activate() throws {
        owner = identity()?.accountId; records = []; activities = []; activityCount = 0; blockedActivityCount = 0; progress = []
        errorMessage = nil; lastSyncedAt = nil; failures = 0; nextAttempt = .distantPast
        if let owner { progress = try local.cache(accountId: owner, topic: .progress) ?? [] }
        try reload()
        if isSyncing { requested = true }
    }
    public func reload() throws {
        guard let current = identity(), current.accountId == owner else { return }
        records = try local.records(accountId: current.accountId)
        let events = try local.activities(accountId: current.accountId)
        activities = events
        activityCount = events.count; blockedActivityCount = events.filter(\.blocked).count
    }
    public func synchronize(force: Bool = false) async {
        if isSyncing { requested = true; return }
        guard identity() != nil, force || Date.now >= nextAttempt else { return }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            requested = false
            guard let current = identity() else { break }
            if owner != current.accountId { do { try activate() } catch { errorMessage = error.localizedDescription; break } }
            do {
                for event in try local.activities(accountId: current.accountId) where !event.blocked || force {
                    guard identity() == current else { break }
                    do {
                        let id = try await remote.uploadActivity(event.submission, token: current.token)
                        guard identity() == current else { break }
                        guard id == event.id else { throw APIError(code: "confirmation_mismatch", message: "事件确认不一致，记录已保留。", httpStatus: 409) }
                        try local.confirmActivity(accountId: current.accountId, id: id)
                    } catch {
                        guard identity() == current else { break }
                        try local.failActivity(accountId: current.accountId, id: event.id, message: message(error), blocked: permanent(error))
                        if !permanent(error) { throw error }
                    }
                }
                for record in try local.records(accountId: current.accountId) where record.state == .pending || (force && record.state == .blocked) {
                    guard identity() == current else { break }
                    do {
                        let settlement = try await remote.uploadFocus(record.submission, token: current.token)
                        guard identity() == current else { break }
                        try local.confirm(accountId: current.accountId, id: record.id, settlement: settlement)
                        confirmedFocusRevision += 1
                    } catch {
                        guard identity() == current else { break }
                        try local.fail(accountId: current.accountId, id: record.id, message: message(error), blocked: permanent(error))
                        if !permanent(error) { throw error }
                    }
                }
                if identity() == current {
                    let latest = try await remote.fetchProgress(token: current.token)
                    if identity() == current {
                        try local.saveCache(latest, accountId: current.accountId, topic: .progress)
                        progress = latest; failures = 0; nextAttempt = .distantPast; lastSyncedAt = .now
                        try reload(); errorMessage = blockedCount + blockedActivityCount > 0 ? "部分记录存在冲突，原记录已保留，请查看详情。" : nil
                    }
                }
            } catch {
                if identity() == current {
                    errorMessage = message(error); failures += 1
                    nextAttempt = .now.addingTimeInterval(min(60, pow(2, Double(min(failures, 6)))))
                    try? reload()
                    if (error as? APIError)?.code == "unauthenticated" { onAuthenticationFailure?(current.accountId) }
                }
            }
        } while requested && identity() != nil && Date.now >= nextAttempt
    }
    private func permanent(_ error: Error) -> Bool {
        guard let error = error as? APIError, let status = error.httpStatus else { return false }
        return (400..<500).contains(status) && ![401, 408, 429].contains(status)
    }
    private func message(_ error: Error) -> String {
        if let error = error as? APIError { return error.message }
        return "连接暂不可用，记录已保存在本机，恢复连接后会重试。"
    }
}
