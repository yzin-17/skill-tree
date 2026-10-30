import Foundation

public enum StatisticsPresentation {
    public static func focusBuckets(_ series: [StatisticsBucket]) -> [StatisticsBucket] {
        series.filter { $0.totals.focusCount > 0 || $0.totals.focusSeconds > 0 }
    }
    public static func attemptBuckets(_ series: [StatisticsBucket]) -> [StatisticsBucket] {
        series.filter { $0.totals.attempts.total > 0 && $0.totals.attempts.successRate != nil }
    }
    public static func xpDomain(_ skills: [SkillStatistics]) -> ClosedRange<Double> {
        let low = min(0, skills.map { Double($0.totals.taskBonusXp) }.min() ?? 0)
        let high = max(1, skills.map { Double($0.totals.timeXp + max(0, $0.totals.taskBonusXp)) }.max() ?? 1)
        return low...high
    }
}
