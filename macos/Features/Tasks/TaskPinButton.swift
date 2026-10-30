import SwiftUI

struct TaskPinButton: View {
    @Environment(ApplicationStore.self) private var store
    let task: TaskRecord
    @State private var isSaving = false
    @State private var error: String?
    private var actionTitle: String { task.pinned ? "取消置顶" : "置顶" }

    var body: some View {
        Button(action: togglePinned) {
            Image(systemName: task.pinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(task.pinned ? Color.primary : AtlasTheme.muted)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }.buttonStyle(.borderless)
            .disabled(isSaving || store.account.isOffline || store.tasks.actingTaskIds.contains(task.id))
            .help(actionTitle)
            .accessibilityLabel("\(actionTitle)：\(task.title)")
            .accessibilityValue(task.pinned ? "已置顶" : "未置顶")
            .accessibilityIdentifier("task-pin-\(task.id)")
            .alert("置顶未更新", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("好") { error = nil }
            } message: { Text(error ?? "") }
    }

    private func togglePinned() {
        guard !isSaving, !store.account.isOffline, !store.tasks.actingTaskIds.contains(task.id) else { return }
        isSaving = true
        var draft = task.write
        draft.pinned.toggle()
        Task {
            defer { isSaving = false }
            do { _ = try await store.tasks.save(draft) }
            catch { self.error = error.localizedDescription }
        }
    }
}
