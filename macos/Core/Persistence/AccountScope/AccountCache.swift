import Foundation
import SwiftData

public enum CacheTopic: String, Sendable { case trees, skills, tasks, progress, links, careers, titles, achievementCommands }

@Model
final class AccountCacheRow {
    @Attribute(.unique) var key: String
    var accountId: String
    var topic: String
    var payload: Data
    var updatedAt: Date
    init(accountId: String, topic: CacheTopic, payload: Data) {
        key = accountId + ":" + topic.rawValue; self.accountId = accountId; self.topic = topic.rawValue
        self.payload = payload; updatedAt = .now
    }
}
