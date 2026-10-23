//
//  ClassSubscriptionPassTests.swift
//  Homework progressTests
//
//  "Subscribe to class" end to end against the in-memory class backend: fetch the class,
//  copy the lessons of every subscribed course into the weeks, and put this week's class
//  assignments in the week containing today, without duplicates or lost progress.
//

import Foundation
import SwiftData
import Testing
@testable import Homework_progress
import ClassroomUI
import StudyData
import StudyDomain

@MainActor
@Suite("Subscribe to class: lessons reach this week")
struct ClassSubscriptionPassTests {
    let env: TestEnvironment
    let studentID = UUID()
    let adminID = UUID()
    /// Wednesday; weeks run Sunday–Saturday (the app's default), so this week is 18–24 Oct.
    let now = date(2026, 10, 21)
    let planner = WeekPlanner(firstWeekday: 1)
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent("SubscriptionPass-\(UUID().uuidString)")

    // Three class courses, published from the seeded homework courses (same slugs).
    let algebra = StudyDomain.Course(slug: "linear-algebra-data-representation-a", title: "אלגברה ליניארית וייצוג נתונים - חלק א",
                                     subtitle: "Linear Algebra & Data Representation A", sortOrder: 0)
    let analysis = StudyDomain.Course(slug: "introduction-to-analysis", title: "מבוא לאנליזה",
                                      subtitle: "Introduction to Analysis", sortOrder: 2)
    let discrete = StudyDomain.Course(slug: "discrete-mathematics", title: "מתמטיקה בדידה",
                                      subtitle: "Discrete Mathematics", sortOrder: 4)

    /// This week (week 1): two algebra lessons, three discrete ones. Next week (week 2): one
    /// analysis lesson and one algebra lesson. Analysis has nothing this week.
    let lessons: [Lesson]

    init() throws {
        env = try TestEnvironment()
        _ = try env.seed()
        let (algebra, analysis, discrete) = (algebra, analysis, discrete)
        lessons = [
            Self.lesson("Targil 1", algebra, week: 1, due: date(2026, 10, 22)),
            Self.lesson("HW1", algebra, week: 1, due: date(2026, 10, 23), category: .optional),
            Self.lesson("Logic 1", discrete, week: 1, due: date(2026, 10, 22)),
            Self.lesson("Quantifiers", discrete, week: 1, due: date(2026, 10, 23)),
            Self.lesson("DNF and CNF", discrete, week: 1, due: date(2026, 10, 24), category: .optional),
            Self.lesson("List 1", analysis, week: 2, due: date(2026, 10, 28)),
            Self.lesson("Targil 2", algebra, week: 2, due: date(2026, 10, 29)),
        ]
    }

    static func lesson(_ title: String, _ course: StudyDomain.Course, week: Int, due: Date,
                       category: LessonCategory = .required, exercises: Int = 5) -> Lesson {
        Lesson(courseID: course.id, title: title, category: category, status: .published, week: week,
               moduleTitle: "Week \(week)", dueAt: due, exerciseCount: exercises, publishedAt: date(2026, 10, 1))
    }

    func makeServer(_ lessons: [Lesson]? = nil) async -> InMemoryServer {
        let server = InMemoryServer(catalog: Catalog(courses: [algebra, analysis, discrete], lessons: lessons ?? self.lessons))
        await server.addUser(studentID, isEnrolled: true)
        await server.addUser(adminID, isAdmin: true)
        return server
    }

    /// A student store as the app has it after sign-in: the cache is loaded, nothing fetched yet.
    func makeStudent(_ server: InMemoryServer, network: NetworkSwitch = NetworkSwitch()) async -> StudentStore {
        let store = StudentStore(userID: studentID, backend: InMemoryConnection(server: server, userID: studentID, network: network),
                                 snapshots: SnapshotStore(directory: cache), automaticRetry: false)
        await store.loadCache()
        return store
    }

    func pass(_ student: StudentStore, skipping skipped: Set<UUID> = []) -> ClassSubscriptionPass {
        ClassSubscriptionPass(student: student, importer: ClassHomeworkImporter(
            store: env.store, planner: planner, ledger: ClassImportLedger(defaults: env.defaults),
            skippedCourses: skipped, fetchFile: { _ in throw URLError(.notConnectedToInternet) }))
    }

    func thisWeek() throws -> AcademicWeek? {
        try env.context.fetch(FetchDescriptor<AcademicWeek>()).first { planner.contains(now, start: $0.startDate, end: $0.endDate) }
    }

    func allAssignments() throws -> [HomeworkAssignment] {
        try env.context.fetch(FetchDescriptor<HomeworkAssignment>())
    }

    // 1, 2, 3: every course, every lesson of a course, and courses without work this week.
    @Test func subscribingPutsThisWeeksLessonsOfEveryCourseInTheCurrentWeek() async throws {
        let student = await makeStudent(await makeServer())
        var subject = pass(student)

        let outcome = try #require(await subject.run(refresh: true, now: now))

        let week = try #require(try thisWeek(), "the week containing today exists")
        let titles = Set(week.assignmentList.map(\.title))
        #expect(titles == ["Targil 1", "HW1", "Logic 1", "Quantifiers", "DNF and CNF"])
        let courses = Set(week.assignmentList.compactMap { $0.course?.englishName })
        #expect(courses == ["Linear Algebra & Data Representation A", "Discrete Mathematics"])
        #expect(outcome.thisWeek == 5)
        #expect(outcome.weekToShow?.id == week.id, "subscribing opens this week")
        guard case .done(let message) = outcome.phase else { Issue.record("expected success"); return }
        #expect(message.contains("5"))

        // Each copy shows title, course, due date and its own progress.
        let logic = try #require(week.assignmentList.first { $0.title == "Logic 1" })
        #expect(logic.course?.englishName == "Discrete Mathematics")
        #expect(logic.dueDate == date(2026, 10, 22))
        #expect(logic.totalExercises == 5 && logic.status == .notStarted)
    }

    // 7: next week's lessons go to next week, never this one.
    @Test func nextWeeksLessonsStayInNextWeek() async throws {
        var subject = pass(await makeStudent(await makeServer()))
        _ = await subject.run(refresh: true, now: now)

        let week = try #require(try thisWeek())
        #expect(!week.assignmentList.contains { $0.title == "List 1" || $0.title == "Targil 2" })
        let next = try #require(try allAssignments().first { $0.title == "List 1" }?.week)
        #expect(next.number == 2)
        #expect(planner.contains(date(2026, 10, 25), start: next.startDate, end: next.endDate), "week 2 follows week 1")
        #expect(try allAssignments().first { $0.title == "Targil 2" }?.week?.id == next.id)
    }

    // A class week number lands on the user's own calendar, not on an unrelated week.
    @Test func lessonsJoinTheStudentsOwnCurrentWeekEvenIfItIsNumberedDifferently() async throws {
        // The student numbers weeks their own way: this week is their "Week 3".
        let own = env.store.createWeek(title: "Week 3", number: 3, start: date(2026, 10, 18), end: date(2026, 10, 24))
        let shifted = lessons.map { lesson -> Lesson in
            var lesson = lesson
            lesson.week = (lesson.week ?? 0) + 2       // class week 3 = this week, 4 = next week
            return lesson
        }
        var subject = pass(await makeStudent(await makeServer(shifted)))
        _ = await subject.run(refresh: true, now: now)

        #expect(own.assignmentList.count == 5)
        let next = try #require(try allAssignments().first { $0.title == "List 1" }?.week)
        #expect(next.number == 4 && planner.contains(date(2026, 10, 27), start: next.startDate, end: next.endDate))
    }

    // 4, 5: reopening, relaunching and subscribing again never duplicate anything.
    @Test func runningAgainAfterARelaunchOrResubscribingAddsNothing() async throws {
        let server = await makeServer()
        var first = pass(await makeStudent(server))
        _ = await first.run(refresh: true, now: now)
        let count = try allAssignments().count
        #expect(count == 7)

        // Same pass again (screen reopened), then a "relaunch": new store from the saved cache,
        // new importer from the saved ledger.
        _ = await first.run(refresh: false, now: now)
        var relaunched = pass(await makeStudent(server))
        let again = try #require(await relaunched.run(refresh: true, now: now))

        #expect(try allAssignments().count == count)
        #expect(Set(try allAssignments().map(\.id)).count == count, "one assignment per lesson")
        #expect(try env.context.fetch(FetchDescriptor<AcademicWeek>()).count == 2)
        #expect(again.report.added == 0)
        #expect(again.weekToShow == nil, "nothing new, so the dashboard isn't moved")
        #expect(again.thisWeek == 5)
    }

    // 6: a course that isn't subscribed adds nothing; neither does a lesson of it this week.
    @Test func coursesThatArentSubscribedStayOutOfTheWeek() async throws {
        var subject = pass(await makeStudent(await makeServer()), skipping: [discrete.id])
        let outcome = try #require(await subject.run(refresh: true, now: now))

        let week = try #require(try thisWeek())
        #expect(Set(week.assignmentList.map(\.title)) == ["Targil 1", "HW1"])
        #expect(outcome.thisWeek == 2)
    }

    // 3/7 for an empty week: no class work this week is a normal, successful state.
    @Test func aWeekWithoutClassWorkIsNotAnError() async throws {
        let later = [Self.lesson("List 1", analysis, week: 2, due: date(2026, 10, 28))]
        var subject = pass(await makeStudent(await makeServer(later)))
        let outcome = try #require(await subject.run(refresh: true, now: now))

        guard case .done(let message) = outcome.phase else { Issue.record("expected success"); return }
        #expect(outcome.thisWeek == 0)
        #expect(message.contains("No class assignments this week"))
    }

    // 8: offline or a server error is reported as such, never as "done".
    @Test func aFailedFetchIsReportedAndAddsNothingWhenNothingIsCached() async throws {
        let network = NetworkSwitch(online: false)
        var subject = pass(await makeStudent(await makeServer(), network: network))
        let outcome = try #require(await subject.run(refresh: true, now: now))

        guard case .failed = outcome.phase else { Issue.record("must not report success: \(outcome.phase)"); return }
        #expect(try allAssignments().isEmpty)
    }

    @Test func aServerErrorAfterAnEarlierSyncStillIsntReportedAsDone() async throws {
        let server = await makeServer()
        let network = NetworkSwitch()
        var first = pass(await makeStudent(server, network: network))
        _ = await first.run(refresh: true, now: now)

        network.failNext(.server("500"))
        var second = pass(await makeStudent(server, network: network))
        let outcome = try #require(await second.run(refresh: true, now: now))

        guard case .failed(let message) = outcome.phase else { Issue.record("must not report success"); return }
        #expect(message.contains("500"))
        #expect(try allAssignments().count == 7, "what was added stays, nothing is duplicated")
    }

    // 9 and the shared-source rule: the teacher's edit reaches the copy, progress is kept.
    @Test func aTeachersEditReachesTheWeekAndProgressIsKept() async throws {
        let server = await makeServer()
        var subject = pass(await makeStudent(server))
        _ = await subject.run(refresh: true, now: now)
        let logic = try #require(try allAssignments().first { $0.title == "Logic 1" })
        logic.apply(logic.exerciseState.settingCompleted(3))
        logic.notes = "my notes"

        var edited = try #require(lessons.first { $0.title == "Logic 1" })
        edited.title = "Logic 1 (revised)"
        edited.exerciseCount = 8
        edited.dueAt = date(2026, 10, 24)
        _ = try await InMemoryConnection(server: server, userID: adminID).saveLesson(LessonDraft(lesson: edited))

        _ = await subject.run(refresh: true, now: now)
        #expect(logic.title == "Logic 1 (revised)")
        #expect(logic.totalExercises == 8)
        #expect(logic.dueDate == date(2026, 10, 24))
        #expect(logic.completedExercises == 3, "progress survives the sync")
        #expect(logic.notes == "my notes")
        #expect(try allAssignments().count == 7)
    }

    // 10: the class side only ever returns the signed-in student's own progress.
    @Test func anotherStudentsProgressNeverReachesThisStudent() async throws {
        let server = await makeServer()
        let other = UUID()
        await server.addUser(other, isEnrolled: true)
        let logic = try #require(lessons.first { $0.title == "Logic 1" })
        let otherStudent = StudentStore(userID: other, backend: InMemoryConnection(server: server, userID: other),
                                        snapshots: SnapshotStore(directory: cache.appendingPathComponent("other")),
                                        automaticRetry: false)
        await otherStudent.start()
        await otherStudent.setCompletedExercises(4, lessonID: logic.id)

        var subject = pass(await makeStudent(server))
        _ = await subject.run(refresh: true, now: now)

        let copy = try #require(try allAssignments().first { $0.id == logic.id })
        #expect(copy.completedExercises == 0)
        #expect(subject.student.progress[logic.id] == nil)
    }
}
