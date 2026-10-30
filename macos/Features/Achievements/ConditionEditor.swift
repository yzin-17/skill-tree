import SwiftUI

struct ConditionDraft: Identifiable {
    let id = UUID()
    var type: ConditionKind = .skillLevel
    var skillId = ""
    var taskId = ""
    var threshold = "1"
    init(_ source: AchievementCondition? = nil) {
        if let source { type = source.type; skillId = source.skillId ?? ""; taskId = source.taskId ?? ""; threshold = source.gte.map(String.init) ?? "1" }
    }
    var value: AchievementCondition {
        .init(type: type, skillId: type == .specificTaskSuccess || skillId.isEmpty ? nil : skillId, taskId: type == .specificTaskSuccess && !taskId.isEmpty ? taskId : nil, gte: type == .specificTaskSuccess ? nil : Int64(threshold))
    }
}

struct ConditionEditor: View {
    @Environment(ApplicationStore.self) private var store
    @Binding var rows: [ConditionDraft]
    var body: some View {
        Section {
            ForEach($rows) { $row in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Picker("条件", selection: $row.type) { ForEach(ConditionKind.allCases) { Text($0.label).tag($0) } }
                        Button { rows.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }.help("删除条件")
                    }
                    if row.type == .specificTaskSuccess {
                        Picker("任务", selection: $row.taskId) { Text("请选择任务").tag(""); ForEach(store.tasks.sorted) { Text($0.title).tag($0.id) } }
                    } else {
                        Picker("技能", selection: $row.skillId) { Text(row.type == .taskSuccessCount ? "全部技能" : "请选择技能").tag(""); ForEach(store.library.skills) { Text($0.name).tag($0.id) } }
                        TextField(row.type == .skillLevel ? "至少达到等级" : row.type == .focusMinutes ? "至少专注分钟" : "至少成功次数", text: $row.threshold)
                    }
                }.padding(.vertical, 7)
            }
            Button("添加条件", systemImage: "plus") { rows.append(.init()) }.disabled(rows.count >= 32)
        } header: { Text("达成条件（全部满足）") }
    }
}

struct ConditionEvidenceView: View {
    @Environment(ApplicationStore.self) private var store
    let evaluation: ConditionEvaluation
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(evaluation.evidence.enumerated()), id: \.offset) { _, evidence in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Image(systemName: evidence.met ? "checkmark.circle.fill" : "circle").foregroundStyle(evidence.met ? AtlasTheme.growth : AtlasTheme.muted)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(label(evidence.condition)).font(.callout)
                            Text("\(evidence.current) / \(evidence.required) \(evidence.unit)").font(.caption).monospacedDigit().foregroundStyle(AtlasTheme.muted)
                        }
                        Spacer()
                        if let id = evidence.condition.skillId { Button { store.openSkill(id) } label: { Image(systemName: "arrow.up.forward") }.help("查看技能") }
                        if let id = evidence.condition.taskId { Button { store.openTask(id) } label: { Image(systemName: "arrow.up.forward") }.help("查看任务") }
                    }
                    if !evidence.sourceIds.isEmpty {
                        DisclosureGroup("来源记录 \(evidence.sourceIds.count)\(evidence.sourcesTruncated ? "（节选）" : "")") {
                            SourceList(sources: evidence.sourceIds.map { .init(kind: evidence.sourceType, id: $0) }).padding(.top, 8)
                        }.font(.caption).foregroundStyle(AtlasTheme.muted)
                    }
                }
            }
        }
    }
    private func label(_ condition: AchievementCondition) -> String {
        let object = condition.skillId.flatMap { id in store.library.skills.first { $0.id == id }?.name }
            ?? condition.taskId.flatMap { id in store.tasks.items.first { $0.id == id }?.title }
            ?? "全部任务"
        return "\(object) · \(condition.type.label)"
    }
}

struct ConditionProgressSummary: View {
    @Environment(ApplicationStore.self) private var store
    let evaluation: ConditionEvaluation
    private var remaining: [ConditionEvidence] { evaluation.evidence.filter { !$0.met } }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ProgressView(value: Double(evaluation.evidence.filter(\.met).count), total: Double(max(1, evaluation.evidence.count)))
                    .tint(AtlasTheme.growth).frame(width: 90).accessibilityHidden(true)
                Text("条件已达成 \(evaluation.evidence.filter(\.met).count) / \(evaluation.evidence.count)").font(.caption).foregroundStyle(AtlasTheme.muted)
            }
            ForEach(Array(remaining.prefix(2).enumerated()), id: \.offset) { _, item in
                let name = item.condition.skillId.flatMap { id in store.library.skills.first { $0.id == id }?.name }
                    ?? item.condition.taskId.flatMap { id in store.tasks.items.first { $0.id == id }?.title } ?? "全部任务"
                Text("\(name) · \(item.condition.type.label) \(item.current) / \(item.required) \(item.unit) · 还差 \(max(0, item.required - item.current)) \(item.unit)")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
