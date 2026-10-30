import SwiftUI

struct SkillEditor: View {
    @Environment(ApplicationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SkillWrite
    @State private var saving = false
    @State private var error: String?
    @State private var showIcons = false
    init(skill: SkillRecord?, treeId: String, parentId: String?) {
        var value = skill?.write ?? SkillWrite(); value.treeId = treeId; value.parentSkillId = parentId
        _draft = State(initialValue: value)
    }
    private var possibleParents: [SkillRecord] {
        var descendants = Set([draft.id])
        var changed = true
        while changed {
            let previous = descendants.count
            for item in store.library.skills where descendants.contains(item.parentSkillId ?? "") { descendants.insert(item.id) }
            changed = descendants.count != previous
        }
        return store.library.skills.filter { $0.treeId == draft.treeId && !descendants.contains($0.id) && ($0.archivedAt == nil || $0.id == draft.parentSkillId) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.version == 0 ? "新建技能" : "编辑技能").font(.title2).padding(24)
            Form {
                TextField("名称", text: $draft.name).accessibilityIdentifier("skill-name")
                TextField("描述", text: $draft.description, axis: .vertical).lineLimit(3...5)
                Picker("技能树", selection: $draft.treeId) { ForEach(store.library.trees) { Text($0.name).tag($0.id) } }.disabled(draft.version > 0)
                    .onChange(of: draft.treeId) { _, _ in draft.parentSkillId = nil }
                Picker("父技能", selection: Binding(get: { draft.parentSkillId ?? "" }, set: { draft.parentSkillId = $0.isEmpty ? nil : $0 })) {
                    Text("无，作为根技能").tag("")
                    ForEach(possibleParents) { Text($0.name).tag($0.id) }
                }
                HStack { Text("图标"); Spacer(); Button { showIcons = true } label: { Label(SkillIcon.find(draft.iconKey).name, systemImage: SkillIcon.find(draft.iconKey).symbol) }; Button("恢复默认") { draft.iconKey = "star" }.font(.caption) }
                TextField("排序", value: $draft.sortOrder, format: .number)
                if draft.version > 0 { Toggle("归档技能", isOn: $draft.archived) }
            }.formStyle(.grouped)
            EditorFooter(error: error, saving: saving, canSave: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.treeId.isEmpty) {
                saving = true
                Task { do { _ = try await store.library.saveSkill(draft); dismiss() } catch { self.error = error.localizedDescription }; saving = false }
            }
        }.frame(width: 520, height: 570).sheet(isPresented: $showIcons) { IconPicker(selection: $draft.iconKey) }
    }
}
