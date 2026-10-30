import XCTest
@testable import SkillAtlasCore

final class GraphAndConditionsTests: XCTestCase {
    func skill(_ id: String, parent: String? = nil) -> SkillRecord {
        .init(id: id, treeId: "tree", parentSkillId: parent, name: id, description: "", iconKey: "star", sortOrder: 0, archivedAt: nil, version: 1, createdAt: .distantPast, updatedAt: .distantPast)
    }
    func testLayoutIsStableNonOverlappingAndToleratesInvalidHierarchy() throws {
        let values = [skill("c", parent: "a"), skill("b", parent: "a"), skill("a"), skill("d", parent: "b"), skill("orphan", parent: "missing")]
        let layout = SkillGraphLayout(skills: values)
        XCTAssertEqual(layout.positions, SkillGraphLayout(skills: values.reversed()).positions)
        XCTAssertGreaterThan(try XCTUnwrap(layout.positions["b"]).x, try XCTUnwrap(layout.positions["a"]).x)
        XCTAssertNotEqual(layout.positions["b"], layout.positions["c"])
        XCTAssertEqual(layout.positions.count, values.count)
        XCTAssertEqual(SkillGraphLayout(skills: [skill("a", parent: "b"), skill("b", parent: "a")]).positions.count, 2)
        XCTAssertTrue(SkillGraphLayout(skills: []).positions.isEmpty)
    }
    func testFourConditionTypesAndInvalidReferences() throws {
        let skill = UUID().uuidString; let task = UUID().uuidString
        let valid = AchievementConditions(all: [
            .init(type: .skillLevel, skillId: skill, gte: 2),
            .init(type: .focusMinutes, skillId: skill, gte: 60),
            .init(type: .taskSuccessCount, gte: 3),
            .init(type: .specificTaskSuccess, taskId: task, gte: nil)
        ])
        XCTAssertNoThrow(try valid.validate())
        XCTAssertThrowsError(try AchievementConditions().validate())
        XCTAssertThrowsError(try AchievementConditions(all: [.init(type: .skillLevel, gte: 1)]).validate())
        XCTAssertThrowsError(try AchievementConditions(all: [.init(type: .specificTaskSuccess, taskId: task, gte: 1)]).validate())
        XCTAssertThrowsError(try AchievementConditions(all: [valid.all[0], valid.all[0]]).validate())
        XCTAssertThrowsError(try AchievementConditions(all: [.init(type: .taskSuccessCount, gte: 0)]).validate())
    }
}
