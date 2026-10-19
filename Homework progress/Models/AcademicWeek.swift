//
//  AcademicWeek.swift
//  Homework progress
//

import Foundation
import SwiftData

/// The main organizational unit. Each week owns its own assignment records and progress.
@Model
final class AcademicWeek {
    var id: UUID
    var title: String
    /// Optional semester week number, used to suggest the next week's title.
    var number: Int?
    /// Start of the first day of the week (local time).
    var startDate: Date
    /// Start of the last day of the week (local time). Inclusive.
    var endDate: Date
    var notes: String
    var createdAt: Date

    /// Deleting a week deletes only its own assignments; courses are untouched.
    @Relationship(deleteRule: .cascade, inverse: \HomeworkAssignment.week)
    var assignments: [HomeworkAssignment] = []

    init(
        id: UUID = UUID(),
        title: String,
        number: Int? = nil,
        startDate: Date,
        endDate: Date,
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.number = number
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.createdAt = createdAt
    }

    var dateRangeText: String { WeekPlanner.rangeText(start: startDate, end: endDate) }

    /// "Week 5 — Oct 18–24"
    var fullLabel: String { "\(title) — \(dateRangeText)" }

    var summary: ProgressSummary {
        ProgressCalculator.summarize(assignments.map(\.snapshot))
    }

    static func chronological(_ lhs: AcademicWeek, _ rhs: AcademicWeek) -> Bool {
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        return lhs.createdAt < rhs.createdAt
    }
}
