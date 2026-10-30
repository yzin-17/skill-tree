import SwiftUI

struct ActivityTimeline: View {
    @Environment(ApplicationStore.self) private var store
    let from: Date
    let through: Date
    let skillId: String
    var compact = false
    @State private var type = ""
    @State private var presentation = "outcomes"
    @State private var items: [ActivityRecord] = []
    @State private var cursor = ""
    @State private var loading = false
    @State private var error: String?
    @State private var generation = UUID()
    @State private var selected: ActivityRecord?
    private var queryKey: String { "\(from.timeIntervalSince1970):\(through.timeIntervalSince1970):\(skillId):\(type)" }
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: store.account.user?.timezone ?? "") ?? .current; return value }
    private var entries: [ActivityEntry] { ActivityEntry.make(items, groupFocus: presentation == "outcomes" && type.isEmpty) }
    private var days: [Date] { Array(Set(entries.map { calendar.startOfDay(for: $0.occurredAt) })).sorted(by: >) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !compact { HStack {
                Text("活动时间线").font(.title3.weight(.semibold)); Spacer()
                Picker("呈现", selection: $presentation) { Text("成果").tag("outcomes"); Text("事件明细").tag("events") }.labelsHidden().pickerStyle(.segmented).frame(width: 160)
                Picker("类型", selection: $type) {
                    Text("全部类型").tag(""); Text("专注记录").tag("focus.recorded"); Text("任务成功").tag("attempt.success"); Text("任务失败").tag("attempt.failed"); Text("任务重试").tag("task.retried"); Text("结果撤销").tag("attempt.reversed"); Text("技能升级").tag("skill.level_up"); Text("成长流水").tag("growth.accrued"); Text("进入阶段").tag("career.transitioned"); Text("称号解锁").tag("title.unlocked"); Text("称号佩戴").tag("title.equipped"); Text("取消佩戴").tag("title.unequipped")
                }.labelsHidden().frame(width: 150)
                Button { Task { await fetch(reset: true) } } label: { Image(systemName: "arrow.clockwise") }.help("刷新活动")
            } }
            if let error { InlineFailure(message: error) { Task { await fetch(reset: items.isEmpty) } } }
            if items.isEmpty && !loading && error == nil { Text(compact ? "当天暂无活动" : "这个区间还没有活动").foregroundStyle(AtlasTheme.muted).padding(.vertical, 24) }
            ForEach(days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 0) {
                    if !compact { Text(AtlasDate.string(day, zone: calendar.timeZone, date: .medium, time: .none)).font(.caption.weight(.medium)).foregroundStyle(AtlasTheme.muted).padding(.vertical, 12) }
                    ForEach(entries.filter { calendar.isDate($0.occurredAt, inSameDayAs: day) }) { entry in
                        if entry.isFocus {
                            FocusOutcomeRow(entry: entry, zone: calendar.timeZone) { selected = $0 }
                        } else {
                            Button { selected = entry.event } label: { ActivityRow(event: entry.event, zone: calendar.timeZone, showsTask: compact) }.buttonStyle(.plain)
                        }
                        Divider().opacity(0.45)
                    }
                }
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            else if !cursor.isEmpty { Button("加载更多活动") { Task { await fetch(reset: false) } }.frame(maxWidth: .infinity) }
        }.onChange(of: type) { _, value in if !value.isEmpty { presentation = "events" } }
        .task(id: queryKey) { await fetch(reset: true) }.sheet(item: $selected) { ActivityDetail(event: $0) }
    }
    private func fetch(reset: Bool) async {
        if !reset && loading { return }
        if reset { generation = UUID(); items = []; cursor = "" }
        let current = generation; loading = true
        defer { if current == generation { loading = false } }
        var query = APIQuery.range(from: from, through: through, timezone: store.account.user?.timezone ?? "UTC")
        query += [.init(name: "skill_id", value: skillId), .init(name: "type", value: type), .init(name: "limit", value: "30"), .init(name: "cursor", value: reset ? "" : cursor)]
        do {
            let page: ActivityPage = try await store.account.request(APIQuery.path("/v1/activity-events", query))
            guard current == generation, !Task.isCancelled else { return }
            let known = Set(items.map(\.id)); items += page.items.filter { !known.contains($0.id) }; cursor = page.nextCursor; error = nil
        } catch { if current == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct ActivityRow: View {
    @Environment(ApplicationStore.self) private var store
    let event: ActivityRecord
    let zone: TimeZone
    var showsDate = false
    var showsTask = false
    private var taskName: String? {
        guard showsTask else { return nil }
        let id = event.metadata["task_id"]?.string ?? (event.entityType == "task" ? event.entityId : nil)
        return store.tasks.items.first { $0.id == id }?.title
    }
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: event.type.hasPrefix("focus.") ? "timer" : (event.type.hasPrefix("task.") || event.type.hasPrefix("attempt.")) ? "checklist" : event.type.hasPrefix("title.") ? "medal" : event.type == "career.transitioned" ? "flag" : "sparkles")
                .font(.system(size: 17, weight: .light)).frame(width: 24).foregroundStyle(AtlasTheme.muted)
            VStack(alignment: .leading, spacing: 6) {
                Text(taskName ?? AchievementDisplay.eventSummary(event)).font(.callout).lineLimit(2)
                if taskName != nil { Text(AchievementDisplay.eventSummary(event)).font(.caption).foregroundStyle(AtlasTheme.muted) }
                if !event.skillIds.isEmpty { Text(event.skillIds.map { id in store.library.skills.first { $0.id == id }?.name ?? "历史技能" }.joined(separator: " · ")).font(.caption).foregroundStyle(AtlasTheme.muted) }
                if let delta = event.metadata["delta_xp"]?.integer { Text("\(delta > 0 ? "+" : "")\(delta) XP").font(.caption).foregroundStyle(AtlasTheme.growth) }
            }
            Spacer()
            Text(showsDate ? ActivityDisplay.relativeDate(event.occurredAt, now: .now, zone: zone) : AtlasDate.string(event.occurredAt, zone: zone, date: .none, time: .short)).font(.caption).foregroundStyle(AtlasTheme.muted)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(AtlasTheme.muted)
        }.padding(.vertical, 10).contentShape(Rectangle())
    }
}

private struct FocusOutcomeRow: View {
    @Environment(ApplicationStore.self) private var store
    let entry: ActivityEntry
    let zone: TimeZone
    let select: (ActivityRecord) -> Void
    @State private var expanded = false
    private var skills: String { entry.event.skillIds.map { id in store.library.skills.first { $0.id == id }?.name ?? "历史技能" }.joined(separator: " · ") }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { select(entry.event) } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "timer").font(.system(size: 18, weight: .light)).frame(width: 24).foregroundStyle(AtlasTheme.muted)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(skills.isEmpty ? "专注会话" : skills).font(.callout.weight(.medium))
                        if let seconds = entry.effectiveSeconds {
                            Text("\(entry.confirmation?.metadata["source"]?.string == "manual" ? "手动补录" : "有效专注") \(AtlasFormat.duration(seconds))").font(.callout)
                        } else { Text("专注过程 · 查看会话结果").font(.callout).foregroundStyle(AtlasTheme.muted) }
                        if let id = entry.taskId { Text(store.tasks.items.first { $0.id == id }?.title ?? "关联任务").font(.caption).foregroundStyle(AtlasTheme.muted) }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(AtlasDate.string(entry.occurredAt, zone: zone, date: .none, time: .short)).font(.caption).foregroundStyle(AtlasTheme.muted)
                        if let xp = entry.awardedXp { Text("+\(xp) XP").font(.callout.weight(.medium)).foregroundStyle(AtlasTheme.growth) }
                    }
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(AtlasTheme.muted)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !entry.processEvents.isEmpty {
                DisclosureGroup("过程记录 · 已显示 \(entry.processEvents.count) 条", isExpanded: $expanded) {
                    ForEach(entry.processEvents) { event in Button { select(event) } label: { ActivityRow(event: event, zone: zone, showsDate: true) }.buttonStyle(.plain) }
                }.font(.caption).foregroundStyle(AtlasTheme.muted).padding(.leading, 36)
            }
        }.padding(.vertical, 12)
    }
}

struct ActivityDetail: View {
    let event: ActivityRecord
    var body: some View { RecordInspector(event: event) }
}

enum AtlasDate {
    static func string(_ date: Date, zone: TimeZone, date style: DateFormatter.Style, time: DateFormatter.Style) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.timeZone = zone; formatter.dateStyle = style; formatter.timeStyle = time
        return formatter.string(from: date)
    }
}
