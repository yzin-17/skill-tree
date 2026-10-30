import SwiftUI

struct ActivityWorkspace: View {
    @Environment(ApplicationStore.self) private var store
    @State private var tab = "calendar"
    @State private var month = Date.now
    @State private var from = Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now
    @State private var through = Date.now
    @State private var skillId = ""
    @State private var bucket = "day"
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PageHeading("成长日志")
                Spacer()
                Picker("日志视图", selection: $tab) {
                    Text("月历").tag("calendar"); Text("统计").tag("stats"); Text("时间线").tag("timeline")
                }.labelsHidden().pickerStyle(.segmented).frame(width: 220)
                    .accessibilityIdentifier("activity-view-picker")
            }.padding(24)
            if tab == "calendar" {
                ActivityCalendarView(monthDate: $month, skillId: $skillId)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 16) { dates; skillPicker; bucketPicker }
                            VStack(alignment: .leading, spacing: 12) { dates; HStack { skillPicker; bucketPicker } }
                        }
                        HStack(spacing: 12) {
                            Button("近 7 天") { setRange(days: 7) }
                            Button("近 30 天") { setRange(days: 30) }
                        }
                        if tab == "stats" { StatisticsView(from: from, through: through, skillId: skillId, bucket: bucket) }
                        else { ActivityTimeline(from: from, through: through, skillId: skillId) }
                    }.padding(.horizontal, 24).padding(.bottom, 24).frame(maxWidth: 1200, alignment: .leading).frame(maxWidth: .infinity)
                }
            }
        }.background(AtlasTheme.ground).environment(\.timeZone, TimeZone(identifier: store.account.user?.timezone ?? "UTC") ?? .gmt)
    }
    private func setRange(days: Int) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: store.account.user?.timezone ?? "UTC") ?? .gmt
        let end = Date.now
        from = calendar.date(byAdding: .day, value: 1 - days, to: end) ?? end
        through = end
    }
    private var dates: some View { HStack(spacing: 10) { DatePicker("从", selection: $from, in: ...through, displayedComponents: .date); DatePicker("到", selection: $through, in: from..., displayedComponents: .date) }.fixedSize() }
    private var skillPicker: some View { Picker("技能", selection: $skillId) { Text("全部技能").tag(""); ForEach(store.library.skills) { Text($0.name).tag($0.id) } }.frame(maxWidth: 220) }
    private var bucketPicker: some View { Picker("分组", selection: $bucket) { Text("日").tag("day"); Text("周").tag("week"); Text("月").tag("month") }.frame(width: 90).disabled(tab != "stats") }
}
