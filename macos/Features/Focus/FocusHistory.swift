import SwiftUI

struct FocusHistoryView: View {
    @Environment(ApplicationStore.self) private var store
    let taskId: String?
    let skillId: String?
    @State private var items: [FocusRecord] = []
    @State private var count: Int64 = 0
    @State private var total: Int64 = 0
    @State private var cursor = ""
    @State private var loading = false
    @State private var error: String?
    @State private var filterDate = false
    @State private var from = Date.now.addingTimeInterval(-30 * 86400)
    @State private var to = Date.now
    @State private var bindingRecord: FocusRecord?
    @State private var detail: FocusRecord?
    @State private var generation = UUID()
    init(taskId: String? = nil, skillId: String? = nil) { self.taskId = taskId; self.skillId = skillId }
    private var requestKey: String { "\(taskId ?? "")/\(skillId ?? "")/\(filterDate)/\(filterDate ? from.timeIntervalSince1970 : 0)/\(filterDate ? to.timeIntervalSince1970 : 0)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("专注历史").font(.title3.weight(.semibold)); Spacer()
                Text("\(count) 次 · \(AtlasFormat.duration(total))").font(.callout).foregroundStyle(AtlasTheme.muted)
                Button { Task { await load(reset: true) } } label: { Image(systemName: "arrow.clockwise") }.help("刷新专注历史")
            }
            HStack {
                Toggle("按日期", isOn: $filterDate).toggleStyle(.checkbox)
                if filterDate {
                    DatePicker("从", selection: $from, displayedComponents: .date)
                    DatePicker("至", selection: $to, displayedComponents: .date)
                }
                Spacer(minLength: 0)
            }.font(.caption)
            if let error { InlineFailure(message: error) { Task { await load(reset: true) } } }
            if items.isEmpty && !loading { Text("暂无专注记录").font(.callout).foregroundStyle(AtlasTheme.muted).padding(.vertical, 22) }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Button { detail = item } label: {
                            Text(store.library.skills.first { $0.id == item.skillId }?.name ?? "历史技能").font(.system(size: 14, weight: .medium))
                        }.buttonStyle(.plain)
                        Text(item.endedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(AtlasTheme.muted)
                        Spacer(minLength: 8)
                        Text(AtlasFormat.duration(item.effectiveSeconds)).font(.callout.weight(.medium)).monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        Text(item.source == "manual" ? "手动补录" : "计时器").foregroundStyle(AtlasTheme.muted)
                        if let id = item.taskId {
                            Button(store.tasks.items.first { $0.id == id }?.title ?? "关联任务") { store.openTask(id) }.lineLimit(1)
                        } else { Text("自由专注").foregroundStyle(AtlasTheme.muted) }
                        Spacer(minLength: 0)
                        Button(item.taskId == nil ? "关联任务" : "更改关联") { bindingRecord = item }.disabled(store.account.isOffline)
                    }.font(.caption)
                    if !item.note.isEmpty { Text(item.note).font(.callout).foregroundStyle(AtlasTheme.muted).lineLimit(2) }
                }.padding(.vertical, 6)
                Divider()
            }
            if loading { ProgressView().controlSize(.small).frame(maxWidth: .infinity) }
            else if !cursor.isEmpty { Button("加载更多") { Task { await load(reset: false) } }.frame(maxWidth: .infinity) }
        }
        .task(id: requestKey) { await load(reset: true) }
        .onChange(of: store.sync?.confirmedFocusRevision) { _, _ in Task { await load(reset: true) } }
        .sheet(item: $bindingRecord) { record in FocusBindingEditor(record: record) { Task { await load(reset: true); await store.tasks.refresh() } } }
        .sheet(item: $detail) { record in FocusRecordDetail(record: record) }
    }
    private func load(reset: Bool) async {
        if !reset && loading { return }
        if reset { generation = UUID(); items = []; cursor = ""; count = 0; total = 0 }
        let current = generation; loading = true
        defer { if generation == current { loading = false } }
        var params = [URLQueryItem(name: "limit", value: "20")]
        if let taskId { params.append(.init(name: "task_id", value: taskId)) }
        if let skillId { params.append(.init(name: "skill_id", value: skillId)) }
        if !reset && !cursor.isEmpty { params.append(.init(name: "cursor", value: cursor)) }
        if filterDate {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: store.account.user?.timezone ?? "") ?? .current
            let start = calendar.startOfDay(for: from), end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to))!
            guard end > start else { error = "结束日期不能早于开始日期。"; return }
            let formatter = ISO8601DateFormatter()
            params.append(.init(name: "from", value: formatter.string(from: start))); params.append(.init(name: "to", value: formatter.string(from: end)))
        }
        var url = URLComponents(); url.path = "/v1/focus-sessions"; url.queryItems = params
        do {
            let page: FocusPage = try await store.account.request(url.string!)
            guard generation == current else { return }
            let existing = Set(items.map(\.id)); items += page.items.filter { !existing.contains($0.id) }
            cursor = page.nextCursor; count = page.count; total = page.totalSeconds; error = nil
        } catch { if generation == current { self.error = error.localizedDescription } }
    }
}

struct FocusBindingEditor: View {
    @Environment(ApplicationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: FocusRecord
    let saved: () -> Void
    @State private var taskId: String
    @State private var saving = false
    @State private var error: String?
    init(record: FocusRecord, saved: @escaping () -> Void) { self.record = record; self.saved = saved; _taskId = State(initialValue: record.taskId ?? "") }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("关联专注记录").font(.title2).padding(24)
            Form {
                Picker("任务", selection: $taskId) {
                    Text("自由专注").tag("")
                    ForEach(store.tasks.sorted) { Text("\($0.title) · \($0.status.label)").tag($0.id) }
                }
            }.formStyle(.grouped)
            EditorFooter(error: error, saving: saving, canSave: true) {
                saving = true
                Task {
                    struct Input: Encodable { let taskId: String?; let version: Int }
                    do {
                        let _: FocusRecord = try await store.account.request("/v1/focus-sessions/\(record.id)/task", method: "PATCH", body: APIClient.body(Input(taskId: taskId.isEmpty ? nil : taskId, version: record.version)))
                        saved(); dismiss()
                    } catch { self.error = error.localizedDescription }; saving = false
                }
            }
        }.frame(width: 500, height: 260)
    }
}

struct FocusRecordDetail: View {
    @Environment(ApplicationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: FocusRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("专注详情").font(.title2); Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text(store.library.skills.first { $0.id == record.skillId }?.name ?? "历史技能").font(.title3)
            LabeledContent("有效专注", value: AtlasFormat.duration(record.effectiveSeconds))
            LabeledContent("来源", value: record.source == "manual" ? "手动补录" : (FocusMode(rawValue: record.mode)?.name ?? "计时器"))
            LabeledContent("开始", value: record.startedAt.formatted(date: .abbreviated, time: .standard))
            LabeledContent("结束", value: record.endedAt.formatted(date: .abbreviated, time: .standard))
            if record.clockAdjusted { Text("系统时间曾调整").font(.callout).foregroundStyle(AtlasTheme.muted) }
            if !record.note.isEmpty { Text(record.note).textSelection(.enabled) }
        }.padding(28).frame(width: 520)
    }
}
