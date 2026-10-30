import Foundation

public struct GraphPosition: Sendable, Equatable {
    public let x: Double
    public let y: Double
}
public struct SkillGraphLayout: Sendable {
    public let positions: [String: GraphPosition]
    public let width: Double
    public let height: Double
    public init(skills: [SkillRecord]) {
        let byID = Dictionary(skills.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var groups: [Int: [SkillRecord]] = [:]
        for skill in byID.values {
            var ancestors = Set([skill.id]); var parent = skill.parentSkillId; var depth = 0
            while let id = parent, let value = byID[id], ancestors.insert(id).inserted {
                depth += 1; parent = value.parentSkillId
            }
            groups[depth, default: []].append(skill)
        }
        let rows = groups.values.map(\.count).max() ?? 1
        height = Double(rows) * 148 + 72
        width = Double((groups.keys.max() ?? 0) + 1) * 260 + 72
        var result: [String: GraphPosition] = [:]
        for (depth, values) in groups {
            let ordered = values.sorted { ($0.sortOrder, $0.name, $0.id) < ($1.sortOrder, $1.name, $1.id) }
            let top = (height - Double(ordered.count - 1) * 148) / 2
            for (index, item) in ordered.enumerated() {
                result[item.id] = .init(x: 166 + Double(depth) * 260, y: top + Double(index) * 148)
            }
        }
        positions = result
    }
}
