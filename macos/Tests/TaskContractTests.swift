import XCTest
@testable import SkillAtlasCore

final class TaskContractTests: XCTestCase {
    func testTaskFieldsAndRewardValidationShareServerFixture() throws {
        struct Contract: Decodable { let fixtures: Fixtures }
        struct Fixtures: Decodable { let task: TaskWrite }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try APIClient.decoder().decode(Contract.self, from: Data(contentsOf: root.appendingPathComponent("server/contracts/task.yaml"))).fixtures.task
        try fixture.validate(); XCTAssertEqual(fixture.skills.first?.rewardLevels, 2)
        XCTAssertEqual(try APIClient.decoder().decode(TaskWrite.self, from: APIClient.body(fixture)), fixture)
        var invalid = fixture; invalid.skills.append(fixture.skills[0]); XCTAssertThrowsError(try invalid.validate())
        invalid = fixture; invalid.skills[0].rewardLevels = -1; XCTAssertThrowsError(try invalid.validate())
        XCTAssertTrue(TaskStatus.inProgress.canConclude); XCTAssertFalse(TaskStatus.success.canConclude)
    }
}
