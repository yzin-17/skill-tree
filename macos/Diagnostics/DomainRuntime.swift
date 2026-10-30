import Foundation

@main
struct DomainRuntime {
    @MainActor static func main() async {
        let runtime = URL(fileURLWithPath: CommandLine.arguments[1])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("skillatlas-domain-\(UUID().uuidString)")
        let vault = KeychainSessionVault(service: "local.skillatlas.domain.\(UUID().uuidString)")
        defer { try? vault.clear(); try? FileManager.default.removeItem(at: directory) }
        var sessions: [AccountSession] = []
        var api: APIClient?
        var failed: Error?
        do {
            let client = APIClient(baseURL: URL(string: "https://localhost:8447")!, certificate: try Data(contentsOf: runtime.appendingPathComponent("tls/cert.der")))
            api = client
            let account = AccountController(client: client, vault: vault)
            let email = "domain-\(UUID().uuidString.lowercased())@example.invalid"
            let password = UUID().uuidString + UUID().uuidString
            await account.authenticate(email: email, password: password, create: true)
            let session = try requireValue(account.session, "原生账号注册"); sessions.append(session)
            let local = try LocalFocusStore(url: directory.appendingPathComponent("cache.sqlite"))
            let library = SkillLibrary(client: client, account: account, local: local)
            let tasks = TaskLibrary(account: account, local: local)
            let achievements = AchievementLibrary(account: account, local: local)
            var treeWrite = TreeWrite(); treeWrite.name = "原生接口验收 · 开发"
            let tree = try await library.saveTree(treeWrite)
            treeWrite = TreeWrite(); treeWrite.name = "原生接口验收 · 基础"
            let secondTree = try await library.saveTree(treeWrite)
            var skillWrite = SkillWrite(); skillWrite.treeId = tree.id; skillWrite.name = "Go"; skillWrite.iconKey = "code"
            let go = try await library.saveSkill(skillWrite)
            skillWrite = SkillWrite(); skillWrite.treeId = secondTree.id; skillWrite.name = "HTTP"; skillWrite.iconKey = "network"
            let http = try await library.saveSkill(skillWrite)
            var link = SkillLinkWrite(); link.fromSkillId = go.id; link.toSkillId = http.id; link.requiredLevel = 2
            try await library.saveLink(link)
            let locked: SkillProgress = try await account.request("/v1/skills/\(go.id)/progress")
            try check(!locked.unlocked && locked.missingPrerequisites.first?.skillId == http.id, "跨树前置方向")
            var taskWrite = TaskWrite(); taskWrite.title = "完成接口诊断"; taskWrite.successCriteria = "完成全部原生 API DTO 验证"; taskWrite.skills = [.init(skillId: go.id, rewardLevels: 2), .init(skillId: http.id, rewardLevels: 1)]
            var task = try await tasks.save(taskWrite)
            var career = CareerWrite(); career.name = "接口开发者"; career.badgeKey = "code"
            career.conditions = .init(all: [.init(type: .skillLevel, skillId: go.id, gte: 3), .init(type: .focusMinutes, skillId: go.id, gte: 1), .init(type: .taskSuccessCount, gte: 1), .init(type: .specificTaskSuccess, taskId: task.id, gte: nil)])
            try await achievements.saveCareer(career)
            var title = TitleWrite(); title.name = "首次达成"; title.iconKey = "star"; title.conditions = .init(all: [.init(type: .specificTaskSuccess, taskId: task.id, gte: nil)])
            try await achievements.saveTitle(title)
            let manual = FocusSubmission(skillId: go.id, taskId: task.id, startedAt: .now.addingTimeInterval(-80), endedAt: .now, effectiveSeconds: 70, note: "原生诊断补录")
            let _: FocusSettlement = try await account.request("/v1/focus-sessions", method: "POST", body: APIClient.body(manual))
            await achievements.refresh()
            try check(achievements.careers?.items.first?.evaluation.evidence.first(where: { $0.condition.type == .focusMinutes })?.current == 0, "补录排除于计时成就")
            var engine = FocusEngine(); let start = Date.now.addingTimeInterval(-61)
            _ = try engine.start(accountId: session.user.id, skillId: go.id, taskId: task.id, configuration: .init(), at: .init(monotonic: 0, wall: start))
            _ = try engine.finish(at: .init(monotonic: 60, wall: start.addingTimeInterval(60)))
            let timed = try FocusSubmission(snapshot: requireValue(engine.snapshot, "计时快照"))
            let _: FocusSettlement = try await account.request("/v1/focus-sessions", method: "POST", body: APIClient.body(timed))
            try await tasks.conclude(task, result: "failed", reason: "诊断第一次失败")
            task = try await tasks.reload(task.id); try await tasks.retry(task)
            task = try await tasks.reload(task.id); try await tasks.conclude(task, result: "success", reason: "诊断重试成功")
            task = try await tasks.reload(task.id)
            try check(task.attemptSummary.successRate == 0.5 && task.attemptSummary.retries == 1 && tasks.commands.isEmpty, "结算与持久请求确认")
            await achievements.refresh()
            let eligibleCareer = try requireValue(achievements.careers?.items.first, "职业列表")
            try check(eligibleCareer.evaluation.eligible, "四类条件同时满足")
            try await achievements.transition(eligibleCareer)
            let unlockedTitle = try requireValue(achievements.titles?.items.first, "称号列表")
            try check(unlockedTitle.unlockedAt != nil, "自动解锁称号")
            try await achievements.equip(unlockedTitle)
            try check(achievements.currentCareer?.id == career.id && achievements.equippedTitle?.id == title.id && achievements.pending == nil, "转职与唯一佩戴确认")
            let stats: StatisticsSummary = try await account.request("/v1/stats/summary")
            try check(stats.totals.focusSeconds == 130 && stats.totals.timeXp == 2 && stats.totals.taskBonusXp == 180 && stats.totals.attempts.successRate == 0.5 && stats.careerHistory.count == 1 && stats.titleHistory.count >= 2, "统计 DTO 与时间/奖励/历史")
            let retryId = try requireValue(stats.sources.retryIds.first, "重试来源")
            let retry: RetryRecord = try await account.request("/v1/task-retries/\(retryId)")
            try check(retry.nextAttemptNo == 2, "重试下钻")
            for id in stats.sources.growthIds { let _: GrowthRecord = try await account.request("/v1/growth-events/\(id)") }
            let events: ActivityPage = try await account.request("/v1/activity-events?limit=200")
            try check(events.items.contains { $0.type == "attempt.success" } && events.items.contains { $0.type == "growth.accrued" }, "活动类型与元数据")
            let history = try await tasks.history(task.id)
            let success = try requireValue(history.items.first { $0.attempt.result == "success" }, "成功历史")
            try await tasks.reverse(success.attempt, reason: "原生诊断撤销")
            await achievements.refresh()
            let regressed: SkillProgress = try await account.request("/v1/skills/\(go.id)/progress")
            try check(regressed.totalXp == 2 && !regressed.unlocked, "撤销奖励保留时间并恢复软锁")
            try check(achievements.currentCareer?.id == career.id && achievements.equippedTitle == nil && achievements.titles?.items.first?.unlockedAt != nil, "职业历史和称号回退")
            let after: StatisticsSummary = try await account.request("/v1/stats/summary")
            try check(after.totals.taskBonusXp == 0 && after.totals.attempts.successes == 0 && after.totals.attempts.failures == 1, "撤销后统计")
            let exported: ExportDocument = try await account.request("/v1/export")
            try exported.validate(accountId: session.user.id)
            let file = runtime.appendingPathComponent("acceptance/native-domain-export.json")
            try exported.saveVerified(to: file)
            try check(exported.counts["focus_sessions"] == 2 && exported.counts["task_attempts"] == 2 && exported.counts["task_reversals"] == 1, "导出事实与读取校验")
            try await account.updateTimezone("UTC")
            let restored = AccountController(client: client, vault: vault); await restored.restore()
            try check(restored.user?.timezone == "UTC", "时区保存与钥匙串恢复")
            let secondLogin: AccountSession = try await client.request("/v1/auth/login", method: "POST", body: APIClient.body(AccountCredentials(email: email, password: password)))
            sessions.append(secondLogin)
            try check(secondLogin.user.id == session.user.id && secondLogin.token != session.token, "另一真实登录会话")
            let fromSecondLogin: TaskRecord = try await client.request("/v1/tasks/\(task.id)", token: secondLogin.token)
            let secondExport: ExportDocument = try await client.request("/v1/export", token: secondLogin.token)
            try check(fromSecondLogin.status == .inProgress && fromSecondLogin.currentAttemptNo == 3 && secondExport.counts == exported.counts, "另一登录会话读取一致业务记录")
            let other: AccountSession = try await client.request("/v1/auth/register", method: "POST", body: APIClient.body(AccountCredentials(email: "domain-other-\(UUID().uuidString.lowercased())@example.invalid", password: UUID().uuidString + UUID().uuidString, timezone: "Asia/Shanghai")))
            sessions.append(other)
            do { let _: RetryRecord = try await client.request("/v1/task-retries/\(retryId)", token: other.token); throw APIError(code: "check", message: "跨账号来源泄漏") }
            catch let error as APIError where error.httpStatus == 404 {}
            let empty: ExportDocument = try await client.request("/v1/export", token: other.token)
            try check(empty.counts.values.reduce(0, +) == 0, "第二账号导出隔离")
            let reopened = try LocalFocusStore(url: directory.appendingPathComponent("cache.sqlite"))
            let cached: [SkillRecord] = try reopened.cache(accountId: session.user.id, topic: .skills) ?? []
            try check(cached.count == 2 && reopened.taskCommands(accountId: session.user.id).isEmpty, "SQLite 重开保留缓存且已确认请求清空")
            let report: [String: Any] = ["date": Date.now.ISO8601Format(), "account_id": session.user.id, "other_account_id": other.user.id, "checks": 19, "transport": "native URLSession HTTPS", "clock": "injected", "ui_acceptance": false, "result": "passed"]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: runtime.appendingPathComponent("acceptance/native-domain-runtime.json"), options: .atomic)
            print("PASS：原生控制器、SwiftData、真实 HTTPS 与 Docker 领域链路；界面和实际计时不在本次范围。")
        } catch { failed = error }
        if let api { for session in sessions { let _: LogoutResult? = try? await api.request("/v1/auth/logout", method: "POST", token: session.token) } }
        if let failed { print("FAIL：\(failed)"); exit(1) }
    }
    static func check(_ value: Bool, _ message: String) throws { if !value { throw APIError(code: "native_domain", message: message) } }
    static func requireValue<T>(_ value: T?, _ message: String) throws -> T { guard let value else { throw APIError(code: "native_domain", message: message) }; return value }
}
