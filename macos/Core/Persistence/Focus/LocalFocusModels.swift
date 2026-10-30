import Foundation
import SwiftData

@Model
final class ActiveFocusRow {
    @Attribute(.unique) var accountId: String
    var payload: Data
    var updatedAt: Date
    init(accountId: String, payload: Data) { self.accountId = accountId; self.payload = payload; updatedAt = .now }
}
@Model
final class PendingFocusRow {
    @Attribute(.unique) var id: String
    var accountId: String
    var payload: Data
    var state: String
    var failure: String?
    var confirmation: Data?
    var attempts: Int
    var createdAt: Date
    var updatedAt: Date
    init(id: String, accountId: String, payload: Data) {
        self.id = id; self.accountId = accountId; self.payload = payload; state = "pending"
        attempts = 0; createdAt = .now; updatedAt = .now
    }
}
@Model
final class PendingActivityRow {
    @Attribute(.unique) var id: String
    var accountId: String
    var payload: Data
    var failure: String?
    var blocked: Bool
    var createdAt: Date
    init(id: String, accountId: String, payload: Data) { self.id = id; self.accountId = accountId; self.payload = payload; blocked = false; createdAt = .now }
}

public enum LocalSyncState: String, Codable, Sendable { case pending, confirmed, blocked }
public struct LocalFocusRecord: Sendable, Identifiable {
    public let id: String
    public let accountId: String
    public let submission: FocusSubmission
    public let state: LocalSyncState
    public let failure: String?
    public let confirmation: FocusSettlement?
}
public struct LocalActivityRecord: Sendable, Identifiable {
    public let id: String
    public let accountId: String
    public let submission: FocusActivitySubmission
    public let blocked: Bool
    public let failure: String?
}
