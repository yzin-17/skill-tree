import SwiftUI

struct SourceDetail: View {
    let source: RecordSource
    var body: some View { RecordInspector(source: source) }
}

struct SourceContent: View {
    @Environment(ApplicationStore.self) private var store
    let source: RecordSource
    let navigate: (RecordSource) -> Void
    let close: () -> Void
    @State private var focus: FocusRecord?
    @State private var attempt: TaskAttemptDetail?
    @State private var growth: GrowthRecord?
    @State private var retry: RetryRecord?
    @State private var error: String?
    @State private var loaded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error { InlineFailure(message: error) { Task { await load() } } }
                VStack(alignment: .leading, spacing: 14) {
                    if let focus {
                        Text(store.library.skills.first { $0.id == focus.skillId }?.name ?? "历史技能").font(.title3)
                        LabeledContent("有效时长", value: AtlasFormat.duration(focus.effectiveSeconds))
                        LabeledContent("来源", value: focus.source == "manual" ? "手动补录" : FocusMode(rawValue: focus.mode)?.name ?? "计时专注")
                        LabeledContent("开始", value: focus.startedAt.formatted(date: .abbreviated, time: .standard))
                        LabeledContent("结束", value: focus.endedAt.formatted(date: .abbreviated, time: .standard))
                        if !focus.note.isEmpty { Text(focus.note).textSelection(.enabled) }
                        Button("查看技能") { close(); store.openSkill(focus.skillId) }
                        if let task = focus.taskId { Button(store.tasks.items.first { $0.id == task }?.title ?? "查看关联任务") { close(); store.openTask(task) } }
                    }
                    if let attempt {
                        LabeledContent("尝试编号", value: "第 \(attempt.attempt.attemptNo) 次")
                        LabeledContent("结果", value: attempt.attempt.result == "success" ? "成功" : "失败")
                        LabeledContent("确认时间", value: attempt.attempt.concludedAt.formatted(date: .abbreviated, time: .shortened))
                        if !attempt.attempt.reason.isEmpty { Text(attempt.attempt.reason).textSelection(.enabled) }
                        ForEach(attempt.attempt.skillSnapshot) { binding in
                            LabeledContent(store.library.skills.first { $0.id == binding.skillId }?.name ?? "历史技能", value: "奖励快照 \(binding.rewardLevels) 级")
                        }
                        ForEach(attempt.rewards) { reward in Button("查看奖励 +\(reward.xpAmount) XP") { navigate(.init(kind: "growth_event", id: reward.growthEventId)) } }
                        if let reversal = attempt.reversal { Label("这次结果已撤销", systemImage: "arrow.uturn.backward"); Text(reversal.reason); Text(reversal.createdAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(AtlasTheme.muted) }
                        Button("查看任务与全部历史") { close(); store.openTask(attempt.attempt.taskId) }
                    }
                    if let growth {
                        Text("\(growth.deltaXp > 0 ? "+" : "")\(growth.deltaXp) XP").font(.system(size: 32, weight: .medium)).monospacedDigit()
                        Text(growth.note).font(.callout)
                        Text(growth.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(AtlasTheme.muted)
                        Button("打开原始\(growth.eventType == "focus_accrual" ? "专注会话" : "任务尝试")") { navigate(.init(kind: growth.eventType == "focus_accrual" ? "focus_session" : "task_attempt", id: growth.sourceId)) }
                        if let original = growth.reversesEventId { Button("查看被补偿的奖励流水") { navigate(.init(kind: "growth_event", id: original)) } }
                        Button("查看技能当前进度") { close(); store.openSkill(growth.skillId) }
                    }
                    if let retry {
                        Text("从第 \(retry.previousAttemptNo) 次进入第 \(retry.nextAttemptNo) 次尝试").font(.headline)
                        Text(retry.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(AtlasTheme.muted)
                        Button("查看上一次失败") { navigate(.init(kind: "task_attempt", id: retry.previousAttemptId)) }
                        Button("查看任务") { close(); store.openTask(retry.taskId) }
                    }
                    if loaded && focus == nil && attempt == nil && growth == nil && retry == nil && error == nil { Text("暂无详情").foregroundStyle(AtlasTheme.muted) }
                    if !loaded && error == nil { ProgressView("正在读取原始记录") }
                    RecordIdentifier(value: source.recordId)
                }.frame(maxWidth: .infinity, alignment: .leading)
        }.task(id: source.id) { await load() }
    }
    private func load() async {
        guard UUID(uuidString: source.recordId) != nil else { error = "来源标识无效。"; return }
        loaded = false; error = nil; focus = nil; attempt = nil; growth = nil; retry = nil
        do {
            switch source.kind {
            case "focus_session": focus = try await store.account.request("/v1/focus-sessions/\(source.recordId)")
            case "task_attempt": attempt = try await store.account.request("/v1/task-attempts/\(source.recordId)")
            case "growth_event": growth = try await store.account.request("/v1/growth-events/\(source.recordId)")
            case "task_retry": retry = try await store.account.request("/v1/task-retries/\(source.recordId)")
            case "growth_source":
                do { focus = try await store.account.request("/v1/focus-sessions/\(source.recordId)") }
                catch let error as APIError where error.httpStatus == 404 { attempt = try await store.account.request("/v1/task-attempts/\(source.recordId)") }
            default: break
            }
        } catch { self.error = error.localizedDescription }
        loaded = true
    }
}

func sourceName(_ kind: String) -> String {
    switch kind { case "focus_session": "专注记录"; case "task_attempt": "任务尝试"; case "growth_event": "成长流水"; case "task_retry": "重试记录"; default: "来源记录" }
}

struct SourceList: View {
    let sources: [RecordSource]
    @State private var selected: RecordSource?
    @State private var shown = 30
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if sources.isEmpty { Text("没有原始记录").font(.caption).foregroundStyle(AtlasTheme.muted) }
            ForEach(sources.prefix(shown)) { source in
                Button { selected = source } label: { HStack { Text(sourceName(source.kind)); Spacer(); Text(String(source.recordId.prefix(8))).font(.system(size: 11, design: .monospaced)); Image(systemName: "chevron.right") }.font(.callout) }.buttonStyle(.plain)
            }
            if shown < sources.count { Button("显示更多来源（共 \(sources.count) 条）") { shown += 30 } }
        }.sheet(item: $selected) { SourceDetail(source: $0) }
    }
}
