import Foundation

public struct ActivityCalendarDay: Identifiable, Sendable {
    public let date: Date
    public let number: Int
    public let isInMonth: Bool
    public let isToday: Bool
    public var id: Date { date }
}

public struct ActivityCalendarMonth: Sendable {
    public let calendar: Calendar
    public let start: Date
    public let end: Date
    public let days: [ActivityCalendarDay]

    public init(containing date: Date, timezone: String, now: Date = .now) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .gmt
        calendar.firstWeekday = 2
        self.calendar = calendar
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        self.start = start
        self.end = end
        let leading = (calendar.component(.weekday, from: start) + 5) % 7
        let first = calendar.date(byAdding: .day, value: -leading, to: start)!
        days = (0..<42).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: first)!
            return .init(date: day, number: calendar.component(.day, from: day),
                         isInMonth: day >= start && day < end,
                         isToday: calendar.isDate(day, inSameDayAs: now))
        }
    }

    public func moving(_ months: Int) -> Date {
        calendar.date(byAdding: .month, value: months, to: start)!
    }

    public func query(skillID: String) -> [URLQueryItem] {
        let formatter = ISO8601DateFormatter()
        return [.init(name: "from", value: formatter.string(from: start)),
                .init(name: "to", value: formatter.string(from: end)),
                .init(name: "bucket", value: "day"), .init(name: "skill_id", value: skillID)]
    }

    public func bucket(on date: Date, in series: [StatisticsBucket]) -> StatisticsBucket? {
        let day = calendar.startOfDay(for: date)
        return series.first { calendar.startOfDay(for: $0.start) == day }
    }

    public func activeDayCount(in series: [StatisticsBucket]) -> Int {
        Set(series.filter { $0.start >= start && $0.start < end && Self.hasRecords($0) }
            .map { calendar.startOfDay(for: $0.start) }).count
    }

    public static func hasRecords(_ bucket: StatisticsBucket) -> Bool {
        let totals = bucket.totals
        return totals.focusCount > 0 || totals.attempts.total > 0 || totals.attempts.retries > 0
            || !bucket.sources.records.isEmpty
    }
}
