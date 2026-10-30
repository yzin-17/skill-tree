import SwiftUI

struct CareerEditor: View {
    @Environment(ApplicationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CareerWrite
    @State private var conditions: [ConditionDraft]
    @State private var saving = false
    @State private var error: String?
    @State private var icons = false
    init(career: CareerRecord?) {
        let input = career?.write ?? CareerWrite()
        _draft = State(initialValue: input); _conditions = State(initialValue: input.conditions.all.isEmpty ? [.init()] : input.conditions.all.map(ConditionDraft.init))
    }
    private var parents: [CareerRecord] {
        let items = store.achievements.careers?.items ?? []
        var descendants = Set([draft.id]); var previous = -1
        while previous != descendants.count { previous = descendants.count; for item in items where descendants.contains(item.parentCareerId ?? "") { descendants.insert(item.id) } }
        return items.filter { !descendants.contains($0.id) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.version == 0 ? "新建成长阶段" : "编辑成长阶段").font(.title2).padding(24)
            Form {
                Section {
                    TextField("名称", text: $draft.name)
                    TextField("描述", text: $draft.description, axis: .vertical).lineLimit(2...4)
                    HStack { Text("徽章"); Spacer(); Button { icons = true } label: { Label(SkillIcon.find(draft.badgeKey).name, systemImage: SkillIcon.find(draft.badgeKey).symbol) } }
                    Picker("前一阶段", selection: Binding(get: { draft.parentCareerId ?? "" }, set: { draft.parentCareerId = $0.isEmpty ? nil : $0 })) { Text("无，作为起点").tag(""); ForEach(parents) { Text($0.name).tag($0.id) } }
                    TextField("排序", value: $draft.sortOrder, format: .number)
                }
                ConditionEditor(rows: $conditions)
            }.formStyle(.grouped)
            EditorFooter(error: error, saving: saving, canSave: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !conditions.isEmpty, save: save)
        }.frame(width: 590, height: 650).sheet(isPresented: $icons) { IconPicker(selection: $draft.badgeKey) }
    }
    private func save() {
        draft.conditions = .init(all: conditions.map(\.value)); saving = true
        Task { do { try await store.achievements.saveCareer(draft); dismiss() } catch { self.error = AchievementDisplay.message(error.localizedDescription) }; saving = false }
    }
}

struct TitleEditor: View {
    @Environment(ApplicationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TitleWrite
    @State private var conditions: [ConditionDraft]
    @State private var saving = false
    @State private var error: String?
    @State private var icons = false
    init(title: TitleRecord?) {
        let input = title?.write ?? TitleWrite()
        _draft = State(initialValue: input); _conditions = State(initialValue: input.conditions.all.isEmpty ? [.init()] : input.conditions.all.map(ConditionDraft.init))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.version == 0 ? "新建称号" : "编辑称号").font(.title2).padding(24)
            Form {
                Section {
                    TextField("名称", text: $draft.name)
                    TextField("描述", text: $draft.description, axis: .vertical).lineLimit(2...4)
                    HStack { Text("图标"); Spacer(); Button { icons = true } label: { Label(SkillIcon.find(draft.iconKey).name, systemImage: SkillIcon.find(draft.iconKey).symbol) } }
                }
                ConditionEditor(rows: $conditions)
            }.formStyle(.grouped)
            EditorFooter(error: error, saving: saving, canSave: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !conditions.isEmpty, save: save)
        }.frame(width: 590, height: 650).sheet(isPresented: $icons) { IconPicker(selection: $draft.iconKey) }
    }
    private func save() {
        draft.conditions = .init(all: conditions.map(\.value)); saving = true
        Task { do { try await store.achievements.saveTitle(draft); dismiss() } catch { self.error = AchievementDisplay.message(error.localizedDescription) }; saving = false }
    }
}
