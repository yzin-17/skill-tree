import SwiftUI

@MainActor @Observable
final class AchievementLibrary {
    private(set) var careers: CareerCatalog?
    private(set) var titles: TitleCatalog?
    private(set) var pending: AchievementCommand?
    private(set) var busy = false
    var errorMessage: String?
    private let account: AccountController
    private let local: LocalFocusStore?
    init(account: AccountController, local: LocalFocusStore?) { self.account = account; self.local = local }
    var currentCareer: CareerRecord? { careers?.items.first { $0.id == careers?.currentCareerId } }
    var equippedTitle: TitleRecord? { titles?.items.first { $0.id == titles?.equippedTitleId } }
    func clear() { careers = nil; titles = nil; pending = nil; busy = false; errorMessage = nil }
    func restore() throws {
        clear(); guard let owner = account.user?.id else { return }
        careers = try local?.cache(accountId: owner, topic: .careers)
        titles = try local?.cache(accountId: owner, topic: .titles)
        let values: [AchievementCommand] = try local?.cache(accountId: owner, topic: .achievementCommands) ?? []
        guard values.allSatisfy({ $0.accountId == owner }), values.count <= 1 else { throw FocusEngineError.damagedSnapshot }
        pending = values.first
    }
    func refresh() async {
        guard let owner = account.user?.id else { return }
        do {
            async let a: CareerCatalog = account.request("/v1/career-nodes")
            async let b: TitleCatalog = account.request("/v1/titles")
            let values = try await (a, b)
            guard account.user?.id == owner else { return }
            careers = values.0; titles = values.1; errorMessage = nil
            try local?.saveCache(values.0, accountId: owner, topic: .careers)
            try local?.saveCache(values.1, accountId: owner, topic: .titles)
        } catch { if account.user?.id == owner { errorMessage = error.localizedDescription } }
    }
    func saveCareer(_ input: CareerWrite) async throws {
        try input.conditions.validate()
        let _: CareerRecord = try await account.request(input.version == 0 ? "/v1/career-nodes" : "/v1/career-nodes/\(input.id)", method: input.version == 0 ? "POST" : "PATCH", body: APIClient.body(input))
        await refresh()
    }
    func saveTitle(_ input: TitleWrite) async throws {
        try input.conditions.validate()
        let _: TitleRecord = try await account.request(input.version == 0 ? "/v1/titles" : "/v1/titles/\(input.id)", method: input.version == 0 ? "POST" : "PATCH", body: APIClient.body(input))
        await refresh()
    }
    func transition(_ career: CareerRecord) async throws {
        struct Input: Encodable { let id: String; let version: Int; let fromCareerId: String? }
        let id = UUID().uuidString.lowercased()
        try await perform(path: "/v1/career-nodes/\(career.id)/transition", id: id, career: true, payload: APIClient.body(Input(id: id, version: career.version, fromCareerId: careers?.currentCareerId)))
    }
    func equip(_ title: TitleRecord?) async throws {
        struct Input: Encodable { let id: String; let version: Int? }
        let id = UUID().uuidString.lowercased()
        try await perform(path: title.map { "/v1/titles/\($0.id)/equip" } ?? "/v1/titles/unequip", id: id, career: false, payload: APIClient.body(Input(id: id, version: title?.version)))
    }
    private func perform(path: String, id: String, career: Bool, payload: Data) async throws {
        guard pending == nil, let owner = account.user?.id, let local else { throw APIError(code: "pending_achievement", message: "请先确认尚未完成的成就操作，并确保本机记录存储可用。") }
        let command = AchievementCommand(id: id, accountId: owner, path: path, career: career, payload: payload)
        try local.saveCache([command], accountId: owner, topic: .achievementCommands); pending = command
        try await retryPending()
    }
    func retryPending() async throws {
        guard let command = pending, command.accountId == account.user?.id, !busy else { return }
        busy = true; defer { if account.user?.id == command.accountId { busy = false } }
        do {
            if command.career { let _: CareerCatalog = try await account.request(command.path, method: "POST", body: command.payload) }
            else { let _: TitleCatalog = try await account.request(command.path, method: "POST", body: command.payload) }
            try clearPending(command.accountId)
            await refresh()
        } catch {
            if let status = (error as? APIError)?.httpStatus, (400..<500).contains(status), ![401,408,429].contains(status) { try clearPending(command.accountId) }
            if account.user?.id == command.accountId { errorMessage = error.localizedDescription }
            throw error
        }
    }
    private func clearPending(_ owner: String) throws {
        try local?.saveCache([AchievementCommand](), accountId: owner, topic: .achievementCommands)
        if account.user?.id == owner { pending = nil }
    }
}
