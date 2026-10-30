import SwiftUI

@MainActor @Observable
final class SkillLibrary {
    private(set) var trees: [SkillTreeRecord] = []
    private(set) var skills: [SkillRecord] = []
    private(set) var links: [SkillLinkRecord] = []
    private(set) var isLoading = false
    var errorMessage: String?
    private let client: APIClient?
    private let account: AccountController
    private let local: LocalFocusStore?
    init(client: APIClient?, account: AccountController, local: LocalFocusStore? = nil) { self.client = client; self.account = account; self.local = local }

    func clear() { trees = []; skills = []; links = []; errorMessage = nil; isLoading = false }
    func restoreCache() throws {
        clear()
        if let owner = account.user?.id {
            trees = try local?.cache(accountId: owner, topic: .trees) ?? []
            skills = try local?.cache(accountId: owner, topic: .skills) ?? []
            links = try local?.cache(accountId: owner, topic: .links) ?? []
        }
    }
    private func persist() {
        guard let owner = account.user?.id else { return }
        do {
            try local?.saveCache(trees, accountId: owner, topic: .trees)
            try local?.saveCache(skills, accountId: owner, topic: .skills)
            try local?.saveCache(links, accountId: owner, topic: .links)
        } catch { errorMessage = "服务端数据已读取，但本机缓存保存失败：\(error.localizedDescription)" }
    }
    var activeTrees: [SkillTreeRecord] { trees.filter { $0.archivedAt == nil }.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) } }
    var activeSkills: [SkillRecord] {
        let ids = Set(activeTrees.map(\.id)); return skills.filter { $0.archivedAt == nil && ids.contains($0.treeId) }
    }
    func refresh() async {
        guard let owner = account.user?.id else { return }
        isLoading = true
        defer { if account.user?.id == owner { isLoading = false } }
        do {
            async let allTrees: [SkillTreeRecord] = account.request("/v1/skill-trees?include_archived=true")
            async let allSkills: [SkillRecord] = account.request("/v1/skills?include_archived=true")
            async let allLinks: [SkillLinkRecord] = account.request("/v1/skill-links")
            let values = try await (allTrees, allSkills, allLinks)
            guard account.user?.id == owner else { return }
            trees = values.0; skills = values.1; links = values.2; errorMessage = nil; persist()
        } catch { if account.user?.id == owner { errorMessage = error.localizedDescription } }
    }
    func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        try await account.request(path, method: method, body: body)
    }
    func saveTree(_ input: TreeWrite) async throws -> SkillTreeRecord {
        let value: SkillTreeRecord = try await request(input.version == 0 ? "/v1/skill-trees" : "/v1/skill-trees/\(input.id)", method: input.version == 0 ? "POST" : "PATCH", body: APIClient.body(input))
        trees.removeAll { $0.id == value.id }; trees.append(value); persist(); return value
    }
    func saveSkill(_ input: SkillWrite) async throws -> SkillRecord {
        let value: SkillRecord = try await request(input.version == 0 ? "/v1/skills" : "/v1/skills/\(input.id)", method: input.version == 0 ? "POST" : "PATCH", body: APIClient.body(input))
        skills.removeAll { $0.id == value.id }; skills.append(value); persist(); return value
    }
    func delete(_ skill: SkillRecord) async throws {
        struct Result: Decodable, Sendable { let deleted: Bool }
        let result: Result = try await request("/v1/skills/\(skill.id)?version=\(skill.version)", method: "DELETE")
        if result.deleted { skills.removeAll { $0.id == skill.id }; persist() }
    }
    func saveLink(_ input: SkillLinkWrite, existing: SkillLinkRecord? = nil) async throws {
        let value: SkillLinkRecord
        if let existing {
            struct Edit: Encodable { let version: Int; let requiredLevel: Int64 }
            value = try await request("/v1/skill-links/\(existing.id)", method: "PATCH", body: APIClient.body(Edit(version: existing.version, requiredLevel: input.requiredLevel ?? 1)))
        } else { value = try await request("/v1/skill-links", method: "POST", body: APIClient.body(input)) }
        links.removeAll { $0.id == value.id }; links.append(value); persist()
    }
    func removeLink(_ link: SkillLinkRecord) async throws {
        struct Result: Decodable, Sendable { let deleted: Bool }
        let result: Result = try await request("/v1/skill-links/\(link.id)?version=\(link.version)", method: "DELETE")
        if result.deleted { links.removeAll { $0.id == link.id }; persist() }
    }
}
