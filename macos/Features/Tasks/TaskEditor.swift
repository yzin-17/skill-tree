import SwiftUI

struct TaskEditor: View {
    @Environment(ApplicationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskWrite
    @State private var rewards: [String: String]
    @State private var skillSearch = ""
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var saving = false
    @State private var error: String?
    let originalStatus: TaskStatus
    let saved: (String) -> Void
    init(task: TaskRecord?, saved: @escaping (String) -> Void) {
        let value = task?.write ?? TaskWrite(); _draft = State(initialValue: value)
        _rewards = State(initialValue: Dictionary(uniqueKeysWithValues: value.skills.map { ($0.skillId, String($0.rewardLevels)) }))
        _hasDeadline = State(initialValue: value.dueAt != nil); _deadline = State(initialValue: value.dueAt ?? .now)
        originalStatus = value.status; self.saved = saved
    }
    private var suggestions: [SkillRecord] {
        store.library.activeSkills.filter { rewards[$0.id] == nil && (skillSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(skillSearch)) }
    }
    private var valid: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && rewards.values.allSatisfy { value in Int64(value).map { (0...1_000_000).contains($0) } == true }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.version == 0 ? "新建任务" : "编辑任务").font(.title2).padding(24)
            Form {
                Section("任务内容") {
                    TextField("标题", text: $draft.title).accessibilityIdentifier("task-title")
                    TextField("描述", text: $draft.description, axis: .vertical).lineLimit(2...5)
                    TextField("完成条件", text: $draft.successCriteria, axis: .vertical).lineLimit(2...4)
                    if originalStatus.canConclude {
                        Picker("状态", selection: $draft.status) { Text("待开始").tag(TaskStatus.todo); Text("进行中").tag(TaskStatus.inProgress) }
                    } else { LabeledContent("状态", value: originalStatus.label) }
                    Toggle("置顶任务", isOn: $draft.pinned)
                    Toggle("设置截止时间", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("截止", selection: $deadline, displayedComponents: [.date, .hourAndMinute]) }
                }
                Section("关联技能与成功奖励") {
                    if rewards.isEmpty { Text("暂无关联技能").foregroundStyle(AtlasTheme.muted) }
                    ForEach(rewards.keys.sorted(), id: \.self) { id in
                        HStack(spacing: 12) {
                            Text(store.library.skills.first { $0.id == id }?.name ?? "已关联技能").frame(maxWidth: .infinity, alignment: .leading)
                            Text("成功奖励")
                            TextField("0", text: Binding(get: { rewards[id] ?? "0" }, set: { rewards[id] = $0 }))
                                .frame(width: 70).multilineTextAlignment(.trailing).accessibilityLabel("技能成功奖励等级")
                                .help("非负整数；每级 60 XP，0 表示仅关联")
                            Text("级")
                            Button { rewards.removeValue(forKey: id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).help("移除关联")
                        }
                    }
                    TextField("搜索技能", text: $skillSearch)
                    ForEach(suggestions.prefix(12)) { skill in
                        Button { rewards[skill.id] = "0" } label: {
                            HStack { Label(skill.name, systemImage: SkillIcon.find(skill.iconKey).symbol); Spacer(); Image(systemName: "plus") }
                        }.buttonStyle(.plain)
                    }
                    if store.library.activeSkills.isEmpty { Text("暂无可选技能").font(.caption).foregroundStyle(AtlasTheme.muted) }
                }
            }.formStyle(.grouped)
            EditorFooter(error: error, saving: saving, canSave: valid) {
                draft.dueAt = hasDeadline ? deadline : nil
                draft.skills = rewards.sorted { $0.key < $1.key }.compactMap { id, value in Int64(value).map { TaskSkillBinding(skillId: id, rewardLevels: $0) } }
                saving = true
                Task { do { let item = try await store.tasks.save(draft); saved(item.id); dismiss() } catch { self.error = error.localizedDescription }; saving = false }
            }
        }.frame(width: 610, height: 690)
    }
}
