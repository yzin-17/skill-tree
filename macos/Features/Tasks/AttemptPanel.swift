import SwiftUI

struct AttemptPanel<Summary: View>: View {
    @Environment(ApplicationStore.self) private var store
    let task: TaskRecord
    @ViewBuilder var summary: Summary
    @State private var history: TaskAttemptHistory?
    @State private var loading = false
    @State private var error: String?
    @State private var action: AttemptAction?
    @State private var reason = ""
    @State private var showHistory = false
    private var pending: [DurableTaskCommand] { store.tasks.commands.filter { $0.taskId == task.id } }
    private var busy: Bool { store.tasks.actingTaskIds.contains(task.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("第 \(task.currentAttemptNo) 次尝试").font(.callout).foregroundStyle(AtlasTheme.muted)
            if let error { InlineFailure(message: error) { Task { await reload() } } }
            if !pending.isEmpty {
                ForEach(pending) { command in
                    VStack(alignment: .leading, spacing: 10) {
                        Label("上次操作的结果尚未确认", systemImage: "arrow.triangle.2.circlepath").font(.callout)
                        Text(command.failure ?? "请求已保存在本机。").font(.caption).foregroundStyle(AtlasTheme.muted)
                        Button("重新确认原结果") { perform { try await store.tasks.execute(command) } }.disabled(busy || store.account.isOffline)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(AtlasTheme.surface)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { focusAction; resultActions }
                    VStack(alignment: .leading, spacing: 10) { focusAction; HStack { resultActions } }
                }
            }
            Divider()
            summary
            Divider()
            DisclosureGroup(isExpanded: $showHistory) {
            HStack { Spacer(); Button { Task { await reload() } } label: { Label("刷新尝试记录", systemImage: "arrow.clockwise") } }
            if let history {
                if history.items.isEmpty { Text("暂无尝试记录").font(.callout).foregroundStyle(AtlasTheme.muted) }
                ForEach(history.items) { item in
                    historyRow(item)
                }
            } else if loading { ProgressView("正在读取尝试记录") }
            } label: { Text("尝试历史 · \(history?.items.count ?? 0) 条") }
        }
        .task(id: task.id) { history = nil; await reload() }
        .onChange(of: task.version) { _, _ in Task { await reload() } }
        .sheet(item: $action) { selected in
            VStack(alignment: .leading, spacing: 22) {
                Text(selected.title).font(.title2.weight(.semibold))
                Text(selected.explanation(task: task)).font(.callout).foregroundStyle(AtlasTheme.muted).fixedSize(horizontal: false, vertical: true)
                if selected.needsReason {
                    TextField("原因或备注（可选）", text: $reason, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Spacer(); Button("返回", role: .cancel) { action = nil }
                    Button("确认") { action = nil; confirm(selected) }.buttonStyle(.borderedProminent).disabled(reason.count > 4000)
                }
            }.padding(28).frame(width: 450)
        }
    }
    @ViewBuilder private var focusAction: some View {
        if task.status.canConclude {
            Button("继续专注", systemImage: "play.fill") { store.prepareFocus(skillId: task.skills.first?.skillId, taskId: task.id) }.buttonStyle(.borderedProminent)
        }
    }
    private var resultActions: some View {
                Group {
                    if task.status.canConclude {
                        Button("确认成功", systemImage: "checkmark") { reason = ""; action = .success }
                        Button("记录失败") { reason = ""; action = .failure }
                    }
                    if task.status == .failed { Button("开始新的尝试", systemImage: "arrow.counterclockwise") { reason = ""; action = .retry } }
                    if busy { ProgressView().controlSize(.small) }
                }.disabled(busy || store.account.isOffline)
    }
    @ViewBuilder private func historyRow(_ item: TaskAttemptDetail) -> some View {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("第 \(item.attempt.attemptNo) 次 · \(item.attempt.result == "success" ? "成功" : "失败")").font(.callout.weight(.medium))
                            if item.reversal != nil { Text("已撤销").font(.caption).foregroundStyle(AtlasTheme.muted) }
                            Spacer()
                            Text(item.attempt.concludedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(AtlasTheme.muted)
                        }
                        if !item.attempt.reason.isEmpty { Text(item.attempt.reason).font(.callout).textSelection(.enabled) }
                        ForEach(item.attempt.skillSnapshot) { binding in
                            HStack {
                                Text(store.library.skills.first { $0.id == binding.skillId }?.name ?? "历史技能")
                                Spacer()
                                Text(item.attempt.result == "success" ? "+\(binding.rewardLevels * 60) XP" : "无额外奖励")
                            }.font(.caption).foregroundStyle(AtlasTheme.muted)
                        }
                        if let reversal = item.reversal {
                            Text("撤销：\(reversal.reason.isEmpty ? "未填写原因" : reversal.reason) · \(reversal.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(AtlasTheme.muted)
                        } else if item.attempt.attemptNo == task.currentAttemptNo && [.success, .failed].contains(task.status) {
                            Button("撤销这次结果") { reason = ""; action = .reverse(item.attempt) }.font(.caption).disabled(busy || !pending.isEmpty || store.account.isOffline)
                        }
                    }.padding(.vertical, 12)
                    Divider().opacity(0.4)
    }
    private func reload() async {
        let id = task.id; loading = true
        defer { loading = false }
        do { history = try await store.tasks.history(id); error = nil } catch { self.error = error.localizedDescription }
    }
    private func confirm(_ selection: AttemptAction) {
        let note = reason
        perform {
            switch selection {
            case .success: try await store.tasks.conclude(task, result: "success", reason: note)
            case .failure: try await store.tasks.conclude(task, result: "failed", reason: note)
            case .retry: try await store.tasks.retry(task)
            case .reverse(let attempt): try await store.tasks.reverse(attempt, reason: note)
            }
        }
    }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do { try await operation(); error = nil; await reload(); await store.sync?.synchronize(force: true); await store.achievements.refresh() }
            catch { self.error = error.localizedDescription }
        }
    }
}

private enum AttemptAction: Identifiable {
    case success, failure, retry, reverse(TaskAttemptRecord)
    var id: String { switch self { case .success: "success"; case .failure: "failure"; case .retry: "retry"; case .reverse(let a): a.id } }
    var title: String { switch self { case .success: "确认任务成功"; case .failure: "记录这次失败"; case .retry: "开始新的尝试"; case .reverse: "撤销这次结果" } }
    var needsReason: Bool { if case .retry = self { false } else { true } }
    func explanation(task: TaskRecord) -> String {
        switch self {
        case .success: "第 \(task.currentAttemptNo) 次尝试将记为成功，并按当前关联技能分别发放奖励。总计 \(task.skills.reduce(Int64(0)) { $0 + $1.rewardLevels * 60 }) XP。"
        case .failure: "这次尝试会计入失败记录。已经获得的专注时间 XP 会保留，之后可以重试。"
        case .retry: "任务将回到进行中，开始第 \(task.currentAttemptNo + 1) 次尝试。之前的记录会保留，重试本身不发放奖励。"
        case .reverse: "原记录和撤销原因会保留。成功奖励会被扣回，时间 XP 保留；任务会进入下一次尝试。称号资格会按新的进度重新计算。"
        }
    }
}
