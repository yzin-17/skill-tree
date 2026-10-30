import Foundation

public struct ActivityEntry: Identifiable, Sendable {
    public let id: String
    public let events: [ActivityRecord]
    public var confirmation: ActivityRecord? { events.first { $0.type == "focus.recorded" && $0.producer == "server" } }
    public var event: ActivityRecord { confirmation ?? events[0] }
    public var occurredAt: Date { event.occurredAt }
    public var isFocus: Bool { id.hasPrefix("focus:") }
    public var effectiveSeconds: Int64? { confirmation?.metadata["effective_seconds"]?.integer }
    public var awardedXp: Int64? { confirmation?.metadata["awarded_xp"]?.integer }
    public var taskId: String? { confirmation?.metadata["task_id"]?.string }
    public var processEvents: [ActivityRecord] { events.filter { $0.id != confirmation?.id } }

    public static func make(_ records: [ActivityRecord], groupFocus: Bool) -> [ActivityEntry] {
        var seen = Set<String>()
        let ordered = records.filter { seen.insert($0.id).inserted }.sorted {
            $0.occurredAt == $1.occurredAt ? $0.id < $1.id : $0.occurredAt > $1.occurredAt
        }
        let grouped = Dictionary(grouping: ordered) { event in
            if groupFocus && event.entityType == "focus_session" && UUID(uuidString: event.entityId) != nil { return "focus:" + event.entityId }
            return "event:" + event.id
        }
        return grouped.map { ActivityEntry(id: $0.key, events: $0.value) }.sorted {
            $0.occurredAt == $1.occurredAt ? $0.id < $1.id : $0.occurredAt > $1.occurredAt
        }
    }
}
