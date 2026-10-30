import SwiftUI
import Charts

struct StatisticsView: View {
    @Environment(ApplicationStore.self) private var store
    let from: Date
    let through: Date
    let skillId: String
    let bucket: String
    @State private var summary: StatisticsSummary?
    @State private var loading = false
    @State private var error: String?
    @State private var selection: Date?
    @State private var attemptSelection: Date?
    @State private var expandedSources = false
    private var queryKey: String { "\(from.timeIntervalSince1970):\(through.timeIntervalSince1970):\(skillId):\(bucket)" }
    private func selectedBucket(_ selection: Date?) -> StatisticsBucket? {
        guard let selection, let summary else { return nil }
        return summary.series.min { abs($0.start.timeIntervalSince(selection)) < abs($1.start.timeIntervalSince(selection)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let error { InlineFailure(message: error) { Task { await load() } } }
            if loading { ProgressView("正在汇总记录") }
            if let summary {
                HStack(alignment: .top, spacing: 32) {
                    metric("有效专注", AtlasFormat.duration(summary.totals.focusSeconds))
                    metric("净增长", "\(summary.totals.totalXp) XP")
                    metric("尝试成功率", summary.totals.attempts.successRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "暂无数据")
                    Spacer()
                }
                Text("\(summary.totals.focusCount) 条专注 · 成功 \(summary.totals.attempts.successes) 次 · 失败 \(summary.totals.attempts.failures) 次 · 重试 \(summary.totals.attempts.retries) 次").font(.callout).foregroundStyle(AtlasTheme.muted)
                timeSection(summary)
                if let item = selectedBucket(selection) { sourcePanel(item, attemptsOnly: false) }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("技能投入与 XP 来源").font(.title3.weight(.semibold)); Spacer(); HStack(spacing: 12) { Label { Text("时间 XP") } icon: { Circle().fill(AtlasTheme.growth).frame(width: 6, height: 6) }; Label { Text("任务净奖励") } icon: { Circle().fill(Color.gray).frame(width: 6, height: 6) } }.font(.caption).foregroundStyle(AtlasTheme.muted) }
                    if summary.skills.isEmpty { Text("当前区间没有技能投入。").foregroundStyle(AtlasTheme.muted) }
                    ForEach(summary.skills) { skill in
                        SkillStatisticsRow(skill: skill, allSkills: summary.skills)
                    }
                }
                Divider()
                successSection(summary)
                if let item = selectedBucket(attemptSelection) { sourcePanel(item, attemptsOnly: true) }
                DisclosureGroup("区间原始记录 · \(summary.sources.records.count) 条", isExpanded: $expandedSources) { SourceList(sources: summary.sources.records).padding(.top, 16) }
                Divider()
                VStack(alignment: .leading, spacing: 18) {
                    Text("阶段与称号历程").font(.title3.weight(.semibold))
                    if summary.careerHistory.isEmpty && summary.titleHistory.isEmpty { Text("当前区间没有成就变更。").foregroundStyle(AtlasTheme.muted) }
                    ForEach(summary.careerHistory) { entry in DisclosureGroup("\(entry.confirmedAt.formatted(date: .abbreviated, time: .shortened)) · \(store.achievements.careers?.items.first { $0.id == entry.toCareerId }?.name ?? "进入成长阶段")") { ConditionEvidenceView(evaluation: entry.evidenceSnapshot).padding(.top, 12) } }
                    ForEach(summary.titleHistory) { event in HStack { Text(event.summary); Spacer(); Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(AtlasTheme.muted) }.font(.callout) }
                    Button("查看成就殿堂") { store.destination = .achievements }
                }
            }
        }.task(id: queryKey) { await load() }
    }
    private func sourcePanel(_ item: StatisticsBucket, attemptsOnly: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(item.label) · \(attemptsOnly ? "尝试来源" : "时段记录")").font(.headline)
                Spacer()
                Button("收起") { if attemptsOnly { attemptSelection = nil } else { selection = nil } }
            }
            SourceList(sources: item.sources.records.filter { !attemptsOnly || ["task_attempt", "task_retry"].contains($0.kind) })
        }.padding(16).background(AtlasTheme.surface)
    }
    @ViewBuilder private func timeSection(_ summary: StatisticsSummary) -> some View {
        let active = StatisticsPresentation.focusBuckets(summary.series)
        VStack(alignment: .leading, spacing: 12) {
            Text("时间投入").font(.title3.weight(.semibold))
            if active.isEmpty {
                Text("所选区间没有专注记录。").font(.callout).foregroundStyle(AtlasTheme.muted)
            } else if active.count == 1, let item = active.first {
                ViewThatFits(in: .horizontal) {
                    HStack { timeSummary(item); Spacer(); Button("查看该时段记录") { selection = item.start } }
                    VStack(alignment: .leading, spacing: 10) { timeSummary(item); Button("查看该时段记录") { selection = item.start } }
                }.padding(16).background(AtlasTheme.surface)
                Text("有投入 1 \(bucketName) · 零投入 \(max(0, summary.series.count - 1)) \(bucketName)").font(.caption).foregroundStyle(AtlasTheme.muted)
            } else {
                Chart(summary.series) { item in
                    BarMark(x: .value("日期", item.start), y: .value("分钟", Double(item.totals.timerSeconds) / 60)).foregroundStyle(by: .value("来源", "计时"))
                    BarMark(x: .value("日期", item.start), y: .value("分钟", Double(item.totals.manualSeconds) / 60)).foregroundStyle(by: .value("来源", "补录"))
                }.chartForegroundStyleScale(["计时": AtlasTheme.growth, "补录": Color.gray])
                    .chartXScale(range: .plotDimension(padding: 10))
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
                    .chartYAxisLabel("分钟")
                    .chartXSelection(value: $selection).frame(height: 150).help("选择日期查看记录")
            }
        }
    }
    private var bucketName: String { bucket == "week" ? "周" : bucket == "month" ? "月" : "日" }
    private func timeSummary(_ item: StatisticsBucket) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(item.label) · \(AtlasFormat.duration(item.totals.focusSeconds))").font(.headline)
            Text("计时 \(AtlasFormat.duration(item.totals.timerSeconds)) · 补录 \(AtlasFormat.duration(item.totals.manualSeconds)) · \(item.totals.focusCount) 条专注").font(.callout).foregroundStyle(AtlasTheme.muted)
        }
    }
    @ViewBuilder private func successSection(_ summary: StatisticsSummary) -> some View {
        let valid = StatisticsPresentation.attemptBuckets(summary.series)
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("尝试成功率").font(.title3.weight(.semibold)); Spacer(); Text("成功 \(summary.totals.attempts.successes) / 有效尝试 \(summary.totals.attempts.total)").font(.callout).foregroundStyle(AtlasTheme.muted) }
            if valid.isEmpty {
                Text("尚无有效尝试").font(.callout).foregroundStyle(AtlasTheme.muted)
            } else if valid.count == 1, let item = valid.first {
                HStack {
                    Text(item.label).font(.callout)
                    Text((item.totals.attempts.successRate ?? 0).formatted(.percent.precision(.fractionLength(0)))).font(.title3.weight(.medium)).monospacedDigit()
                    Spacer()
                    Button("查看尝试来源") { attemptSelection = item.start }
                }.padding(16).background(AtlasTheme.surface)
            } else {
                Chart(summary.series) { item in
                    if let rate = item.totals.attempts.successRate {
                        LineMark(x: .value("日期", item.start), y: .value("成功率 %", rate * 100)).foregroundStyle(AtlasTheme.growth)
                        PointMark(x: .value("日期", item.start), y: .value("成功率 %", rate * 100)).foregroundStyle(AtlasTheme.growth)
                    }
                }.chartYScale(domain: 0...100).chartXScale(domain: summary.from...summary.to)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
                    .chartYAxis { AxisMarks(values: [0, 50, 100]) { value in AxisGridLine(); AxisValueLabel { if let amount = value.as(Int.self) { Text("\(amount)%") } } } }
                    .chartXSelection(value: $attemptSelection).frame(height: 140)
            }
        }
    }
    private func metric(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 12) { Text(label).font(.caption).foregroundStyle(AtlasTheme.muted); Text(value).font(.system(size: 24, weight: .medium)).monospacedDigit() } }
    private func load() async {
        loading = true; error = nil; summary = nil; selection = nil; attemptSelection = nil
        let key = queryKey
        var query = APIQuery.range(from: from, through: through, timezone: store.account.user?.timezone ?? "UTC")
        query += [.init(name: "skill_id", value: skillId), .init(name: "bucket", value: bucket)]
        do { let result: StatisticsSummary = try await store.account.request(APIQuery.path("/v1/stats/summary", query)); if !Task.isCancelled && key == queryKey { summary = result } }
        catch { if !Task.isCancelled && key == queryKey { self.error = error.localizedDescription } }
        if !Task.isCancelled && key == queryKey { loading = false }
    }
}

private struct SkillStatisticsRow: View {
    @Environment(ApplicationStore.self) private var store
    let skill: SkillStatistics
    let allSkills: [SkillStatistics]
    private var treeName: String { store.library.trees.first { $0.id == skill.treeId }?.name ?? "历史技能树" }
    private var range: ClosedRange<Double> { StatisticsPresentation.xpDomain(allSkills) }
    var body: some View {
        Button { store.openSkill(skill.skillId) } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { identity.frame(width: 130, alignment: .leading); comparison.frame(minWidth: 120); values }
                VStack(alignment: .leading, spacing: 8) { HStack { identity; Spacer(); values }; comparison }
            }.padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(skill.name)，所属技能树 \(treeName)，投入 \(AtlasFormat.duration(skill.totals.focusSeconds))，时间 XP \(skill.totals.timeXp)，任务净奖励 \(skill.totals.taskBonusXp) XP，总计 \(skill.totals.totalXp) XP")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { store.openSkill(skill.skillId) }
            .accessibilityHint("打开技能详情")
    }
    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) { Text(skill.name).font(.callout.weight(.medium)); Text(treeName).font(.caption).foregroundStyle(AtlasTheme.muted) }
    }
    private var values: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(skill.totals.totalXp) XP · \(AtlasFormat.duration(skill.totals.focusSeconds))").font(.callout).monospacedDigit()
            Text("时间 \(skill.totals.timeXp) · 任务 \(skill.totals.taskBonusXp)").font(.caption).foregroundStyle(AtlasTheme.muted).monospacedDigit()
        }.fixedSize(horizontal: true, vertical: false)
    }
    private var comparison: some View {
        Chart {
            BarMark(x: .value("XP", skill.totals.timeXp), y: .value("技能", skill.name)).foregroundStyle(AtlasTheme.growth)
            BarMark(x: .value("XP", skill.totals.taskBonusXp), y: .value("技能", skill.name)).foregroundStyle(Color.gray)
        }.chartXScale(domain: range).chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden).frame(height: 22).accessibilityHidden(true)
    }
}
