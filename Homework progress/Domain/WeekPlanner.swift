//
//  WeekPlanner.swift
//  Homework progress
//

import Foundation

/// Date math for academic weeks. Weeks are stored as [first day, last day] at start-of-day.
nonisolated struct WeekPlanner {
    var calendar: Calendar

    /// Israeli academic weeks run Sunday–Saturday by default.
    init(calendar: Calendar = .current, firstWeekday: Int = 1) {
        var calendar = calendar
        calendar.firstWeekday = firstWeekday
        self.calendar = calendar
    }

    struct Range: Equatable {
        var start: Date
        var end: Date
    }

    func range(containing date: Date) -> Range {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: day) ?? day
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return Range(start: start, end: end)
    }

    /// The seven days after `end`.
    func range(after end: Date) -> Range {
        let start = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        let last = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return Range(start: start, end: last)
    }

    func normalized(start: Date, end: Date) -> Range {
        let s = calendar.startOfDay(for: start)
        let e = calendar.startOfDay(for: end)
        return Range(start: min(s, e), end: max(s, e))
    }

    func contains(_ date: Date, start: Date, end: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: start) && day <= calendar.startOfDay(for: end)
    }

    /// Whole days between two week starts, used to shift due dates when duplicating a week.
    func dayOffset(from: Date, to: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }

    func shift(_ date: Date, byDays days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    enum Timing: Equatable { case past, current, upcoming }

    func timing(start: Date, end: Date, today: Date = .now) -> Timing {
        if contains(today, start: start, end: end) { return .current }
        return calendar.startOfDay(for: end) < calendar.startOfDay(for: today) ? .past : .upcoming
    }

    /// The week containing today, else the nearest upcoming week, else the latest past week.
    func preferredWeek<W>(in weeks: [W], today: Date = .now, start: (W) -> Date, end: (W) -> Date) -> W? {
        if let current = weeks.first(where: { contains(today, start: start($0), end: end($0)) }) { return current }
        let day = calendar.startOfDay(for: today)
        let upcoming = weeks.filter { start($0) > day }.min { start($0) < start($1) }
        return upcoming ?? weeks.max { start($0) < start($1) }
    }

    static func nextNumber(after numbers: [Int?]) -> Int {
        (numbers.compactMap { $0 }.max() ?? numbers.count) + 1
    }

    static func defaultTitle(number: Int) -> String {
        String(localized: "Week \(number)")
    }

    /// Locale-aware: "Oct 18 – 24" (US), "18–24 Oct" (UK/Israel), "18–24 окт." (Russian).
    static func rangeText(start: Date, end: Date) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateTemplate = "MMMd"
        return formatter.string(from: start, to: end)
    }
}
