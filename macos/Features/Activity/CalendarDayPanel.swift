import SwiftUI

struct CalendarDayPanel: View {
    let date: Date
    let timezone: String
    let skillId: String
    let bucket: StatisticsBucket?
    let revision: UUID
    let close: () -> Void
    @AccessibilityFocusState private var headingFocused: Bool
    private var zone: TimeZone { TimeZone(identifier: timezone) ?? .gmt }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(CalendarDisplay.string(date, format: "yyyy年M月d日 EEEE", zone: zone)).font(.headline).accessibilityFocused($headingFocused)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                    .accessibilityLabel("关闭日期详情").help("关闭日期详情")
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let totals = bucket?.totals {
                        HStack(alignment: .top, spacing: 24) {
                            metric("任务完成", "\(totals.attempts.successes) 次")
                            metric("有效专注", AtlasFormat.duration(totals.focusSeconds))
                            Spacer(minLength: 0)
                        }
                        Text("\(totals.focusCount) 条专注 · 失败 \(totals.attempts.failures) · 重试 \(totals.attempts.retries) · \(totals.totalXp) XP")
                            .font(.caption).foregroundStyle(AtlasTheme.muted)
                    }
                    Text("当天活动").font(.headline)
                    ActivityTimeline(from: date, through: date, skillId: skillId, compact: true).id("\(date.timeIntervalSince1970):\(revision)")
                }.padding(20)
            }.id(date)
        }.onAppear { headingFocused = true }
            .onChange(of: date) { _, _ in headingFocused = true }
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(AtlasTheme.muted)
            Text(value).font(.title3.weight(.medium)).monospacedDigit()
        }
    }
}
