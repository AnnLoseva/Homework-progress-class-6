import Foundation

public enum ProgressValidationError: Error, Equatable, Sendable {
    case exerciseCountOutOfRange(maximum: Int)
    case notStartedWithExercises
    case notesTooLong(maximum: Int)
    case lessonNotAvailable
}

/// The progress rules, applied on the device before a change is queued. The database
/// enforces the same rules again in `private.progress_before_write`.
///
/// Lesson completion (`status`) and exercise completion (`completedExercises`) are separate:
/// a student may mark a lesson completed without ticking every exercise.
public enum ProgressRules {
    public static let maxNotesLength = 20_000

    public static func validate(_ progress: LessonProgress, for lesson: Lesson, now: Date) throws {
        guard lesson.isVisibleToStudents(at: now) else { throw ProgressValidationError.lessonNotAvailable }
        guard (0...lesson.exerciseCount).contains(progress.completedExercises) else {
            throw ProgressValidationError.exerciseCountOutOfRange(maximum: lesson.exerciseCount)
        }
        if progress.status == .notStarted && progress.completedExercises != 0 {
            throw ProgressValidationError.notStartedWithExercises
        }
        if progress.notes.count > maxNotesLength {
            throw ProgressValidationError.notesTooLong(maximum: maxNotesLength)
        }
    }

    /// Sets the completed-exercise counter (clamped to the lesson's range) and moves the
    /// status along: starting work → in progress; finishing every exercise → completed;
    /// going back below the total → in progress again.
    public static func settingCompletedExercises(_ count: Int, on progress: LessonProgress,
                                                 lesson: Lesson, at date: Date) -> LessonProgress {
        var next = progress
        let clamped = min(max(count, 0), lesson.exerciseCount)
        next.completedExercises = clamped

        if lesson.hasExercises && clamped == lesson.exerciseCount {
            next.status = .completed
        } else if clamped > 0 {
            next.status = .inProgress
        } else if next.status == .completed {
            next.status = .inProgress
        }
        return stamped(next, from: progress, at: date)
    }

    /// Sets the lesson status. "Not started" resets the counter; "completed" keeps it as it
    /// is, because finishing a lesson does not require every exercise.
    public static func settingStatus(_ status: ProgressStatus, on progress: LessonProgress,
                                     lesson: Lesson, at date: Date) -> LessonProgress {
        var next = progress
        next.status = status
        if status == .notStarted { next.completedExercises = 0 }
        next.completedExercises = min(next.completedExercises, lesson.exerciseCount)
        return stamped(next, from: progress, at: date)
    }

    public static func settingNotes(_ notes: String, on progress: LessonProgress,
                                    lesson: Lesson, at date: Date) -> LessonProgress {
        var next = progress
        next.notes = String(notes.prefix(maxNotesLength))
        next.completedExercises = min(next.completedExercises, lesson.exerciseCount)
        return stamped(next, from: progress, at: date)
    }

    /// Brings a stored row back in range if the administrator lowered the exercise count.
    /// The stored value is kept on the server; this only affects what is shown and sent.
    public static func clamped(_ progress: LessonProgress, to lesson: Lesson) -> LessonProgress {
        var next = progress
        next.completedExercises = min(max(progress.completedExercises, 0), lesson.exerciseCount)
        if next.status == .notStarted { next.completedExercises = 0 }
        return next
    }

    private static func stamped(_ next: LessonProgress, from previous: LessonProgress, at date: Date) -> LessonProgress {
        var next = next
        next.lastActivityAt = date
        // Never go backwards in time on this device, even if the clock was adjusted.
        next.clientModifiedAt = max(date, previous.clientModifiedAt.addingTimeInterval(0.001))
        if next.status == .completed {
            next.completedAt = previous.status == .completed ? previous.completedAt : date
        } else {
            next.completedAt = nil
        }
        return next
    }
}
