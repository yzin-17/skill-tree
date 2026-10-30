import Foundation

public struct ExportDocument: Codable, Sendable {
    public let format: String
    public let formatVersion: Int
    public let exportedAt: Date
    public let account: AccountUser
    public let datasets: [String: [JSONValue]]
    public let counts: [String: Int]
    public static let datasetNames = Set(["skill_trees", "skills", "skill_links", "tasks", "task_skills", "focus_sessions", "task_attempts", "task_attempt_skills", "task_rewards", "task_retry_requests", "task_reversals", "growth_events", "activity_events", "career_nodes", "career_transitions", "titles", "user_titles", "achievement_profiles", "achievement_references", "achievement_commands"])
    public func validate(accountId: String) throws {
        func invalid(_ message: String) -> APIError { .init(code: "invalid_export", message: message) }
        guard format == "skill-atlas-export", formatVersion == 1, account.id == accountId, UUID(uuidString: account.id) != nil,
              Set(datasets.keys) == Self.datasetNames, Set(counts.keys) == Self.datasetNames else { throw invalid("导出格式、版本或账号不一致。") }
        var ids: [String: Set<String>] = [:]
        var rows: [String: [[String: JSONValue]]] = [:]
        let withoutId: Set<String> = ["task_skills", "task_attempt_skills", "user_titles", "achievement_profiles", "achievement_references"]
        for (name, records) in datasets {
            guard counts[name] == records.count else { throw invalid("数据集 \(name) 的记录数不一致。") }
            ids[name] = []
            for record in records {
                guard case .object(let fields) = record else { throw invalid("导出包含无效记录。") }
                try Self.checkPrivateFields(record)
                rows[name, default: []].append(fields)
                if !withoutId.contains(name) {
                    guard let id = fields["id"]?.string, UUID(uuidString: id) != nil, ids[name, default: []].insert(id).inserted else { throw invalid("数据集 \(name) 存在缺失或重复的标识。") }
                }
            }
        }
        let references: [String: [String: String]] = [
            "skills": ["tree_id": "skill_trees", "parent_skill_id": "skills"], "skill_links": ["from_skill_id": "skills", "to_skill_id": "skills"],
            "task_skills": ["task_id": "tasks", "skill_id": "skills"], "focus_sessions": ["skill_id": "skills", "task_id": "tasks"], "task_attempts": ["task_id": "tasks"],
            "task_attempt_skills": ["attempt_id": "task_attempts", "skill_id": "skills"], "task_rewards": ["attempt_id": "task_attempts", "skill_id": "skills", "growth_event_id": "growth_events"],
            "task_retry_requests": ["task_id": "tasks"], "task_reversals": ["attempt_id": "task_attempts"], "growth_events": ["skill_id": "skills", "reverses_event_id": "growth_events"],
            "career_nodes": ["parent_career_id": "career_nodes"], "career_transitions": ["from_career_id": "career_nodes", "to_career_id": "career_nodes"],
            "user_titles": ["title_id": "titles"], "achievement_profiles": ["current_career_id": "career_nodes", "equipped_title_id": "titles"], "achievement_references": ["skill_id": "skills", "task_id": "tasks"]
        ]
        for (name, fields) in references {
            for row in rows[name] ?? [] {
                for (field, target) in fields {
                    let optional = ["parent_skill_id", "parent_career_id", "from_career_id", "reverses_event_id"].contains(field) || ["achievement_profiles", "achievement_references"].contains(name) || (name == "focus_sessions" && field == "task_id")
                    if optional && (row[field] == nil || row[field] == .null) { continue }
                    guard let id = row[field]?.string, ids[target]?.contains(id) == true else { throw invalid("\(name).\(field) 的历史引用缺失。") }
                }
            }
        }
        for row in rows["growth_events"] ?? [] {
            let target = row["event_type"]?.string == "focus_accrual" ? "focus_sessions" : "task_attempts"
            guard let id = row["source_id"]?.string, ids[target]?.contains(id) == true else { throw invalid("成长流水缺少原始来源。") }
        }
    }
    private static func checkPrivateFields(_ value: JSONValue) throws {
        switch value {
        case .object(let fields):
            for (key, child) in fields {
                guard !["password_hash", "token", "token_hash", "request_hash", "create_hash", "result_json"].contains(key) else { throw APIError(code: "private_export_field", message: "导出包含不应保存的认证或内部字段。") }
                try checkPrivateFields(child)
            }
        case .array(let children): for child in children { try checkPrivateFields(child) }
        default: break
        }
    }
    public func fileData() throws -> Data {
        try validate(accountId: account.id)
        return try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: APIClient.body(self)), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
    public func saveVerified(to url: URL) throws {
        let data = try fileData()
        try data.write(to: url, options: .atomic)
        let saved = try Data(contentsOf: url)
        let decoded = try APIClient.decoder().decode(ExportDocument.self, from: saved)
        try decoded.validate(accountId: account.id)
        guard saved == data, decoded.counts == counts else { throw APIError(code: "export_readback", message: "文件已写入，但重新读取校验失败。") }
    }
}
