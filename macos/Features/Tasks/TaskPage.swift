import SwiftUI

struct TaskPage: View {
    @Environment(ApplicationStore.self) private var store
    @State private var selected: String?
    @State private var search = ""
    @State private var filter = "active"
    @State private var editor: TaskEditorSelection?
    @State private var cancelTarget: TaskRecord?
    @State private var error: String?
    private var filtered: [TaskRecord] {
        store.tasks.sorted.filter { item in
            (search.isEmpty || item.title.localizedCaseInsensitiveContains(search)) &&
            (filter == "all" || (filter == "active" && [.todo, .inProgress, .failed].contains(item.status)) || item.status.rawValue == filter)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                PageHeading("任务")
                Spacer()
                Button { Task { await store.tasks.refresh() } } label: { Image(systemName: "arrow.clockwise") }.help("刷新任务")
                Button("新建任务", systemImage: "plus") { editor = .init(task: nil) }.controlSize(.large).disabled(store.account.isOffline)
            }.padding(28)
            if let message = store.tasks.errorMessage { InlineFailure(message: message) { Task { await store.tasks.refresh() } }.padding(.horizontal, 28).padding(.bottom, 12) }
            HSplitView {
                VStack(spacing: 14) {
                    TextField("搜索任务", text: $search).textFieldStyle(.roundedBorder).accessibilityIdentifier("task-search")
                    Picker("显示", selection: $filter) {
                        Text("待处理").tag("active"); Text("全部任务").tag("all")
                        ForEach(TaskStatus.allCases) { Text($0.label).tag($0.rawValue) }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                    List(filtered, selection: $selected) { item in
                        TaskListRow(task: item).tag(item.id).padding(.vertical, 6)
                            .contextMenu {
                                Button("编辑") { editor = .init(task: item) }
                                Button(item.pinned ? "取消置顶" : "置顶") { var draft = item.write; draft.pinned.toggle(); save(draft) }
                                if item.status.canCancel { Button("取消任务", role: .destructive) { cancelTarget = item } }
                            }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                        .overlay { if filtered.isEmpty { Text(store.tasks.items.isEmpty ? "还没有任务" : "没有匹配的任务").font(.callout).foregroundStyle(AtlasTheme.muted) } }
                }.padding(.leading, 20).padding(.trailing, 14).frame(minWidth: 220, idealWidth: 290, maxWidth: 360)
                if let item = filtered.first(where: { $0.id == selected }) {
                    TaskDetail(task: item, edit: { editor = .init(task: item) }, cancel: { cancelTarget = item })
                        .id(item.id)
                        .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyWorkspace(symbol: "checklist", title: emptyTitle) {
                        if !store.tasks.items.isEmpty && filtered.isEmpty {
                            Button("清除筛选") { search = ""; filter = "all" }
                        } else {
                            Button(store.tasks.items.isEmpty ? "创建第一个任务" : "新建任务") { editor = .init(task: nil) }.disabled(store.account.isOffline)
                        }
                    }.frame(minWidth: 340)
                }
            }
        }.background(AtlasTheme.ground)
            .onAppear { reveal(store.requestedTaskId) }
            .task(id: store.sync?.records.filter { $0.state == .confirmed }.count) { await store.tasks.refresh() }
            .onChange(of: store.requestedTaskId) { _, value in reveal(value) }
            .onChange(of: filtered.map(\.id)) { _, ids in if let selected, !ids.contains(selected) { self.selected = nil } }
            .sheet(item: $editor) { selection in TaskEditor(task: selection.task) { reveal($0) } }
            .confirmationDialog("取消任务？已存在的专注和尝试历史会保留。", isPresented: Binding(get: { cancelTarget != nil }, set: { if !$0 { cancelTarget = nil } }), titleVisibility: .visible) {
                Button("取消任务", role: .destructive) { if let item = cancelTarget { var draft = item.write; draft.status = .canceled; save(draft) }; cancelTarget = nil }
            }
            .alert("操作未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") { error = nil } } message: { Text(error ?? "") }
    }
    private var emptyTitle: String { store.tasks.items.isEmpty ? "暂无任务" : filtered.isEmpty ? "没有匹配的任务" : "未选择任务" }
    private func reveal(_ id: String?) { if id != nil { search = ""; filter = "all" }; selected = id }
    private func save(_ draft: TaskWrite) { Task { do { _ = try await store.tasks.save(draft) } catch { self.error = error.localizedDescription } } }
}

struct TaskListRow: View {
    let task: TaskRecord
    var open: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let open {
                Button(action: open) { labels }.buttonStyle(.plain)
            } else { labels }
            TaskPinButton(task: task)
            if let open {
                Button(action: open) { Image(systemName: "chevron.right").frame(width: 24, height: 28) }
                    .buttonStyle(.plain).help("查看任务")
                    .accessibilityLabel("查看任务：\(task.title)")
            }
        }.padding(.vertical, 2)
    }
    private var labels: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
            HStack { Text(task.status.label); Spacer(); if task.isOverdue { Label("已逾期", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange) } }
                .font(.caption).foregroundStyle(AtlasTheme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}

struct TaskDetail: View {
    @Environment(ApplicationStore.self) private var store
    let task: TaskRecord
    let edit: () -> Void
    let cancel: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(task.status.label).font(.callout).foregroundStyle(AtlasTheme.muted)
                        Spacer()
                        TaskPinButton(task: task)
                        Button("编辑", action: edit).disabled(store.account.isOffline)
                        if task.status.canCancel {
                            Menu { Button("取消任务", role: .destructive, action: cancel).disabled(store.account.isOffline) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("更多任务操作")
                        }
                    }
                    Text(task.title).font(.system(size: 24, weight: .semibold)).textSelection(.enabled)
                    if let due = task.dueAt { Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar").font(.callout).foregroundStyle(task.isOverdue ? Color.orange : AtlasTheme.muted) }
                }
                detailSection("完成条件", text: task.successCriteria.isEmpty ? "尚未填写完成条件。" : task.successCriteria)
                AttemptPanel(task: task) {
                if !task.description.isEmpty { detailSection("描述", text: task.description) }
                VStack(alignment: .leading, spacing: 10) {
                    Text("关联技能与成功奖励").font(.headline)
                    if task.skills.isEmpty { Text("尚未关联技能。").foregroundStyle(AtlasTheme.muted) }
                    ForEach(task.skills) { binding in
                        let skill = store.library.skills.first { $0.id == binding.skillId }
                        HStack { Label(skill?.name ?? "已关联技能", systemImage: SkillIcon.find(skill?.iconKey ?? "star").symbol); Spacer(); Text(binding.rewardLevels == 0 ? "仅关联" : "+\(binding.rewardLevels) 级 · \(binding.rewardLevels * 60) XP").foregroundStyle(AtlasTheme.muted) }
                    }
                }
                HStack(spacing: 28) {
                    metric("累计专注", value: AtlasFormat.duration(task.totalFocusSeconds))
                    metric("专注次数", value: "\(task.focusCount)")
                    metric("成功率", value: task.attemptSummary.successRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "暂无数据")
                }.padding(.vertical, 4)
                Text("成功 \(task.attemptSummary.successes) 次 · 失败 \(task.attemptSummary.failures) 次 · 重试 \(task.attemptSummary.retries) 次").font(.caption).foregroundStyle(AtlasTheme.muted)
                }
                Divider()
                DisclosureGroup("专注记录 · \(task.focusCount) 次") { FocusHistoryView(taskId: task.id).padding(.top, 12) }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func detailSection(_ title: String, text: String) -> some View { VStack(alignment: .leading, spacing: 10) { Text(title).font(.headline); Text(text).font(.callout).foregroundStyle(AtlasTheme.muted).textSelection(.enabled) } }
    private func metric(_ title: String, value: String) -> some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.caption).foregroundStyle(AtlasTheme.muted); Text(value).font(.system(size: 17, weight: .medium)).monospacedDigit() } }
}

private struct TaskEditorSelection: Identifiable {
    let id = UUID()
    let task: TaskRecord?
}
