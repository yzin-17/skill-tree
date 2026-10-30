import Foundation

public struct SkillTreeRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var description: String
    public var themeKey: String
    public var sortOrder: Int
    public var archivedAt: Date?
    public var version: Int
    public let createdAt: Date
    public var updatedAt: Date
    public var write: TreeWrite { TreeWrite(id: id, name: name, description: description, themeKey: themeKey, sortOrder: sortOrder, archived: archivedAt != nil, version: version) }
}

public struct SkillRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let treeId: String
    public var parentSkillId: String?
    public var name: String
    public var description: String
    public var iconKey: String
    public var sortOrder: Int
    public var archivedAt: Date?
    public var version: Int
    public let createdAt: Date
    public var updatedAt: Date
    public var write: SkillWrite { SkillWrite(id: id, treeId: treeId, parentSkillId: parentSkillId, name: name, description: description, iconKey: iconKey, sortOrder: sortOrder, archived: archivedAt != nil, version: version) }
}

public struct TreeWrite: Codable, Sendable {
    public var id = UUID().uuidString.lowercased()
    public var name = ""
    public var description = ""
    public var themeKey = "blue"
    public var sortOrder = 0
    public var archived = false
    public var version = 0
}

public struct SkillWrite: Codable, Sendable {
    public var id = UUID().uuidString.lowercased()
    public var treeId = ""
    public var parentSkillId: String?
    public var name = ""
    public var description = ""
    public var iconKey = "star"
    public var sortOrder = 0
    public var archived = false
    public var version = 0
}

public struct SkillIcon: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let symbol: String
    public let category: String
    public static let all: [SkillIcon] = [
        .init(id: "star", name: "星标", symbol: "star", category: "通用"),
        .init(id: "code", name: "代码", symbol: "chevron.left.forwardslash.chevron.right", category: "开发"),
        .init(id: "database", name: "数据库", symbol: "externaldrive", category: "开发"),
        .init(id: "network", name: "网络", symbol: "network", category: "开发"),
        .init(id: "terminal", name: "终端", symbol: "terminal", category: "开发"),
        .init(id: "book", name: "阅读", symbol: "book", category: "知识"),
        .init(id: "brain", name: "思考", symbol: "brain", category: "知识"),
        .init(id: "pencil", name: "写作", symbol: "pencil", category: "知识"),
        .init(id: "music", name: "音乐", symbol: "music.note", category: "生活"),
        .init(id: "camera", name: "摄影", symbol: "camera", category: "生活"),
        .init(id: "paint", name: "绘画", symbol: "paintbrush", category: "生活"),
        .init(id: "language", name: "语言", symbol: "character.bubble", category: "知识"),
        .init(id: "heart", name: "健康", symbol: "heart", category: "生活"),
        .init(id: "fitness", name: "运动", symbol: "figure.run", category: "生活"),
        .init(id: "leaf", name: "自然", symbol: "leaf", category: "生活"),
        .init(id: "compass", name: "探索", symbol: "safari", category: "通用")
    ]
    public static func find(_ key: String) -> SkillIcon { all.first { $0.id == key } ?? all[0] }
}
