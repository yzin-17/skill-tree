import Foundation
import Testing
@testable import SkillAtlasCore

struct PresentationTests {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    @Test func activityDatesRespectAccountDayAndYear() {
        let now = date("2026-10-30T00:30:00Z")
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        #expect(ActivityDisplay.relativeDate(date("2026-10-29T15:00:00Z"), now: now, zone: zone) == "昨天 23:00")
        #expect(ActivityDisplay.relativeDate(date("2026-10-29T16:01:00Z"), now: now, zone: zone) == "今天 00:01")
        #expect(ActivityDisplay.relativeDate(date("2026-09-28T15:00:00Z"), now: now, zone: zone) == "9月28日 23:00")
        #expect(ActivityDisplay.relativeDate(date("2025-10-29T15:00:00Z"), now: now, zone: zone) == "2025年10月29日 23:00")
        #expect(ActivityDisplay.relativeDate(date("2026-10-29T15:00:00Z"), now: now, zone: .gmt) == "昨天 15:00")
    }

    private func event(_ id: String, type: String, session: String, at: String = "2026-10-29T15:00:00Z", metadata: [String: JSONValue] = [:]) -> ActivityRecord {
        .init(id: id, type: type, producer: "server", entityType: "focus_session", entityId: session, summary: type, skillIds: ["skill"], metadata: metadata, occurredAt: date(at), createdAt: date(at))
    }
    @Test func focusGroupsUseIdentityAndConfirmedAwardWithoutDoubleCounting() {
        let first = UUID().uuidString, second = UUID().uuidString
        let saved = event("saved", type: "focus.recorded", session: first, metadata: ["effective_seconds": .integer(53), "awarded_xp": .integer(1)])
        let growth = event("xp", type: "growth.accrued", session: first, metadata: ["delta_xp": .integer(1)])
        let other = event("other", type: "focus.recorded", session: second, metadata: ["effective_seconds": .integer(120), "awarded_xp": .integer(2)])
        let groups = ActivityEntry.make([saved, growth, saved, other], groupFocus: true)
        #expect(groups.count == 2)
        let group = groups.first { $0.event.entityId == first }!
        #expect(group.events.count == 2)
        #expect(group.effectiveSeconds == 53)
        #expect(group.awardedXp == 1)
        #expect(group.processEvents.map(\.id) == ["xp"])
        #expect(ActivityEntry.make([saved, growth, saved, other], groupFocus: false).count == 3)
    }
    @Test func partialPageAndCrossDayProcessDoNotInventAnOutcome() {
        let session = UUID().uuidString
        let started = event("start", type: "focus.started", session: session, at: "2026-10-29T15:59:00Z")
        let ended = event("end", type: "focus.ended", session: session, at: "2026-10-29T16:01:00Z", metadata: ["effective_seconds": .integer(53)])
        let partial = ActivityEntry.make([ended, started], groupFocus: true)[0]
        #expect(partial.confirmation == nil && partial.awardedXp == nil && partial.effectiveSeconds == nil)
        let saved = event("saved", type: "focus.recorded", session: session, at: "2026-10-29T16:02:00Z", metadata: ["effective_seconds": .integer(53), "awarded_xp": .integer(0)])
        let complete = ActivityEntry.make([ended, started, saved], groupFocus: true)[0]
        #expect(complete.events.count == 3)
        #expect(complete.occurredAt == saved.occurredAt)
        #expect(complete.awardedXp == 0)
        #expect(ActivityEntry.make([event("invalid", type: "focus.started", session: "")], groupFocus: true)[0].isFocus == false)
    }

    @Test func sparseStatisticsRetainZeroBucketsAndNegativeRewards() {
        func totals(seconds: Int64, count: Int64, time: Int64 = 0, bonus: Int64 = 0, attempts: Int64 = 0) -> StatisticsTotals {
            .init(focusSeconds: seconds, timerSeconds: seconds, manualSeconds: 0, focusCount: count, timeXp: time, taskBonusXp: bonus, totalXp: time + bonus, attempts: .init(total: attempts, successes: 0, failures: attempts, retries: 0, successRate: attempts == 0 ? nil : 0))
        }
        let sources = StatisticsSources(focusIds: [], growthIds: [], attemptIds: [], retryIds: [])
        let zero = StatisticsBucket(start: date("2026-10-28T00:00:00Z"), label: "2026-10-28", totals: totals(seconds: 0, count: 0), sources: sources)
        let one = StatisticsBucket(start: date("2026-10-29T00:00:00Z"), label: "2026-10-29", totals: totals(seconds: 53, count: 1, attempts: 1), sources: sources)
        let two = StatisticsBucket(start: date("2026-10-30T00:00:00Z"), label: "2026-10-30", totals: totals(seconds: 120, count: 1), sources: sources)
        let original = [zero, one, two]
        #expect(StatisticsPresentation.focusBuckets([zero]).isEmpty)
        #expect(StatisticsPresentation.focusBuckets([zero, one]).map(\.label) == ["2026-10-29"])
        #expect(StatisticsPresentation.focusBuckets(original).map(\.label) == ["2026-10-29", "2026-10-30"])
        #expect(original.count == 3 && original.first?.totals.focusSeconds == 0)
        #expect(StatisticsPresentation.attemptBuckets(original).map(\.label) == ["2026-10-29"])
        #expect(StatisticsPresentation.attemptBuckets(original)[0].totals.attempts.successRate == 0)
        let skills = [SkillStatistics(skillId: "a", treeId: "tree", name: "Go", totals: totals(seconds: 3600, count: 2, time: 60, bonus: -120)), SkillStatistics(skillId: "b", treeId: "tree", name: "HTTP", totals: totals(seconds: 60, count: 1, time: 1, bonus: 20))]
        #expect(StatisticsPresentation.xpDomain(skills) == -120...60)
        #expect(skills[0].totals.totalXp == -60)
        #expect(StatisticsPresentation.xpDomain([]) == 0...1)
    }
}
