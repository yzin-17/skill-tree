import SwiftUI

struct TreeEditor: View {
    @Environment(ApplicationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TreeWrite
    @State private var saving = false
    @State private var error: String?
    let saved: (String) -> Void
    init(tree: SkillTreeRecord?, saved: @escaping (String) -> Void) { _draft = State(initialValue: tree?.write ?? TreeWrite()); self.saved = saved }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.version == 0 ? "新建技能树" : "编辑技能树").font(.title2).padding(24)
            Form {
                TextField("名称", text: $draft.name).accessibilityIdentifier("tree-name")
                TextField("描述", text: $draft.description, axis: .vertical).lineLimit(3...5)
                Picker("主题", selection: $draft.themeKey) {
                    Text("星空蓝").tag("blue"); Text("暖金").tag("gold"); Text("鼠尾草").tag("sage"); Text("玫瑰").tag("rose")
                }
                TextField("排序", value: $draft.sortOrder, format: .number)
                if draft.version > 0 { Toggle("归档技能树", isOn: $draft.archived).help("保留全部技能和历史记录") }
            }.formStyle(.grouped)
            EditorFooter(error: error, saving: saving, canSave: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                saving = true
                Task {
                    do { let tree = try await store.library.saveTree(draft); saved(tree.id); dismiss() }
                    catch { self.error = error.localizedDescription }
                    saving = false
                }
            }
        }.frame(width: 480, height: 430)
    }
}
