import Foundation

public enum SkillLinkType: String, Codable, Sendable, CaseIterable, Identifiable {
    case prerequisite, reference
    public var id: String { rawValue }
    public var label: String { self == .prerequisite ? "前置条件" : "普通关联" }
}
public struct SkillLinkRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let fromSkillId: String
    public let toSkillId: String
    public let linkType: SkillLinkType
    public let requiredLevel: Int64?
    public let version: Int
    public let createdAt: Date
    public let deletedAt: Date?
}
public struct SkillLinkWrite: Codable, Sendable {
    public var id = UUID().uuidString.lowercased()
    public var fromSkillId = ""
    public var toSkillId = ""
    public var linkType = SkillLinkType.prerequisite
    public var requiredLevel: Int64? = 1
}
