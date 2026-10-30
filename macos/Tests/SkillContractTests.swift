import XCTest
@testable import SkillAtlasCore

final class SkillContractTests: XCTestCase {
    func testSharedSkillFormsAndIcons() throws {
        struct Contract: Decodable { let icons: [String]; let fixtures: Fixtures }
        struct Fixtures: Decodable { let tree: TreeWrite; let skill: SkillWrite }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let contract = try APIClient.decoder().decode(Contract.self, from: Data(contentsOf: root.appendingPathComponent("server/contracts/skill.yaml")))
        XCTAssertEqual(contract.icons, SkillIcon.all.map(\.id))
        XCTAssertEqual(contract.fixtures.skill.treeId, contract.fixtures.tree.id)
        XCTAssertEqual(contract.fixtures.skill.iconKey, "code")
        let encoded = try APIClient.body(contract.fixtures.skill)
        let roundTrip = try APIClient.decoder().decode(SkillWrite.self, from: encoded)
        XCTAssertEqual(roundTrip.iconKey, "code")
        XCTAssertEqual(roundTrip.id, contract.fixtures.skill.id)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: encoded) as? [String: Any] != nil, true)
    }
}
