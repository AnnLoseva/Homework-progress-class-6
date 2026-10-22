import Foundation
import Testing
@testable import StudyDomain

@Suite("Workload")
struct WorkloadTests {
    let required = Fixture.lesson("Vectors", .required, exercises: 8)
    let optional = Fixture.lesson("Extra drills", .optional, exercises: 12)
    let draft = Fixture.lesson("Eigenvalues", .required, status: .draft)
    let archived = Fixture.lesson("Old notes", .optional, status: .archived)
    let scheduled = Fixture.lesson("Next week", .required, availableFrom: Fixture.now.addingTimeInterval(Fixture.day))

    var catalog: Catalog { Catalog(courses: [Fixture.course], lessons: [required, optional, draft, archived, scheduled]) }

    @Test func requiredLessonsAreAlwaysInTheWorkload() {
        let lessons = Workload.lessons(in: catalog, subscriptions: [:], now: Fixture.now)
        #expect(lessons.map(\.id) == [required.id])
        #expect(Workload.membership(of: required, subscriptions: [:], now: Fixture.now) == .required)
    }

    @Test func requiredLessonsStayEvenWithAnInactiveSubscriptionRow() {
        // e.g. left over from when the lesson was optional
        let subs = [required.id: LessonSubscription(lessonID: required.id, isActive: false)]
        #expect(Workload.contains(required, subscriptions: subs, now: Fixture.now))
    }

    @Test func optionalLessonsCountOnlyWhenSubscribed() {
        #expect(!Workload.contains(optional, subscriptions: [:], now: Fixture.now))
        let active = [optional.id: LessonSubscription(lessonID: optional.id, isActive: true)]
        #expect(Workload.contains(optional, subscriptions: active, now: Fixture.now))
        let inactive = [optional.id: LessonSubscription(lessonID: optional.id, isActive: false)]
        #expect(!Workload.contains(optional, subscriptions: inactive, now: Fixture.now))
    }

    @Test func draftsArchivedAndScheduledLessonsAreNeverActiveWork() {
        let all = Dictionary(uniqueKeysWithValues: catalog.lessons.map { ($0.id, LessonSubscription(lessonID: $0.id, isActive: true)) })
        for lesson in [draft, archived, scheduled] {
            #expect(!Workload.contains(lesson, subscriptions: all, now: Fixture.now))
            #expect(Workload.membership(of: lesson, subscriptions: all, now: Fixture.now) == .inactive)
        }
    }

    @Test func scheduledLessonBecomesActiveWhenAvailable() {
        #expect(Workload.contains(scheduled, subscriptions: [:], now: Fixture.now.addingTimeInterval(2 * Fixture.day)))
    }
}

@Suite("Dashboard")
struct DashboardTests {
    @Test func emptyWorkloadHasNoPercentages() {
        let summary = DashboardSummary.make(catalog: .empty, subscriptions: [:], progress: [:], now: Fixture.now)
        #expect(summary.isEmpty)
        #expect(summary.lessonCompletionFraction == nil)
        #expect(summary.exerciseCompletionFraction == nil)
        #expect(!summary.isAllDone)
    }

    @Test func unsubscribedOptionalLessonsDoNotCountAsRemainingWork() {
        let required = Fixture.lesson("Required", .required, exercises: 4)
        let optional = Fixture.lesson("Optional", .optional, exercises: 100)
        let catalog = Catalog(courses: [Fixture.course], lessons: [required, optional])
        let summary = DashboardSummary.make(catalog: catalog, subscriptions: [:],
                                            progress: [required.id: Fixture.progress(required, .completed, done: 4)],
                                            now: Fixture.now)
        #expect(summary.remainingLessonCount == 0)
        #expect(summary.totalExerciseCount == 4)
        #expect(summary.isAllDone)
    }

    @Test func exerciseCompletionIsWeightedNotAnAverageOfPercentages() {
        // Tiny lesson: 2/2 (100 %). Big lesson: 2/20 (10 %).
        // Average of percentages would be 55 %; weighted is 4/22 ≈ 18 %.
        let tiny = Fixture.lesson("Tiny", .required, exercises: 2)
        let big = Fixture.lesson("Big", .required, exercises: 20)
        let summary = DashboardSummary.make(
            catalog: Catalog(courses: [Fixture.course], lessons: [tiny, big]), subscriptions: [:],
            progress: [tiny.id: Fixture.progress(tiny, .completed, done: 2), big.id: Fixture.progress(big, .inProgress, done: 2)],
            now: Fixture.now)
        #expect(summary.completedExerciseCount == 4)
        #expect(summary.totalExerciseCount == 22)
        #expect(abs(summary.exerciseCompletionFraction! - 4.0 / 22.0) < 0.0001)
        // Lesson completion is a separate metric: 1 of 2 lessons.
        #expect(summary.lessonCompletionFraction == 0.5)
    }

    @Test func lessonsWithoutExercisesDoNotDistortExerciseProgress() {
        let reading = Fixture.lesson("Reading", .required, exercises: 0)
        let sheet = Fixture.lesson("Sheet", .required, exercises: 10)
        let summary = DashboardSummary.make(
            catalog: Catalog(courses: [Fixture.course], lessons: [reading, sheet]), subscriptions: [:],
            progress: [reading.id: Fixture.progress(reading, .completed), sheet.id: Fixture.progress(sheet, .inProgress, done: 5)],
            now: Fixture.now)
        #expect(summary.exerciseCompletionFraction == 0.5)
        #expect(summary.completedLessonCount == 1)
    }

    @Test func completedCountIgnoresAStaleCounterAboveTheTotal() {
        // The administrator lowered the exercise count from 10 to 6 after the student did 8.
        let lesson = Fixture.lesson("Shrunk", .required, exercises: 6)
        let summary = DashboardSummary.make(catalog: Catalog(courses: [Fixture.course], lessons: [lesson]), subscriptions: [:],
                                            progress: [lesson.id: Fixture.progress(lesson, .inProgress, done: 8)], now: Fixture.now)
        #expect(summary.completedExerciseCount == 6)
        #expect(summary.exerciseCompletionFraction == 1)
    }

    @Test func nextUpPutsDeadlinesFirstThenRequiredWork() {
        let noDate = Fixture.lesson("No date", .required, week: 1)
        let later = Fixture.lesson("Later", .required, due: 5 * Fixture.day)
        let soon = Fixture.lesson("Soon", .optional, due: 1 * Fixture.day)
        let optionalNoDate = Fixture.lesson("Optional no date", .optional, week: 0)
        let done = Fixture.lesson("Done", .required, due: 0.5 * Fixture.day)
        let subs = [soon.id: LessonSubscription(lessonID: soon.id, isActive: true),
                    optionalNoDate.id: LessonSubscription(lessonID: optionalNoDate.id, isActive: true)]
        let summary = DashboardSummary.make(
            catalog: Catalog(courses: [Fixture.course], lessons: [noDate, later, soon, optionalNoDate, done]),
            subscriptions: subs, progress: [done.id: Fixture.progress(done, .completed)], now: Fixture.now)
        #expect(summary.nextUp.map(\.lesson.title) == ["Soon", "Later", "No date", "Optional no date"])
        #expect(summary.upcomingDeadlines.map(\.lesson.title) == ["Soon", "Later"])
        #expect(summary.optionalSubscribed.count == 2)
    }

    @Test func overdueAndInProgressBuckets() {
        let overdue = Fixture.lesson("Overdue", .required, due: -Fixture.day)
        let started = Fixture.lesson("Started", .required, exercises: 3)
        let summary = DashboardSummary.make(
            catalog: Catalog(courses: [Fixture.course], lessons: [overdue, started]), subscriptions: [:],
            progress: [started.id: Fixture.progress(started, .inProgress, done: 1)], now: Fixture.now)
        #expect(summary.overdue.map(\.lesson.title) == ["Overdue"])
        #expect(summary.requiredInProgress.map(\.lesson.title) == ["Started"])
        #expect(summary.requiredNotStarted.map(\.lesson.title) == ["Overdue"])
    }

    @Test func historyKeepsArchivedUnsubscribedAndUnavailableWork() {
        let archived = Fixture.lesson("Archived", .optional, status: .archived)
        let unsubscribed = Fixture.lesson("Dropped", .optional, exercises: 4)
        let active = Fixture.lesson("Active", .required)
        let vanished = UUID()   // unpublished: not in the catalog any more
        let progress = [
            archived.id: Fixture.progress(archived, .completed),
            unsubscribed.id: Fixture.progress(unsubscribed, .inProgress, done: 2),
            active.id: Fixture.progress(active, .inProgress),
            vanished: LessonProgress(lessonID: vanished, status: .inProgress, notes: "kept"),
        ]
        let entries = StudyHistory.entries(
            catalog: Catalog(courses: [Fixture.course], lessons: [archived, unsubscribed, active]),
            subscriptions: [unsubscribed.id: LessonSubscription(lessonID: unsubscribed.id, isActive: false)],
            progress: progress, now: Fixture.now)
        let reasons = Dictionary(uniqueKeysWithValues: entries.map { ($0.lessonID, $0.reason) })
        #expect(reasons[archived.id] == .archived)
        #expect(reasons[unsubscribed.id] == .unsubscribed)
        #expect(reasons[vanished] == .unavailable)
        #expect(reasons[active.id] == nil)
    }
}
