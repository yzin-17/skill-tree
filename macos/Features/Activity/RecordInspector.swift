import SwiftUI

struct RecordInspector: View {
    @Environment(ApplicationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let event: ActivityRecord?
    let initialSource: RecordSource?
    @State private var path: [RecordSource] = []
    init(event: ActivityRecord) {
        self.event = event
        initialSource = event.type == "focus.recorded" && event.entityType == "focus_session" ? .init(kind: "focus_session", id: event.entityId) : nil
    }
    init(source: RecordSource) { event = nil; initialSource = source }
    private var current: RecordSource? { path.last ?? initialSource }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                if !path.isEmpty { Button { path.removeLast() } label: { Label("返回", systemImage: "chevron.left") } }
                Text(current.map { sourceName($0.kind) } ?? event.map { AchievementDisplay.eventSummary($0) } ?? "记录详情").font(.title2.weight(.semibold))
                Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if path.isEmpty, let event, let xp = event.metadata["awarded_xp"]?.integer { Text("本次已确认 +\(xp) XP").font(.headline).foregroundStyle(AtlasTheme.growth) }
                    if let current {
                        SourceContent(source: current, navigate: { path.append($0) }, close: { dismiss() }).id(current.id)
                    } else if let event { eventContent(event) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 440)
        }.padding(24).frame(width: 560)
    }
    private func eventContent(_ event: ActivityRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(event.occurredAt.formatted(date: .abbreviated, time: .standard)).font(.callout).foregroundStyle(AtlasTheme.muted)
            ForEach(event.skillIds, id: \.self) { id in Button(store.library.skills.first { $0.id == id }?.name ?? "查看技能") { dismiss(); store.openSkill(id) } }
            if let delta = event.metadata["delta_xp"]?.integer { Text("\(delta > 0 ? "+" : "")\(delta) XP").font(.title3).foregroundStyle(AtlasTheme.growth) }
            if let seconds = event.metadata["effective_seconds"]?.integer { LabeledContent("事件时有效专注", value: AtlasFormat.duration(seconds)) }
            if let level = event.metadata["level"]?.integer { LabeledContent("达到等级", value: "Lv.\(level)") }
            if let reason = event.metadata["reason"]?.string, !reason.isEmpty { Text(reason).textSelection(.enabled) }
            Button("查看原始记录") { openSource(event) }
            RecordIdentifier(value: event.id)
        }
    }
    private func openSource(_ event: ActivityRecord) {
        if let id = event.metadata["growth_event_id"]?.string { path.append(.init(kind: "growth_event", id: id)); return }
        if event.type == "task.retried", let id = event.metadata["request_id"]?.string { path.append(.init(kind: "task_retry", id: id)); return }
        if event.type == "skill.level_up", let id = event.metadata["source_id"]?.string { path.append(.init(kind: "growth_source", id: id)); return }
        switch event.entityType {
        case "focus_session", "task_attempt": path.append(.init(kind: event.entityType, id: event.entityId))
        case "task": dismiss(); store.openTask(event.entityId)
        case "skill": dismiss(); store.openSkill(event.entityId)
        case "career", "title": dismiss(); store.destination = .achievements
        default: dismiss(); store.destination = .skills
        }
    }
}

struct RecordIdentifier: View {
    let value: String
    var body: some View {
        DisclosureGroup("记录标识") {
            LabeledContent("记录 ID") { Text(value).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) }.padding(.top, 6)
        }.font(.callout).foregroundStyle(AtlasTheme.muted)
    }
}
