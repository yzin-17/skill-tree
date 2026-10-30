import SwiftUI

struct ActivityCalendarView: View {
    @Environment(ApplicationStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Binding var monthDate: Date
    @Binding var skillId: String
    @State private var summary: StatisticsSummary?
    @State private var selectedDate: Date?
    @State private var error: String?
    @State private var loading = true
    @State private var generation = UUID()
    @State private var loadedKey = ""
    @State private var revision = UUID()
    private var timezone: String { store.account.user?.timezone ?? "UTC" }
    private var month: ActivityCalendarMonth { .init(containing: monthDate, timezone: timezone) }
    private var queryKey: String { "\(month.start.timeIntervalSince1970):\(timezone):\(skillId)" }
    private var title: String { CalendarDisplay.string(month.start, format: "yyyy年 M月", zone: month.calendar.timeZone) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        controls
                        if let error { InlineFailure(message: error) { Task { await load() } } }
                        totals
                        calendarGrid
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                        .frame(maxWidth: 1200, alignment: .leading).frame(maxWidth: .infinity)
                }
                if let selectedDate {
                    CalendarDayPanel(date: selectedDate, timezone: timezone, skillId: skillId,
                                     bucket: month.bucket(on: selectedDate, in: summary?.series ?? []),
                                     revision: revision, close: { self.selectedDate = nil })
                        .frame(width: min(420, max(320, geometry.size.width * 0.68)), height: geometry.size.height)
                        .background(AtlasTheme.surface)
                        .overlay(alignment: .leading) { Rectangle().fill(AtlasTheme.raised).frame(width: 1) }
                        .accessibilityIdentifier("calendar-day-panel")
                }
            }
        }.task(id: queryKey) { await load() }
            .onChange(of: queryKey) { _, _ in selectedDate = nil }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
            .onChange(of: store.sync?.confirmedFocusRevision) { _, _ in Task { await load() } }
            .onExitCommand { selectedDate = nil }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { monthNavigation; Spacer(); filters }
            VStack(alignment: .leading, spacing: 14) { monthNavigation; filters }
        }
    }
    private var monthNavigation: some View {
        HStack(spacing: 12) {
            Text(title).font(.title3.weight(.semibold)).fixedSize()
            Button { monthDate = month.moving(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("上个月")
            Button { monthDate = month.moving(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("下个月")
            Button("本月") { monthDate = .now }
        }
    }
    private var filters: some View {
        HStack(spacing: 12) {
            Picker("技能", selection: $skillId) {
                Text("全部技能").tag("")
                ForEach(store.library.skills) { Text($0.name).tag($0.id) }
            }.frame(width: 180)
            Button { Task { await load() } } label: {
                if loading { ProgressView().controlSize(.small).frame(width: 14, height: 14) }
                else { Image(systemName: "arrow.clockwise") }
            }.disabled(loading).help("刷新月历").accessibilityLabel("刷新月历")
        }
    }
    private var totals: some View {
        HStack(alignment: .top, spacing: 32) {
            metric("任务完成", summary.map { "\($0.totals.attempts.successes) 次" } ?? "—")
            metric("有效专注", summary.map { AtlasFormat.duration($0.totals.focusSeconds) } ?? "—")
            metric("有记录", summary.map { "\(month.activeDayCount(in: $0.series)) 天" } ?? "—")
            Spacer(minLength: 0)
        }.padding(.vertical, 4)
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(AtlasTheme.muted)
            Text(value).font(.system(size: 22, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }
    }
    private var calendarGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                    Text(day).font(.caption.weight(.medium)).foregroundStyle(AtlasTheme.muted).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 1), count: 7), spacing: 1) {
                ForEach(month.days) { day in
                    CalendarDayCell(day: day, bucket: month.bucket(on: day.date, in: summary?.series ?? []),
                                    zone: month.calendar.timeZone, selected: selectedDate == day.date,
                                    loading: summary == nil && loading) { selectedDate = day.date }
                        .disabled(!day.isInMonth || summary == nil)
                }
            }.padding(1).background(AtlasTheme.raised.opacity(0.7))
        }.accessibilityIdentifier("activity-month-grid")
    }
    private func load() async {
        let key = queryKey
        let requestMonth = month
        let current = UUID()
        generation = current
        if loadedKey != key { summary = nil; selectedDate = nil }
        loadedKey = key; loading = true; error = nil
        do {
            let result: StatisticsSummary = try await store.account.request(APIQuery.path("/v1/stats/summary", requestMonth.query(skillID: skillId)))
            guard current == generation, key == queryKey, !Task.isCancelled else { return }
            summary = result; revision = UUID()
        } catch {
            guard current == generation, key == queryKey, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
        if current == generation { loading = false }
    }
}

private struct CalendarDayCell: View {
    let day: ActivityCalendarDay
    let bucket: StatisticsBucket?
    let zone: TimeZone
    let selected: Bool
    let loading: Bool
    let select: () -> Void
    @State private var hovering = false
    private var weekend: Bool { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone; return calendar.isDateInWeekend(day.date) }
    private var accessibility: String {
        let date = CalendarDisplay.string(day.date, format: "yyyy年M月d日 EEEE", zone: zone)
        guard day.isInMonth else { return date }
        guard let bucket else { return "\(date)，\(loading ? "正在加载" : "暂无数据")" }
        let totals = bucket.totals
        return "\(date)\(day.isToday ? "，今天" : "")，完成 \(totals.attempts.successes) 次，专注 \(AtlasFormat.duration(totals.focusSeconds))，失败 \(totals.attempts.failures) 次，重试 \(totals.attempts.retries) 次"
    }
    var body: some View {
        Button(action: select) { content }
            .buttonStyle(.plain).focusable(day.isInMonth).onHover { hovering = $0 }
            .onKeyPress(.space) { select(); return .handled }
            .onKeyPress(.return) { select(); return .handled }
            .accessibilityElement(children: .ignore).accessibilityLabel(accessibility)
            .accessibilityAddTraits(.isButton).accessibilityAction { select() }
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityIdentifier("calendar-day-" + CalendarDisplay.string(day.date, format: "yyyy-MM-dd", zone: zone))
            .help(accessibility)
    }
    private func attemptStatus(_ totals: StatisticsTotals) -> String {
        var labels: [String] = []
        if totals.attempts.failures > 0 { labels.append("失败 \(totals.attempts.failures)") }
        if totals.attempts.retries > 0 { labels.append("重试 \(totals.attempts.retries)") }
        return labels.joined(separator: " · ")
    }
    private var content: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(day.number)").font(.system(size: 13, weight: day.isToday ? .semibold : .regular)).monospacedDigit()
                        .frame(minWidth: 22, minHeight: 22)
                        .background(day.isToday ? AtlasTheme.raised : .clear, in: Circle())
                    Spacer(minLength: 0)
                    if day.isToday { Circle().fill(AtlasTheme.growth).frame(width: 4, height: 4) }
                }
                Spacer(minLength: 0)
                if day.isInMonth {
                    if let totals = bucket?.totals {
                        if totals.attempts.successes > 0 { Text("完成 \(totals.attempts.successes)").foregroundStyle(AtlasTheme.growth) }
                        if totals.focusCount > 0 { Text(CalendarDisplay.duration(totals.focusSeconds)).foregroundStyle(AtlasTheme.growth) }
                        if totals.attempts.failures > 0 || totals.attempts.retries > 0 {
                            Text(attemptStatus(totals))
                                .foregroundStyle(AtlasTheme.muted)
                        }
                        if let bucket, ActivityCalendarMonth.hasRecords(bucket), totals.focusCount == 0,
                           totals.attempts.total == 0, totals.attempts.retries == 0 {
                            Text("\(totals.totalXp) XP").foregroundStyle(AtlasTheme.muted)
                        }
                    } else { Text("—").foregroundStyle(AtlasTheme.muted) }
                }
            }.font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.85)
                .padding(8).frame(maxWidth: .infinity, minHeight: 100, maxHeight: 100, alignment: .topLeading)
                .foregroundStyle(day.isInMonth ? Color.primary : AtlasTheme.muted.opacity(0.45))
                .background(hovering && day.isInMonth ? AtlasTheme.raised : weekend ? AtlasTheme.surface : AtlasTheme.ground)
                .contentShape(Rectangle())
                .overlay { if selected { Rectangle().strokeBorder(AtlasTheme.growth, lineWidth: 1.5) } }
    }
}

enum CalendarDisplay {
    static func string(_ date: Date, format: String, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN"); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone; formatter.dateFormat = format
        return formatter.string(from: date)
    }
    static func duration(_ seconds: Int64) -> String {
        if seconds >= 3600 { return seconds % 3600 < 60 ? "\(seconds / 3600)小时" : "\(seconds / 3600)时\(seconds % 3600 / 60)分" }
        if seconds >= 60 { return "\(seconds / 60)分钟" }
        return "\(seconds)秒"
    }
}
