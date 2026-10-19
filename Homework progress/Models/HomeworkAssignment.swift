//
//  HomeworkAssignment.swift
//  Homework progress
//

import Foundation
import SwiftData

/// A homework assignment. Belongs to exactly one course and one week (enforced by `HomeworkStore`).
@Model
final class HomeworkAssignment {
    var id: UUID
    var title: String
    var course: Course?
    var week: AcademicWeek?
    var dueDate: Date?
    /// `nil` means "not specified". Zero is treated the same way by progress calculations.
    var totalExercises: Int?
    var completedExercises: Int
    var notes: String
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \HomeworkAttachment.assignment)
    var attachments: [HomeworkAttachment] = []

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date? = nil,
        totalExercises: Int? = nil,
        completedExercises: Int = 0,
        notes: String = "",
        status: AssignmentStatus = .notStarted,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.totalExercises = totalExercises
        self.completedExercises = completedExercises
        self.notes = notes
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var status: AssignmentStatus {
        get { AssignmentStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    var isCompleted: Bool { status == .completed }

    var exerciseState: ExerciseState {
        ExerciseState(total: totalExercises, completed: completedExercises, status: status)
    }

    /// Writes a new exercise state and bumps the modification date.
    func apply(_ state: ExerciseState) {
        guard state != exerciseState else { return }
        totalExercises = state.total
        completedExercises = state.completed
        status = state.status
        touch()
    }

    func touch() { updatedAt = .now }

    var snapshot: ExerciseSnapshot {
        ExerciseSnapshot(total: totalExercises, completed: completedExercises, isCompleted: isCompleted)
    }

    var progress: AssignmentProgress {
        ProgressCalculator.progress(completed: completedExercises, total: totalExercises)
    }

    var sortedAttachments: [HomeworkAttachment] {
        attachments.sorted { ($0.sortIndex, $0.importedAt) < ($1.sortIndex, $1.importedAt) }
    }

    static func defaultOrder(_ lhs: HomeworkAssignment, _ rhs: HomeworkAssignment) -> Bool {
        if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
        switch (lhs.dueDate, rhs.dueDate) {
        case let (l?, r?) where l != r: return l < r
        case (.some, nil): return true
        case (nil, .some): return false
        default: return lhs.createdAt < rhs.createdAt
        }
    }
}
