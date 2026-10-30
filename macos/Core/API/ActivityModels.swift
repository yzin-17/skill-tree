import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String), integer(Int64), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .integer(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .string(let v): try c.encode(v); case .integer(let v): try c.encode(v); case .number(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .object(let v): try c.encode(v); case .array(let v): try c.encode(v); case .null: try c.encodeNil() }
    }
    public var string: String? { if case .string(let v) = self { v } else { nil } }
    public var integer: Int64? { if case .integer(let v) = self { v } else { nil } }
}
public struct ActivityRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let type: String
    public let producer: String
    public let entityType: String
    public let entityId: String
    public let summary: String
    public let skillIds: [String]
    public let metadata: [String: JSONValue]
    public let occurredAt: Date
    public let createdAt: Date
}
public struct ActivityPage: Codable, Sendable {
    public let items: [ActivityRecord]
    public let nextCursor: String
}
public struct GrowthRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let skillId: String
    public let eventType: String
    public let sourceId: String
    public let deltaXp: Int64
    public let note: String
    public let createdAt: Date
    public let reversesEventId: String?
}
public struct RetryRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let taskId: String
    public let previousAttemptNo: Int
    public let nextAttemptNo: Int
    public let previousAttemptId: String
    public let createdAt: Date
}
public struct RecordSource: Identifiable, Equatable, Sendable {
    public let kind: String
    public let recordId: String
    public var id: String { kind + ":" + recordId }
    public init(kind: String, id: String) { self.kind = kind; recordId = id }
}
public enum APIQuery {
    public static func path(_ path: String, _ items: [URLQueryItem]) -> String {
        var url = URLComponents(); url.path = path; url.queryItems = items.filter { $0.value?.isEmpty == false }
        return url.string ?? path
    }
    public static func range(from: Date, through: Date, timezone: String) -> [URLQueryItem] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: timezone) ?? .gmt
        let start = calendar.startOfDay(for: from)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: through)) ?? through
        return [.init(name: "from", value: start.ISO8601Format()), .init(name: "to", value: end.ISO8601Format())]
    }
}
