import Foundation

@main
struct RealClockRuntime {
    @MainActor static func main() async {
        let runtime = URL(fileURLWithPath: CommandLine.arguments[1])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("skillatlas-real-clock-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var client: APIClient?
        var session: AccountSession?
        var failure: Error?
        do {
            let api = APIClient(baseURL: URL(string: "https://localhost:8447")!, certificate: try Data(contentsOf: runtime.appendingPathComponent("tls/cert.der")))
            client = api
            let user: AccountSession = try await api.request("/v1/auth/register", method: "POST", body: APIClient.body(AccountCredentials(email: "real-clock-\(UUID().uuidString.lowercased())@example.invalid", password: UUID().uuidString + UUID().uuidString, timezone: "Asia/Shanghai")))
            session = user
            var tree = TreeWrite(); tree.name = "原生真实时钟诊断"
            let savedTree: SkillTreeRecord = try await api.request("/v1/skill-trees", method: "POST", token: user.token, body: APIClient.body(tree))
            var skill = SkillWrite(); skill.treeId = savedTree.id; skill.name = "真实经过时间"
            let savedSkill: SkillRecord = try await api.request("/v1/skills", method: "POST", token: user.token, body: APIClient.body(skill))
            let local = try LocalFocusStore(url: directory.appendingPathComponent("focus.sqlite"))
            let focus = try FocusCoordinator(store: local)
            try focus.activate(accountId: user.user.id)
            let start = ClockReading.now()
            try focus.start(skillId: savedSkill.id, configuration: .init())
            for _ in 0..<32 { try await Task.sleep(for: .seconds(1)); focus.tick() }
            try focus.pause(); let paused = focus.snapshot?.effectiveSeconds ?? -1
            try await Task.sleep(for: .seconds(3)); focus.tick()
            try require(focus.snapshot?.effectiveSeconds == paused, "暂停期间累计了有效秒数")
            try focus.resume()
            for _ in 0..<32 { try await Task.sleep(for: .seconds(1)); focus.tick() }
            try focus.finish(note: "真实单调时钟、暂停 3 秒；非界面操作")
            let counted = try required(focus.lastFinished, "正计时保存失败")
            let wallElapsed = ClockReading.now().monotonic - start.monotonic
            try require(counted.submission.effectiveSeconds >= 64 && Double(counted.submission.effectiveSeconds) < wallElapsed - 2, "真实时钟有效时间或暂停排除错误")
            try focus.start(skillId: savedSkill.id, configuration: .init(mode: .countdown, targetSeconds: 2))
            try await Task.sleep(for: .seconds(3)); focus.tick()
            try require(focus.snapshot == nil && focus.lastFinished?.submission.effectiveSeconds == 2, "实际倒计时越过目标仍未结束")
            try focus.start(skillId: savedSkill.id, configuration: .init(mode: .pomodoro, targetSeconds: 1, restSeconds: 1, rounds: 2))
            try await Task.sleep(for: .seconds(4)); focus.tick()
            try require(focus.snapshot == nil && focus.lastFinished?.submission.effectiveSeconds == 2, "实际番茄钟休息计分或最后多余休息")
            let sync = FocusSynchronizer(local: local, remote: api, identity: { .init(accountId: user.user.id, token: user.token) })
            try sync.activate(); await sync.synchronize(force: true)
            let records = try local.records(accountId: user.user.id)
            let seconds = records.reduce(0) { $0 + $1.submission.effectiveSeconds }
            try require(records.count == 3 && records.allSatisfy { $0.state == .confirmed } && sync.activityCount == 0, "真实时钟记录上传未确认")
            try require(sync.progress.first?.totalFocusSeconds == Int64(seconds) && sync.progress.first?.timeXp == Int64(seconds / 60), "真实秒数与服务端 XP 不一致")
            let report: [String: Any] = ["date": Date.now.ISO8601Format(), "account_id": user.user.id, "clock": "DispatchTime.now real elapsed", "wall_elapsed_seconds": wallElapsed, "count_up_effective_seconds": counted.submission.effectiveSeconds, "countdown_seconds": 2, "pomodoro_seconds": 2, "confirmed_total_seconds": seconds, "time_xp": seconds / 60, "pause_seconds": 3, "ui_acceptance": false, "system_sleep_tested": false, "result": "passed"]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: runtime.appendingPathComponent("acceptance/native-real-clock.json"), options: .atomic)
            print("PASS：真实经过时间、三种模式、暂停排除、SQLite 保存和 HTTPS 确认；\(seconds) 秒，\(seconds / 60) XP。")
        } catch { failure = error }
        if let client, let session { let _: LogoutResult? = try? await client.request("/v1/auth/logout", method: "POST", token: session.token) }
        if let failure { print("FAIL：\(failure)"); exit(1) }
    }
    static func require(_ result: Bool, _ message: String) throws { if !result { throw APIError(code: "real_clock", message: message) } }
    static func required<T>(_ value: T?, _ message: String) throws -> T { guard let value else { throw APIError(code: "real_clock", message: message) }; return value }
}
