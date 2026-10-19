//
//  Progress.swift
//  Homework progress
//
//  All progress math lives here so it is centralized and unit-tested.
//

import Foundation

nonisolated enum AssignmentStatus: String, CaseIterable, Codable, Identifiable {
    case notAssigned
    case notStarted
    case inProgress
    case completed
    case postponed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notAssigned: String(localized: "Not yet assigned")
        case .notStarted: String(localized: "Not started")
        case .inProgress: String(localized: "In progress")
        case .completed: String(localized: "Completed")
        case .postponed: String(localized: "Postponed")
        }
    }

    var symbolName: String {
        switch self {
        case .notAssigned: "tray"
        case .notStarted: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .completed: "checkmark.circle.fill"
        case .postponed: "clock.arrow.circlepath"
        }
    }
}

/// Minimal value view of an assignment, used for aggregate calculations.
nonisolated struct ExerciseSnapshot: Equatable {
    var total: Int?
    var completed: Int
    var isCompleted: Bool
}

nonisolated struct AssignmentProgress: Equatable {
    let completed: Int
    let total: Int?

    /// True when a positive exercise total is known.
    var hasExerciseCount: Bool { (total ?? 0) > 0 }

    /// `nil` when the total is unknown or zero — never divides by zero. Clamped to 0...1.
    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    var percent: Int? { fraction.map { Int(($0 * 100).rounded()) } }

    /// `max(0, total - completed)`; `nil` when the total is unknown.
    var remaining: Int? {
        guard let total, total > 0 else { return nil }
        return max(0, total - completed)
    }

    /// Completed count exceeds the total (the user kept it after lowering the total).
    var isInconsistent: Bool {
        guard let total, total > 0 else { return false }
        return completed > total
    }
}

nonisolated struct ProgressSummary: Equatable {
    var completedExercises = 0
    var totalExercises = 0
    var assignmentCount = 0
    var completedAssignmentCount = 0
    /// Assignments that contributed to the exercise totals.
    var countedAssignmentCount = 0
    var inconsistentAssignmentCount = 0

    var remainingExercises: Int { max(0, totalExercises - completedExercises) }
    var openAssignmentCount: Int { assignmentCount - completedAssignmentCount }

    /// Exercise-weighted: sum(completed) / sum(total). `nil` when no assignment has a count.
    var fraction: Double? {
        guard totalExercises > 0 else { return nil }
        return Double(completedExercises) / Double(totalExercises)
    }

    var percent: Int? { fraction.map { Int(($0 * 100).rounded()) } }

    var isEmpty: Bool { assignmentCount == 0 }
}

nonisolated enum ProgressCalculator {
    static func progress(completed: Int, total: Int?) -> AssignmentProgress {
        AssignmentProgress(completed: max(0, completed), total: total)
    }

    /// Weekly / per-course progress, weighted by exercise counts (not by averaging percentages).
    /// Assignments without a positive exercise total are excluded from exercise sums but still
    /// counted in assignment statistics. Inconsistent counts are clamped to their total.
    static func summarize(_ items: [ExerciseSnapshot]) -> ProgressSummary {
        var summary = ProgressSummary()
        for item in items {
            summary.assignmentCount += 1
            if item.isCompleted { summary.completedAssignmentCount += 1 }
            guard let total = item.total, total > 0 else { continue }
            let completed = max(0, item.completed)
            summary.countedAssignmentCount += 1
            summary.totalExercises += total
            summary.completedExercises += min(completed, total)
            if completed > total { summary.inconsistentAssignmentCount += 1 }
        }
        return summary
    }
}

/// Editable exercise state with the rules for changing it. Pure value type; the model applies it.
nonisolated struct ExerciseState: Equatable {
    var total: Int?
    var completed: Int
    var status: AssignmentStatus

    enum TotalReductionChoice {
        /// Lower the completed count to the new total.
        case lowerCompleted
        /// Keep the existing completed count and flag the inconsistency.
        case keepCompleted
    }

    enum TotalChange: Equatable {
        case applied(ExerciseState)
        /// The new total is below the completed count; the caller must ask the user.
        case needsDecision(newTotal: Int, completed: Int)
    }

    private var knownTotal: Int? {
        guard let total, total > 0 else { return nil }
        return total
    }

    var canIncrement: Bool {
        guard let knownTotal else { return true }
        return completed < knownTotal
    }

    var canDecrement: Bool { completed > 0 }

    func incremented() -> ExerciseState {
        guard canIncrement else { return self }
        var next = self
        next.completed += 1
        return next.withDerivedStatus()
    }

    func decremented() -> ExerciseState {
        guard canDecrement else { return self }
        var next = self
        next.completed -= 1
        return next.withDerivedStatus()
    }

    /// Sets the completed count directly, clamped to `0...total` when a total is known.
    func settingCompleted(_ value: Int) -> ExerciseState {
        var next = self
        var clamped = max(0, value)
        if let knownTotal { clamped = min(clamped, max(knownTotal, completedIfInconsistent)) }
        next.completed = clamped
        return next.withDerivedStatus()
    }

    /// When the user already chose to keep an over-count, typing it again must not be clamped away.
    private var completedIfInconsistent: Int {
        guard let knownTotal, completed > knownTotal else { return 0 }
        return completed
    }

    /// Changes the total. Returns `.needsDecision` instead of silently changing progress when the
    /// new total is below the completed count. `nil` or `0` clears the count.
    func settingTotal(_ newTotal: Int?) -> TotalChange {
        let normalized = newTotal.map { max(0, $0) }
        if let normalized, normalized > 0, completed > normalized {
            return .needsDecision(newTotal: normalized, completed: completed)
        }
        var next = self
        next.total = normalized
        return .applied(next.withDerivedStatus())
    }

    func settingTotal(_ newTotal: Int, resolving choice: TotalReductionChoice) -> ExerciseState {
        var next = self
        next.total = max(0, newTotal)
        if choice == .lowerCompleted, newTotal > 0 { next.completed = min(completed, newTotal) }
        return next.withDerivedStatus()
    }

    /// Manual completion works with or without an exercise count. With a count, the remaining
    /// exercises are marked done so weekly totals agree with the status.
    func markedCompleted() -> ExerciseState {
        var next = self
        next.status = .completed
        if let knownTotal, completed < knownTotal { next.completed = knownTotal }
        return next
    }

    func reopened() -> ExerciseState {
        var next = self
        if let knownTotal, completed >= knownTotal { next.completed = max(0, knownTotal - 1) }
        next.status = next.completed > 0 ? .inProgress : .notStarted
        return next
    }

    func settingStatus(_ status: AssignmentStatus) -> ExerciseState {
        guard status != .completed else { return markedCompleted() }
        var next = self
        next.status = status
        return next
    }

    /// Status follows counts: all done → completed; any progress → in progress.
    /// "Postponed" and "not yet assigned" are kept unless everything is done.
    func withDerivedStatus() -> ExerciseState {
        var next = self
        if let knownTotal, completed >= knownTotal {
            next.status = .completed
            return next
        }
        switch status {
        case .completed:
            // Only un-complete when the counts prove it is unfinished.
            if knownTotal != nil { next.status = completed > 0 ? .inProgress : .notStarted }
        case .notStarted:
            if completed > 0 { next.status = .inProgress }
        case .inProgress:
            if completed == 0 { next.status = .notStarted }
        case .notAssigned:
            if completed > 0 { next.status = .inProgress }
        case .postponed:
            break
        }
        return next
    }
}
