import SwiftUI

struct DashboardView: View {
    @Environment(ApplicationStore.self) private var store
    @State private var summary: StatisticsSummary?
    @State private var recent: [ActivityRecord] = []
    @State private var error: String?
    @State private var taskEditor = false
    @State private var treeEditor = false
    @State private var activity: ActivityRecord?
    private var zone: TimeZone { TimeZone(identifier: store.account.user?.timezone ?? "") ?? .current }
    private var highlighted: [TaskRecord] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return store.tasks.sorted.filter { $0.pinned || $0.status == .inProgress || ($0.status.canConclude && $0.dueAt.map { calendar.isDate($0, inSameDayAs: .now) } == true) }
    }
    private var nextCareer: CareerRecord? {
        store.achievements.careers?.items.filter { $0.parentCareerId == store.achievements.currentCareer?.id && $0.id != store.achievements.currentCareer?.id }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }.first
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        PageHeading("工作台", subtitle: AtlasDate.string(.now, zone: zone, date: .full, time: .none)); Spacer()
                        Button { Task { await store.refreshWorkspace(); await load() } } label: { Image(systemName: "arrow.clockwise") }.help("刷新工作台")
                        Button("新建任务", systemImage: "plus") { taskEditor = true }.disabled(store.account.isOffline)
                    }
                    if store.account.isOffline { Label("当前离线", systemImage: "wifi.slash").font(.callout).foregroundStyle(AtlasTheme.muted) }
                    if let error { InlineFailure(message: error) { Task { await load() } } }
                    if let local = store.localError { InlineFailure(message: local) { store.destination = .settings } }
                    HStack(spacing: 32) {
                        dashboardMetric("今日投入", summary.map { AtlasFormat.duration($0.totals.focusSeconds) } ?? "—")
                        dashboardMetric("今日成长", summary.map { "\($0.totals.totalXp) XP" } ?? "—")
                        dashboardMetric("今日成功", summary.map { "\($0.totals.attempts.successes) 次" } ?? "—")
                        Spacer(minLength: 0)
                    }
                    if geometry.size.width >= 900 {
                        HStack(alignment: .top, spacing: 24) { taskSection.frame(maxWidth: .infinity); focusAndGrowth.frame(width: 280) }
                    } else { taskSection; compactFocusAndGrowth }
                    if store.library.trees.isEmpty {
                        HStack { Text("暂无技能树").font(.callout).foregroundStyle(AtlasTheme.muted); Spacer(); Button("新建技能树") { treeEditor = true }.disabled(store.account.isOffline) }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("近期活动").font(.title3.weight(.semibold)); Spacer(); Button("成长日志") { store.destination = .activity } }
                        if recent.isEmpty { Text("暂无活动").foregroundStyle(AtlasTheme.muted).padding(.vertical, 12) }
                        ForEach(recent) { event in Button { activity = event } label: { ActivityRow(event: event, zone: zone, showsDate: true) }.buttonStyle(.plain) }
                    }
                }.padding(24).frame(maxWidth: 1200, alignment: .leading).frame(maxWidth: .infinity)
            }
        }.background(AtlasTheme.ground).task { await load() }
            .onChange(of: store.sync?.confirmedFocusRevision) { _, _ in Task { await load() } }
            .sheet(isPresented: $taskEditor) { TaskEditor(task: nil) { store.openTask($0) } }
            .sheet(isPresented: $treeEditor) { TreeEditor(tree: nil) { _ in store.destination = .skills } }
            .sheet(item: $activity) { ActivityDetail(event: $0) }
    }
    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("今日与进行中").font(.title3.weight(.semibold)); Spacer(); Button("全部任务") { store.destination = .tasks } }
            if highlighted.isEmpty { Text("暂无待处理任务").font(.callout).foregroundStyle(AtlasTheme.muted).padding(.vertical, 12) }
            ForEach(highlighted.prefix(6)) { item in
                VStack(alignment: .leading, spacing: 12) {
                    TaskListRow(task: item, open: { store.openTask(item.id) })
                    if !item.successCriteria.isEmpty { Text(item.successCriteria).font(.callout).foregroundStyle(AtlasTheme.muted).lineLimit(2) }
                    HStack {
                        Text("已投入 \(AtlasFormat.duration(item.totalFocusSeconds))").font(.caption).foregroundStyle(AtlasTheme.muted)
                        Spacer()
                        if item.status.canConclude { Button("继续专注", systemImage: "play") { store.prepareFocus(skillId: item.skills.first?.skillId, taskId: item.id) } }
                    }
                }.padding(18).background(AtlasTheme.surface)
            }
            let failed = store.tasks.sorted.filter { $0.status == .failed && !highlighted.contains($0) }
            if !failed.isEmpty {
                Text("待重试").font(.headline)
                ForEach(failed.prefix(4)) { item in HStack { Text(item.title).font(.callout); Spacer(); Button("查看并重试") { store.openTask(item.id) } } }
            }
        }
    }
    private var compactFocusAndGrowth: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.focus?.snapshot == nil ? "开始一段专注" : "当前专注").font(.headline)
                if let snapshot = store.focus?.snapshot {
                    Text(store.library.skills.first { $0.id == snapshot.skillId }?.name ?? "当前技能").font(.callout)
                    Text("\(AtlasFormat.duration(Int(snapshot.effectiveElapsed))) · \(snapshot.status == .running ? "正在计时" : "已暂停")").font(.callout).foregroundStyle(AtlasTheme.muted)
                }
                Button(store.focus?.snapshot == nil ? "开始专注" : "查看当前专注", systemImage: "play.fill") { store.destination = store.library.activeSkills.isEmpty ? .skills : .focus }.buttonStyle(.borderedProminent)
                if let sync = store.sync, sync.pendingCount + sync.blockedCount + sync.activityCount > 0 {
                    Button("\(sync.pendingCount + sync.blockedCount + sync.activityCount) 条记录待确认") { store.destination = .focus }.font(.caption)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text(store.achievements.currentCareer?.name ?? "成长路径").font(.headline)
                if let next = nextCareer {
                    Text("下一阶段 · \(next.name)").font(.callout)
                    if let gap = next.evaluation.evidence.first(where: { !$0.met }) {
                        let name = gap.condition.skillId.flatMap { id in store.library.skills.first { $0.id == id }?.name }
                            ?? gap.condition.taskId.flatMap { id in store.tasks.items.first { $0.id == id }?.title } ?? "全部任务"
                        Text("\(name) · \(gap.current) / \(gap.required) \(gap.unit)，还差 \(max(0, gap.required - gap.current)) \(gap.unit)").font(.callout).foregroundStyle(AtlasTheme.muted).fixedSize(horizontal: false, vertical: true)
                    } else { Text("条件已达成 \(next.evaluation.evidence.filter(\.met).count) / \(next.evaluation.evidence.count)").font(.callout).foregroundStyle(AtlasTheme.muted) }
                } else { Text("尚未设置成长路径").font(.callout).foregroundStyle(AtlasTheme.muted) }
                Button("查看成长路径") { store.destination = .achievements }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(18).background(AtlasTheme.surface)
    }
    private var focusAndGrowth: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text(store.focus?.snapshot == nil ? "开始一段专注" : "当前专注").font(.headline)
                if let snapshot = store.focus?.snapshot {
                    Text(store.library.skills.first { $0.id == snapshot.skillId }?.name ?? "当前技能").font(.callout)
                    Text("\(AtlasFormat.duration(Int(snapshot.effectiveElapsed))) · \(snapshot.status == .running ? "正在计时" : "已暂停")").font(.callout).foregroundStyle(AtlasTheme.muted).monospacedDigit()
                }
                Button(store.focus?.snapshot == nil ? "开始专注" : "查看当前专注", systemImage: "play.fill") { store.destination = store.library.activeSkills.isEmpty ? .skills : .focus }.buttonStyle(.borderedProminent)
                if let sync = store.sync, sync.pendingCount + sync.blockedCount + sync.activityCount > 0 {
                    Button("\(sync.pendingCount + sync.blockedCount + sync.activityCount) 条记录待确认") { store.destination = .focus }.font(.caption)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text(store.achievements.currentCareer?.name ?? "成长路径").font(.headline)
                if let title = store.achievements.equippedTitle { Text("称号 · \(title.name)").font(.callout).foregroundStyle(AtlasTheme.muted) }
                if let next = nextCareer {
                    Text("下一阶段 · \(next.name)").font(.callout)
                    Text("条件已达成 \(next.evaluation.evidence.filter(\.met).count) / \(next.evaluation.evidence.count)").font(.caption).foregroundStyle(AtlasTheme.muted)
                    if let gap = next.evaluation.evidence.first(where: { !$0.met }) {
                        ConditionEvidenceView(evaluation: .init(eligible: false, evidence: [gap]))
                    }
                } else { Text("尚未设置成长路径").font(.callout).foregroundStyle(AtlasTheme.muted) }
                Button("查看成长路径") { store.destination = .achievements }
            }
        }.padding(18).background(AtlasTheme.surface)
    }
    private func dashboardMetric(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 6) { Text(label).font(.caption).foregroundStyle(AtlasTheme.muted); Text(value).font(.system(size: 24, weight: .medium)).monospacedDigit() } }
    private func load() async {
        do {
            let query = APIQuery.range(from: .now, through: .now, timezone: store.account.user?.timezone ?? "UTC")
            async let stats: StatisticsSummary = store.account.request(APIQuery.path("/v1/stats/summary", query))
            async let events: ActivityPage = store.account.request("/v1/activity-events?limit=6")
            let result = try await (stats, events)
            if !Task.isCancelled { summary = result.0; recent = result.1.items; error = nil }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
