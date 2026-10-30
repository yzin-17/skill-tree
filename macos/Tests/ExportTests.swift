import XCTest
@testable import SkillAtlasCore

final class ExportTests: XCTestCase {
    let owner = UUID().uuidString.lowercased()
    func document(extra: [String: JSONValue] = [:], badCount: Bool = false) -> ExportDocument {
        var datasets = Dictionary(uniqueKeysWithValues: ExportDocument.datasetNames.map { ($0, [JSONValue]()) })
        var tree: [String: JSONValue] = ["id": .string(UUID().uuidString.lowercased()), "name": .string("测试技能树")]
        tree.merge(extra) { _, new in new }; datasets["skill_trees"] = [.object(tree)]
        var counts = datasets.mapValues(\.count); if badCount { counts["skills"] = 2 }
        return .init(format: "skill-atlas-export", formatVersion: 1, exportedAt: .now, account: .init(id: owner, email: "test@example.invalid", timezone: "Asia/Shanghai", createdAt: .now), datasets: datasets, counts: counts)
    }
    func testJSONFileRoundTripPreservesDatasetsAndLargeIntegers() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skillatlas-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let value = document(extra: ["sort_order": .integer(9_007_199_254_740_991)])
        let file = dir.appendingPathComponent("backup.json"); try value.saveVerified(to: file)
        let decoded = try APIClient.decoder().decode(ExportDocument.self, from: Data(contentsOf: file))
        XCTAssertEqual(decoded.datasets, value.datasets); XCTAssertEqual(decoded.counts, value.counts)
        XCTAssertThrowsError(try decoded.validate(accountId: UUID().uuidString))
    }
    func testInvalidCountsPrivateFieldsAndBrokenReferencesAreRejected() throws {
        XCTAssertThrowsError(try document(badCount: true).fileData())
        XCTAssertThrowsError(try document(extra: ["token_hash": .string("forbidden")]).fileData())
        let base = document(); var sets = base.datasets
        sets["skills"] = [.object(["id": .string(UUID().uuidString), "tree_id": .string(UUID().uuidString), "parent_skill_id": .null])]
        let invalid = ExportDocument(format: base.format, formatVersion: 1, exportedAt: .now, account: base.account, datasets: sets, counts: sets.mapValues(\.count))
        XCTAssertThrowsError(try invalid.fileData())
    }

    func testWriteDeniedPreservesExistingBackup() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("skillatlas-export-denied-\(UUID().uuidString)")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? manager.removeItem(at: directory)
        }
        let file = directory.appendingPathComponent("backup.json")
        try document().saveVerified(to: file)
        let original = try Data(contentsOf: file)
        try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        XCTAssertThrowsError(try document().saveVerified(to: file)) { error in
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: directory.path), ["backup.json"])
    }
}
