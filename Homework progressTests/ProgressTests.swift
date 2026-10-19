//
//  ProgressTests.swift
//  Homework progressTests
//

import Testing
@testable import Homework_progress

@Suite("Progress calculations")
struct ProgressCalculatorTests {
    @Test func assignmentProgressBasics() {
        let progress = ProgressCalculator.progress(completed: 6, total: 9)
        #expect(progress.remaining == 3)
        #expect(progress.percent == 67)
        #expect(progress.hasExerciseCount)
        #expect(!progress.isInconsistent)
    }

    @Test func zeroTotalNeverDividesByZero() {
        let progress = ProgressCalculator.progress(completed: 0, total: 0)
        #expect(progress.fraction == nil)
        #expect(progress.percent == nil)
        #expect(progress.remaining == nil)
        #expect(!progress.hasExerciseCount)
    }

    @Test func unspecifiedTotal() {
        let progress = ProgressCalculator.progress(completed: 3, total: nil)
        #expect(progress.fraction == nil)
        #expect(progress.remaining == nil)
        #expect(!progress.isInconsistent)
    }

    @Test func overCountIsClampedAndFlagged() {
        let progress = ProgressCalculator.progress(completed: 7, total: 5)
        #expect(progress.fraction == 1)
        #expect(progress.remaining == 0)
        #expect(progress.isInconsistent)
    }

    @Test func weeklyProgressIsWeightedByExercises() {
        // 2/2 must not weigh the same as 2/20: (2 + 2) / (2 + 20) ≈ 18%, not the 55% an average would give.
        let summary = ProgressCalculator.summarize([
            ExerciseSnapshot(total: 2, completed: 2, isCompleted: true),
            ExerciseSnapshot(total: 20, completed: 2, isCompleted: false),
        ])
        #expect(summary.completedExercises == 4)
        #expect(summary.totalExercises == 22)
        #expect(summary.remainingExercises == 18)
        #expect(summary.percent == 18)
        #expect(summary.completedAssignmentCount == 1)
        #expect(summary.openAssignmentCount == 1)
    }

    @Test func exampleWeekFromSpec() {
        let summary = ProgressCalculator.summarize([
            ExerciseSnapshot(total: 9, completed: 6, isCompleted: false),
            ExerciseSnapshot(total: 12, completed: 12, isCompleted: true),
            ExerciseSnapshot(total: 8, completed: 3, isCompleted: false),
            ExerciseSnapshot(total: 6, completed: 2, isCompleted: false),
            ExerciseSnapshot(total: 4, completed: 0, isCompleted: false),
        ])
        #expect(summary.completedExercises == 23)
        #expect(summary.totalExercises == 39)
        #expect(summary.remainingExercises == 16)
        #expect(summary.percent == 59)
        #expect(summary.assignmentCount == 5)
    }

    @Test func assignmentsWithoutCountsAreExcludedFromExercisesButCountedAsAssignments() {
        let summary = ProgressCalculator.summarize([
            ExerciseSnapshot(total: nil, completed: 0, isCompleted: true),
            ExerciseSnapshot(total: 0, completed: 0, isCompleted: false),
            ExerciseSnapshot(total: 10, completed: 5, isCompleted: false),
        ])
        #expect(summary.totalExercises == 10)
        #expect(summary.completedExercises == 5)
        #expect(summary.countedAssignmentCount == 1)
        #expect(summary.assignmentCount == 3)
        #expect(summary.completedAssignmentCount == 1)
    }

    @Test func emptyAndCountlessWeeks() {
        let empty = ProgressCalculator.summarize([])
        #expect(empty.isEmpty)
        #expect(empty.fraction == nil)

        let countless = ProgressCalculator.summarize([ExerciseSnapshot(total: nil, completed: 0, isCompleted: false)])
        #expect(countless.fraction == nil)
        #expect(countless.remainingExercises == 0)
    }

    @Test func inconsistentAssignmentsDoNotPushWeekAbove100Percent() {
        let summary = ProgressCalculator.summarize([
            ExerciseSnapshot(total: 3, completed: 5, isCompleted: true),
            ExerciseSnapshot(total: 3, completed: 0, isCompleted: false),
        ])
        #expect(summary.completedExercises == 3)
        #expect(summary.percent == 50)
        #expect(summary.inconsistentAssignmentCount == 1)
    }
}

@Suite("Exercise count rules")
struct ExerciseStateTests {
    @Test func incrementStopsAtTotal() {
        var state = ExerciseState(total: 2, completed: 0, status: .notStarted)
        state = state.incremented()
        #expect(state.completed == 1)
        #expect(state.status == .inProgress)
        state = state.incremented()
        #expect(state.completed == 2)
        #expect(state.status == .completed)
        #expect(!state.canIncrement)
        #expect(state.incremented() == state)
    }

    @Test func incrementWithoutTotalIsAllowed() {
        let state = ExerciseState(total: nil, completed: 0, status: .notStarted).incremented()
        #expect(state.completed == 1)
        #expect(state.status == .inProgress)
    }

    @Test func decrementNeverGoesNegativeAndReopens() {
        var state = ExerciseState(total: 3, completed: 3, status: .completed)
        state = state.decremented()
        #expect(state.completed == 2)
        #expect(state.status == .inProgress)
        state = ExerciseState(total: 3, completed: 0, status: .notStarted).decremented()
        #expect(state.completed == 0)
    }

    @Test func settingCompletedIsClamped() {
        let state = ExerciseState(total: 5, completed: 0, status: .notStarted)
        #expect(state.settingCompleted(9).completed == 5)
        #expect(state.settingCompleted(-3).completed == 0)
    }

    @Test func raisingTotalIsApplied() {
        let state = ExerciseState(total: 5, completed: 5, status: .completed)
        guard case .applied(let next) = state.settingTotal(8) else {
            Issue.record("Expected applied")
            return
        }
        #expect(next.total == 8)
        #expect(next.completed == 5)
        #expect(next.status == .inProgress)
    }

    @Test func loweringTotalBelowCompletedNeedsADecision() {
        let state = ExerciseState(total: 10, completed: 7, status: .inProgress)
        #expect(state.settingTotal(5) == .needsDecision(newTotal: 5, completed: 7))

        let lowered = state.settingTotal(5, resolving: .lowerCompleted)
        #expect(lowered.completed == 5)
        #expect(lowered.total == 5)
        #expect(lowered.status == .completed)

        let kept = state.settingTotal(5, resolving: .keepCompleted)
        #expect(kept.completed == 7)
        #expect(kept.total == 5)
        #expect(ProgressCalculator.progress(completed: kept.completed, total: kept.total).isInconsistent)
    }

    @Test func clearingTotal() {
        let state = ExerciseState(total: 4, completed: 2, status: .inProgress)
        guard case .applied(let next) = state.settingTotal(nil) else {
            Issue.record("Expected applied")
            return
        }
        #expect(next.total == nil)
        #expect(next.completed == 2)
        guard case .applied(let zero) = state.settingTotal(0) else {
            Issue.record("Expected applied")
            return
        }
        #expect(zero.total == 0)
    }

    @Test func manualCompletionWithoutCount() {
        let state = ExerciseState(total: nil, completed: 0, status: .notStarted).markedCompleted()
        #expect(state.status == .completed)
        #expect(state.completed == 0)
        // Changing nothing about counts must not silently un-complete it.
        #expect(state.withDerivedStatus().status == .completed)
    }

    @Test func manualCompletionWithCountFillsRemaining() {
        let state = ExerciseState(total: 6, completed: 2, status: .inProgress).markedCompleted()
        #expect(state.completed == 6)
        #expect(state.status == .completed)
        let reopened = state.reopened()
        #expect(reopened.status == .inProgress)
        #expect(reopened.completed == 5)
    }

    @Test func postponedIsKeptUntilFinished() {
        var state = ExerciseState(total: 2, completed: 0, status: .postponed).incremented()
        #expect(state.status == .postponed)
        state = state.incremented()
        #expect(state.status == .completed)
    }
}
