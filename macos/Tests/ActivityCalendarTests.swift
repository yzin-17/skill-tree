import Foundation
import Testing
@testable import SkillAtlasCore

struct ActivityCalendarTests {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func leapMonthHasSixMondayFirstWeeks() {
        let month = ActivityCalendarMonth(containing: date("2024-02-20T12:00:00Z"), timezone: "Asia/Shanghai")
        #expect(month.days.count == 42)
        #expect(Set(month.days.map(\.date)).count == 42)
        #expect(month.calendar.component(.weekday, from: month.days[0].date) == 2)
        #expect(month.days.filter(\.isInMonth).map(\.number) == Array(1...29))
        #expect(month.days.first?.date == date("2024-01-28T16:00:00Z"))
        #expect(month.days.last?.date == date("2024-03-09T16:00:00Z"))
    }

    @Test func accountTimezoneOwnsMonthTodayAndExclusiveQueryBounds() {
        let now = date("2026-12-31T16:30:00Z")
        let month = ActivityCalendarMonth(containing: now, timezone: "Asia/Shanghai", now: now)
        #expect(month.start == date("2026-12-31T16:00:00Z"))
        #expect(month.end == date("2027-01-31T16:00:00Z"))
        #expect(month.days.filter(\.isToday).map(\.number) == [1])
        #expect(month.moving(-1) == date("2026-11-30T16:00:00Z"))
        #expect(month.moving(1) == month.end)
        let query = Dictionary(uniqueKeysWithValues: month.query(skillID: "skill").map { ($0.name, $0.value!) })
        #expect(query == ["from": "2026-12-31T16:00:00Z", "to": "2027-01-31T16:00:00Z", "bucket": "day", "skill_id": "skill"])
        let utc = ActivityCalendarMonth(containing: now, timezone: "UTC", now: now)
        #expect(utc.days.filter(\.isToday).map(\.number) == [31])
    }

    @Test func daylightSavingUsesCalendarDaysRatherThanSeconds() {
        for (monthText, hours) in [("2026-03-10T12:00:00Z", 23.0), ("2026-11-10T12:00:00Z", 25.0)] {
            let month = ActivityCalendarMonth(containing: date(monthText), timezone: "America/New_York")
            let intervals = zip(month.days, month.days.dropFirst()).map { $1.date.timeIntervalSince($0.date) / 3600 }
            #expect(intervals.contains(hours))
            #expect(month.days.allSatisfy { month.calendar.component(.hour, from: $0.date) == 0 })
            #expect(month.days.filter(\.isInMonth).count == (hours == 23 ? 31 : 30))
        }
    }

    @Test func emptyAndSixWeekMonthsKeepTheirActualDates() {
        let feb = ActivityCalendarMonth(containing: date("2021-02-01T00:00:00Z"), timezone: "UTC")
        #expect(feb.days[0].number == 1 && feb.days[0].isInMonth)
        #expect(feb.days.filter(\.isInMonth).count == 28)
        let august = ActivityCalendarMonth(containing: date("2026-08-15T00:00:00Z"), timezone: "invalid")
        #expect(august.calendar.timeZone == .gmt)
        #expect(august.days[35].number == 31 && august.days[35].isInMonth)
        #expect(august.activeDayCount(in: []) == 0)
        #expect(august.bucket(on: august.start, in: []) == nil)
    }

    @Test func bucketsKeepEffectiveResultsZerosAndNegativeRewards() {
        let month = ActivityCalendarMonth(containing: date("2026-10-30T00:00:00Z"), timezone: "Asia/Shanghai")
        func bucket(_ at: String, successes: Int64 = 0, failures: Int64 = 0, retries: Int64 = 0, xp: Int64 = 0, growth: [String] = []) -> StatisticsBucket {
            .init(start: date(at), label: "", totals: .init(focusSeconds: 0, timerSeconds: 0, manualSeconds: 0, focusCount: 0, timeXp: 0, taskBonusXp: xp, totalXp: xp, attempts: .init(total: successes + failures, successes: successes, failures: failures, retries: retries, successRate: nil)), sources: .init(focusIds: [], growthIds: growth, attemptIds: [], retryIds: []))
        }
        let empty = bucket("2026-10-27T16:00:00Z")
        let reversed = bucket("2026-10-28T16:00:00Z", failures: 1, retries: 1, xp: -60, growth: ["reversal"])
        let complete = bucket("2026-10-29T16:00:00Z", successes: 2)
        let outside = bucket("2026-09-29T16:00:00Z", successes: 1)
        let series = [complete, outside, empty, reversed]
        let selected = month.bucket(on: date("2026-10-29T15:59:00Z"), in: series)!
        #expect(selected.start == reversed.start)
        #expect(selected.totals.attempts.successes == 0)
        #expect(selected.totals.attempts.failures == 1 && selected.totals.attempts.retries == 1)
        #expect(selected.totals.totalXp == -60)
        #expect(month.activeDayCount(in: series + [complete]) == 2)
        #expect(month.bucket(on: empty.start, in: series)?.totals.attempts.total == 0)
        #expect(month.bucket(on: date("2026-10-26T16:00:00Z"), in: series) == nil)
        #expect(!ActivityCalendarMonth.hasRecords(empty))
        #expect(ActivityCalendarMonth.hasRecords(bucket("2026-10-30T16:00:00Z", growth: ["zero-xp"])))
    }
}
