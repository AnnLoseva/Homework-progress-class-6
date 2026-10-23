import Foundation
@testable import StudyDomain

enum Fixture {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let day: TimeInterval = 86_400
    static let course = Course(slug: "linear-algebra", title: "Linear Algebra", sortOrder: 1)
    static let otherCourse = Course(slug: "discrete", title: "Discrete Mathematics", sortOrder: 2)

    static func lesson(_ title: String, _ category: LessonCategory, status: LessonStatus = .published,
                       exercises: Int = 0, due: TimeInterval? = nil, week: Int? = 1, course: Course = Fixture.course,
                       availableFrom: Date? = nil, publishedAt: Date? = nil) -> Lesson {
        Lesson(courseID: course.id, title: title, category: category, status: status, week: week,
               availableFrom: availableFrom, dueAt: due.map { now.addingTimeInterval($0) }, exerciseCount: exercises,
               publishedAt: status == .draft ? nil : (publishedAt ?? now.addingTimeInterval(-7 * day)),
               archivedAt: status == .archived ? now.addingTimeInterval(-day) : nil)
    }

    static func progress(_ lesson: Lesson, _ status: ProgressStatus, done: Int = 0, notes: String = "") -> LessonProgress {
        LessonProgress(lessonID: lesson.id, status: status, completedExercises: done, notes: notes,
                       lastActivityAt: now, completedAt: status == .completed ? now : nil, clientModifiedAt: now)
    }
}
