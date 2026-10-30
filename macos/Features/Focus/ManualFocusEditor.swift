import SwiftUI

struct ManualFocusEditor: View {
    @Environment(ApplicationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var skillId = ""
    @State private var taskId = ""
    @State private var startedAt = Date.now.addingTimeInterval(-1500)
    @State private var endedAt = Date.now
    @State private var minutes = "25"
    @State private var seconds = "0"
    @State private var note = ""
    @State private var error: String?
    @State private var id = UUID().uuidString.lowercased()
    private var duration: Int? {
        guard let m = Int(minutes), let s = Int(seconds), m >= 0, m <= 44640, (0...59).contains(s) else { return nil }
        return m * 60 + s
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("手动补录专注").font(.title2).padding(24)
            Form {
                Picker("主技能", selection: $skillId) { Text("请选择").tag(""); ForEach(store.library.activeSkills) { Text($0.name).tag($0.id) } }
                Picker("关联任务", selection: $taskId) { Text("自由专注").tag(""); ForEach(store.tasks.sorted) { Text($0.title).tag($0.id) } }
                DatePicker("开始时间", selection: $startedAt)
                DatePicker("结束时间", selection: $endedAt)
                HStack { Text("有效专注"); TextField("分钟", text: $minutes).frame(width: 75); Text("分"); TextField("秒", text: $seconds).frame(width: 55); Text("秒") }
                TextField("备注", text: $note, axis: .vertical).lineLimit(2...4)
            }.formStyle(.grouped)
            EditorFooter(error: error, saving: false, canSave: !skillId.isEmpty && (duration ?? 0) > 0) {
                do {
                    guard let focus = store.focus, let duration else { throw FocusEngineError.invalidState }
                    let value = FocusSubmission(id: id, skillId: skillId, taskId: taskId.isEmpty ? nil : taskId, startedAt: startedAt, endedAt: endedAt, effectiveSeconds: duration, note: note)
                    try value.validate(); try focus.addManual(value); dismiss()
                } catch { self.error = error.localizedDescription }
            }
        }.frame(width: 540, height: 490)
    }
}
