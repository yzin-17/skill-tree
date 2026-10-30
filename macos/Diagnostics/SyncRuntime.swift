import Foundation

private actor DroppedResponseRemote: FocusRemote {
    let client: APIClient
    var droppedEvent = false
    var droppedFocus = false
    init(client: APIClient) { self.client = client }
    func uploadActivity(_ value: FocusActivitySubmission, token: String) async throws -> String {
        let id = try await client.uploadActivity(value, token: token)
        if !droppedEvent { droppedEvent = true; throw URLError(.networkConnectionLost) }
        return id
    }
    func uploadFocus(_ value: FocusSubmission, token: String) async throws -> FocusSettlement {
        let result = try await client.uploadFocus(value, token: token)
        if !droppedFocus { droppedFocus = true; throw URLError(.networkConnectionLost) }
        return result
    }
    func fetchProgress(token: String) async throws -> [SkillProgress] { try await client.fetchProgress(token: token) }
}

@main
struct SyncRuntime {
    @MainActor static func main() async {
        let runtime = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        var sessions: [AccountSession] = []
        var client: APIClient?
        var failure: Error?
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("skillatlas-native-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let api = APIClient(baseURL: URL(string: "https://localhost:8447")!, certificate: try Data(contentsOf: runtime.appendingPathComponent("tls/cert.der")))
            client = api
            var skills: [SkillRecord] = []
            for index in 1...2 {
                let credentials = AccountCredentials(email: "sync-\(UUID().uuidString.lowercased())@example.invalid", password: UUID().uuidString + "-native-check", timezone: "Asia/Shanghai")
                let session: AccountSession = try await api.request("/v1/auth/register", method: "POST", body: APIClient.body(credentials))
                sessions.append(session)
                var tree = TreeWrite(); tree.name = "原生同步验收 \(index)"
                let savedTree: SkillTreeRecord = try await api.request("/v1/skill-trees", method: "POST", token: session.token, body: APIClient.body(tree))
                var skill = SkillWrite(); skill.treeId = savedTree.id; skill.name = "受控计时输入"
                skills.append(try await api.request("/v1/skills", method: "POST", token: session.token, body: APIClient.body(skill)))
            }
            let url = directory.appendingPathComponent("focus.sqlite")
            var local = try LocalFocusStore(url: url)
            for index in 0...1 {
                var engine = FocusEngine(); let base = Date.now; let owner = sessions[index].user.id
                let started = try engine.start(accountId: owner, skillId: skills[index].id, configuration: .init(), at: .init(monotonic: 0, wall: base))
                try local.commit(accountId: owner, snapshot: engine.snapshot, signals: started)
                if index == 0 {
                    let paused = try engine.pause(at: .init(monotonic: 20, wall: base.addingTimeInterval(20)))
                    try local.commit(accountId: owner, snapshot: engine.snapshot, signals: paused)
                    let resumed = try engine.resume(at: .init(monotonic: 100, wall: base.addingTimeInterval(100)))
                    try local.commit(accountId: owner, snapshot: engine.snapshot, signals: resumed)
                }
                let elapsed: Double = index == 0 ? 150 : 60
                let ended = try engine.finish(at: .init(monotonic: elapsed, wall: base.addingTimeInterval(elapsed)))
                try local.commit(accountId: owner, snapshot: nil, signals: ended, finished: FocusSubmission(snapshot: engine.snapshot!))
            }
            var identity: SyncIdentity? = .init(accountId: sessions[0].user.id, token: sessions[0].token)
            let remote = DroppedResponseRemote(client: api)
            var sync = FocusSynchronizer(local: local, remote: remote, identity: { identity }); try sync.activate()
            await sync.synchronize(force: true)
            try require(sync.pendingCount == 1 && sync.activityCount == 4, "丢失事件响应后队列状态错误")
            await sync.synchronize(force: true)
            try require(sync.pendingCount == 1 && sync.activityCount == 0, "丢失会话响应后原记录未保留")
            local = try LocalFocusStore(url: url)
            sync = FocusSynchronizer(local: local, remote: remote, identity: { identity }); try sync.activate()
            await sync.synchronize(force: true)
            try require(sync.pendingCount == 0 && sync.records.first?.state == .confirmed && sync.progress.first?.timeXp == 1, "重开补传未得到权威 1 XP")
            let first: FocusPage = try await api.request("/v1/focus-sessions", token: sessions[0].token)
            let secondBefore: FocusPage = try await api.request("/v1/focus-sessions", token: sessions[1].token)
            try require(first.count == 1 && first.totalSeconds == 70 && secondBefore.count == 0, "会话重复或错误账号已上传")
            struct Event: Decodable, Sendable { let type: String }
            struct Events: Decodable, Sendable { let items: [Event] }
            let timeline: Events = try await api.request("/v1/activity-events", token: sessions[0].token)
            for type in ["focus.started", "focus.paused", "focus.resumed", "focus.ended"] {
                try require(timeline.items.filter { $0.type == type }.count == 1, "生命周期事件重复或丢失")
            }
            identity = .init(accountId: sessions[1].user.id, token: sessions[1].token); try sync.activate()
            try require(sync.progress.isEmpty && sync.pendingCount == 1, "账号缓存未隔离")
            await sync.synchronize(force: true)
            let second: FocusPage = try await api.request("/v1/focus-sessions", token: sessions[1].token)
            try require(second.count == 1 && second.totalSeconds == 60 && sync.progress.first?.skillId == skills[1].id, "第二账号恢复错误")
            let evidence: [String: Any] = ["date": "2026-10-29", "input": "注入时钟的原生同步链路", "account_ids": sessions.map { $0.user.id },
                "first_seconds": first.totalSeconds, "first_time_xp": 1, "second_seconds": second.totalSeconds, "lifecycle_event_count": 4,
                "event_response_dropped": true, "focus_response_dropped": true, "sqlite_reopened": true, "owner_partition_verified": true]
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: runtime.appendingPathComponent("acceptance/native-sync-runtime.json"))
            print("原生 URLSession + SwiftData + Docker HTTPS：响应丢失、重开补传、4 类事件去重、双账号队列隔离通过。")
        } catch { failure = error }
        if let client {
            for session in sessions { let _: LogoutResult? = try? await client.request("/v1/auth/logout", method: "POST", token: session.token) }
        }
        if let failure { print("原生同步验收失败：\(failure.localizedDescription)"); exit(1) }
        print("验收会话已退出；没有保存或输出密码、令牌。")
    }
    static func require(_ value: Bool, _ message: String) throws { if !value { throw APIError(code: "verification", message: message) } }
}
