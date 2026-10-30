import SwiftUI

struct SkillLinkEditor: View {
    @Environment(ApplicationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let existing: SkillLinkRecord?
    @State private var draft: SkillLinkWrite
    @State private var level: String
    @State private var saving = false
    @State private var error: String?
    init(skillId: String, existing: SkillLinkRecord?) {
        self.existing = existing
        var input = SkillLinkWrite(); input.fromSkillId = skillId
        if let existing { input.id = existing.id; input.fromSkillId = existing.fromSkillId; input.toSkillId = existing.toSkillId; input.linkType = existing.linkType; input.requiredLevel = existing.requiredLevel }
        _draft = State(initialValue: input); _level = State(initialValue: String(input.requiredLevel ?? 1))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(existing == nil ? "添加技能关系" : "调整前置等级").font(.title2).padding(24)
            Form {
                Picker("关系", selection: $draft.linkType) { ForEach(SkillLinkType.allCases) { Text($0.label).tag($0) } }.disabled(existing != nil)
                endpoint(draft.linkType == .prerequisite ? "目标技能" : "起点技能", selection: $draft.fromSkillId)
                endpoint(draft.linkType == .prerequisite ? "前置技能" : "关联技能", selection: $draft.toSkillId)
                if draft.linkType == .prerequisite { TextField("前置最低等级", text: $level) }
            }.formStyle(.grouped)
            EditorFooter(error: error, saving: saving, canSave: !draft.fromSkillId.isEmpty && !draft.toSkillId.isEmpty && draft.fromSkillId != draft.toSkillId, save: save)
        }.frame(width: 520, height: 410)
    }
    private func endpoint(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("选择技能").tag("")
            ForEach(store.library.skills.filter { $0.archivedAt == nil || [draft.fromSkillId, draft.toSkillId].contains($0.id) }) { skill in
                Text("\(store.library.trees.first { $0.id == skill.treeId }?.name ?? "") / \(skill.name)").tag(skill.id)
            }
        }.disabled(existing != nil)
    }
    private func save() {
        guard draft.linkType == .reference || Int64(level).map({ (1...1_000_000).contains($0) }) == true else { error = "前置等级须为 1–1000000 的整数。"; return }
        draft.requiredLevel = draft.linkType == .reference ? nil : Int64(level)
        saving = true
        Task { do { try await store.library.saveLink(draft, existing: existing); await store.sync?.synchronize(force: true); dismiss() } catch { self.error = error.localizedDescription }; saving = false }
    }
}
