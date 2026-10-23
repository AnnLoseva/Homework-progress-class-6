import Foundation
import Testing
@testable import StudyDomain

@Suite("Progress rules")
struct ProgressRulesTests {
    let sheet = Fixture.lesson("Sheet", .required, exercises: 5)
    let reading = Fixture.lesson("Reading", .optional, exercises: 0)
    var start: LessonProgress { .empty(for: sheet.id, at: Fixture.now.addingTimeInterval(-60)) }

    @Test func tickingTheFirstExerciseStartsTheLesson() {
        let next = ProgressRules.settingCompletedExercises(1, on: start, lesson: sheet, at: Fixture.now)
        #expect(next.status == .inProgress)
        #expect(next.completedExercises == 1)
        #expect(next.completedAt == nil)
        #expect(next.lastActivityAt == Fixture.now)
    }

    @Test func finishingEveryExerciseCompletesTheLesson() {
        let next = ProgressRules.settingCompletedExercises(5, on: start, lesson: sheet, at: Fixture.now)
        #expect(next.status == .completed)
        #expect(next.completedAt == Fixture.now)
    }

    @Test func goingBelowTheTotalReopensTheLesson() {
        let done = ProgressRules.settingCompletedExercises(5, on: start, lesson: sheet, at: Fixture.now)
        let reopened = ProgressRules.settingCompletedExercises(4, on: done, lesson: sheet, at: Fixture.now.addingTimeInterval(1))
        #expect(reopened.status == .inProgress)
        #expect(reopened.completedAt == nil)
    }

    @Test func countsAreClampedToTheLessonRange() {
        #expect(ProgressRules.settingCompletedExercises(99, on: start, lesson: sheet, at: Fixture.now).completedExercises == 5)
        #expect(ProgressRules.settingCompletedExercises(-3, on: start, lesson: sheet, at: Fixture.now).completedExercises == 0)
    }

    @Test func lessonsWithoutExercisesAreCompletedManually() {
        let base = LessonProgress.empty(for: reading.id, at: Fixture.now.addingTimeInterval(-60))
        #expect(ProgressRules.settingCompletedExercises(3, on: base, lesson: reading, at: Fixture.now).completedExercises == 0)
        let done = ProgressRules.settingStatus(.completed, on: base, lesson: reading, at: Fixture.now)
        #expect(done.status == .completed)
        #expect(done.completedAt == Fixture.now)
        #expect(throws: Never.self) { try ProgressRules.validate(done, for: reading, now: Fixture.now) }
    }

    @Test func markingCompletedKeepsTheExerciseCount() {
        let partly = ProgressRules.settingCompletedExercises(2, on: start, lesson: sheet, at: Fixture.now)
        let done = ProgressRules.settingStatus(.completed, on: partly, lesson: sheet, at: Fixture.now.addingTimeInterval(1))
        #expect(done.status == .completed)
        #expect(done.completedExercises == 2, "lesson completion is separate from exercise completion")
    }

    @Test func resettingToNotStartedClearsTheCounter() {
        let partly = ProgressRules.settingCompletedExercises(3, on: start, lesson: sheet, at: Fixture.now)
        let reset = ProgressRules.settingStatus(.notStarted, on: partly, lesson: sheet, at: Fixture.now.addingTimeInterval(1))
        #expect(reset.completedExercises == 0)
        #expect(throws: Never.self) { try ProgressRules.validate(reset, for: sheet, now: Fixture.now) }
    }

    @Test func completedAtSurvivesFurtherEditsWhileCompleted() {
        let done = ProgressRules.settingStatus(.completed, on: start, lesson: sheet, at: Fixture.now)
        let noted = ProgressRules.settingNotes("great", on: done, lesson: sheet, at: Fixture.now.addingTimeInterval(100))
        #expect(noted.completedAt == Fixture.now)
    }

    @Test func clientTimestampsNeverGoBackwards() {
        let first = ProgressRules.settingNotes("a", on: start, lesson: sheet, at: Fixture.now)
        // The device clock jumped back an hour.
        let second = ProgressRules.settingNotes("b", on: first, lesson: sheet, at: Fixture.now.addingTimeInterval(-3600))
        #expect(second.clientModifiedAt > first.clientModifiedAt)
    }

    @Test func validationRejectsInconsistentStates() {
        var bad = start
        bad.completedExercises = 6
        bad.status = .inProgress
        #expect(throws: ProgressValidationError.exerciseCountOutOfRange(maximum: 5)) { try ProgressRules.validate(bad, for: sheet, now: Fixture.now) }

        bad.completedExercises = 2
        bad.status = .notStarted
        #expect(throws: ProgressValidationError.notStartedWithExercises) { try ProgressRules.validate(bad, for: sheet, now: Fixture.now) }

        bad.status = .inProgress
        bad.notes = String(repeating: "x", count: ProgressRules.maxNotesLength + 1)
        #expect(throws: ProgressValidationError.notesTooLong(maximum: ProgressRules.maxNotesLength)) { try ProgressRules.validate(bad, for: sheet, now: Fixture.now) }
    }

    @Test func progressOnDraftLessonsIsRejected() {
        let draft = Fixture.lesson("Draft", .required, status: .draft)
        #expect(throws: ProgressValidationError.lessonNotAvailable) {
            try ProgressRules.validate(.empty(for: draft.id), for: draft, now: Fixture.now)
        }
    }

    @Test func notesAreTruncatedToTheLimit() {
        let long = String(repeating: "é", count: ProgressRules.maxNotesLength + 50)
        #expect(ProgressRules.settingNotes(long, on: start, lesson: sheet, at: Fixture.now).notes.count == ProgressRules.maxNotesLength)
    }
}
