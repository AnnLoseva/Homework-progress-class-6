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

    // The test iPad with another account: its own "Week 1" (18–25 Oct), no course at all, and
    // the class as it is on the server — 12 optional lessons, all week 1, due 25–28 Oct.
    @Test func anotherAccountWithAnEmptyWeekAndNoCoursesGetsAllTwelveLessons() async throws {
        let iPad = try TestEnvironment()                       // nothing seeded: no courses
        let week = iPad.store.createWeek(title: "Week 1", number: 1, start: date(2026, 10, 18), end: date(2026, 10, 25))
        let computational = StudyDomain.Course(slug: "computational-thinking-programming", title: "חשיבה חישובית ותכנותית",
                                               subtitle: "Computational Thinking & Programming", sortOrder: 1)
        let silicon = StudyDomain.Course(slug: "from-silicon-to-high-level-language", title: "מסיליקון לשפה עילית",
                                         subtitle: "From Silicon to High-Level Language", sortOrder: 3)
        func optional(_ title: String, _ course: StudyDomain.Course, due day: Int, _ exercises: Int) -> Lesson {
            Self.lesson(title, course, week: 1, due: date(2026, 10, day, hour: 9), category: .optional, exercises: exercises)
        }
        let server = InMemoryServer(catalog: Catalog(courses: [algebra, computational, analysis, silicon, discrete], lessons: [
            optional("Targil 1", algebra, due: 25, 6), optional("HW1", algebra, due: 25, 9),
            optional("Class Work 2", algebra, due: 25, 5), optional("Exercise 1", computational, due: 25, 10),
            optional("Test quantifiers", discrete, due: 25, 52), optional("Exer DNF and CNF", discrete, due: 25, 1),
            optional("Exer quantif", discrete, due: 25, 20), optional("Tirgul Logic 1", discrete, due: 25, 9),
            optional("Exercise 1 (silicon)", silicon, due: 26, 13), optional("Add_List_1", analysis, due: 28, 8),
            optional("List_1", analysis, due: 28, 9), optional("Review sheet", analysis, due: 28, 1),
        ]))
        let other = UUID()
        await server.addUser(other)                            // signed in, hasn't joined with the class code
        let student = StudentStore(userID: other, backend: InMemoryConnection(server: server, userID: other),
                                   snapshots: SnapshotStore(directory: cache.appendingPathComponent("iPad")), automaticRetry: false)
        await student.loadCache()
        var subject = ClassSubscriptionPass(student: student, importer: ClassHomeworkImporter(
            store: iPad.store, planner: planner, ledger: ClassImportLedger(defaults: iPad.defaults),
            fetchFile: { _ in throw URLError(.userAuthenticationRequired) }))

        let outcome = try #require(await subject.run(refresh: true, now: date(2026, 10, 23, hour: 16)))

        #expect(week.assignmentList.count == 12, "every lesson is in the week on screen")
        #expect(try iPad.context.fetchCount(FetchDescriptor<AcademicWeek>()) == 1, "no second week")
        #expect(Set(week.assignmentList.compactMap { $0.course?.englishName }).count == 5, "all five courses")
        #expect(Set(try iPad.context.fetch(FetchDescriptor<Homework_progress.Course>()).map(\.id))
                == Set(CourseSeeder.defaults.map(\.id)), "the five default courses, as on every other device")
        #expect(outcome.thisWeek == 12)
        #expect(outcome.weekToShow?.id == week.id)
        guard case .done = outcome.phase else { Issue.record("expected success: \(outcome.phase)"); return }
        #expect(outcome.report.filesPending == 0, "these lessons have no PDFs to wait for")
    }

    // Every account that subscribes gets the administrator's week as it is: "Week 1",
    // 18–23 Oct, the same 12 assignments in the same five courses, with its own progress
    // (0 of 143) — never the administrator's 97.
    @Test func everySubscriberGetsTheSameWeekAndCoursesWithTheirOwnProgress() async throws {
        let computational = StudyDomain.Course(slug: "computational-thinking-programming", title: "חשיבה חישובית ותכנותית",
                                               subtitle: "Computational Thinking & Programming", sortOrder: 1)
        let silicon = StudyDomain.Course(slug: "from-silicon-to-high-level-language", title: "מסיליקון לשפה עילית",
                                         subtitle: "From Silicon to High-Level Language", sortOrder: 3)
        func published(_ title: String, _ course: StudyDomain.Course, due day: Int, _ exercises: Int) -> Lesson {
            var lesson = Self.lesson(title, course, week: 1, due: date(2026, 10, day, hour: 9), category: .optional, exercises: exercises)
            lesson.weekStartsOn = "2026-10-18"
            lesson.weekEndsOn = "2026-10-23"
            return lesson
        }
        let classLessons = [
            published("Targil 1", algebra, due: 25, 6), published("HW1", algebra, due: 25, 9),
            published("Class Work 2", algebra, due: 25, 5), published("Exercise 1", computational, due: 25, 10),
            published("Test quantifiers", discrete, due: 25, 52), published("Exer DNF and CNF", discrete, due: 25, 1),
            published("Exer quantif", discrete, due: 25, 20), published("Tirgul Logic 1", discrete, due: 25, 9),
            published("Exercise 1 (silicon)", silicon, due: 26, 13), published("Add_List_1", analysis, due: 28, 8),
            published("List_1", analysis, due: 28, 9), published("Review sheet", analysis, due: 28, 1),
        ]
        let server = InMemoryServer(catalog: Catalog(courses: [algebra, computational, analysis, silicon, discrete],
                                                     lessons: classLessons))
        await server.addUser(adminID, isAdmin: true, isEnrolled: true)
        // The administrator has done 97 exercises in Class.
        let admin = StudentStore(userID: adminID, backend: InMemoryConnection(server: server, userID: adminID),
                                 snapshots: SnapshotStore(directory: cache.appendingPathComponent("admin")), automaticRetry: false)
        await admin.start()
        for lesson in classLessons.prefix(5) { await admin.setCompletedExercises(lesson.exerciseCount, lessonID: lesson.id) }

        for account in 1...2 {                                 // two other accounts, on fresh devices
            let device = try TestEnvironment()
            let studentID = UUID()
            await server.addUser(studentID)
            let student = StudentStore(userID: studentID, backend: InMemoryConnection(server: server, userID: studentID),
                                       snapshots: SnapshotStore(directory: cache.appendingPathComponent("s\(account)")),
                                       automaticRetry: false)
            await student.loadCache()
            var subject = ClassSubscriptionPass(student: student, importer: ClassHomeworkImporter(
                store: device.store, planner: planner, ledger: ClassImportLedger(defaults: device.defaults),
                fetchFile: { _ in throw URLError(.userAuthenticationRequired) }))
            let outcome = try #require(await subject.run(refresh: true, now: date(2026, 10, 23, hour: 17)))

            let weeks = try device.context.fetch(FetchDescriptor<AcademicWeek>())
            let week = try #require(weeks.first)
            #expect(weeks.count == 1)
            #expect(week.title == "Week 1" && week.number == 1)
            #expect(week.startDate == date(2026, 10, 18, hour: 0) && week.endDate == date(2026, 10, 23, hour: 0), "18–23 Oct")
            #expect(outcome.weekToShow?.id == week.id)

            let summary = ProgressCalculator.summarize(week.assignmentList.map(\.snapshot))
            #expect(summary.assignmentCount == 12)
            #expect(summary.totalExercises == 143)
            #expect(summary.completedExercises == 0, "their own progress, not the administrator's")

            // The Courses list on the week: every course has its assignments.
            let courses = try device.context.fetch(FetchDescriptor<Homework_progress.Course>())
            #expect(Set(courses.map(\.id)) == Set(CourseSeeder.defaults.map(\.id)))
            let perCourse = Dictionary(uniqueKeysWithValues: courses.map { ($0.englishName, $0.assignments(in: week).count) })
            #expect(perCourse == ["Linear Algebra & Data Representation A": 3, "Computational Thinking & Programming": 1,
                                  "Introduction to Analysis": 3, "From Silicon to High-Level Language": 1,
                                  "Discrete Mathematics": 4])
        }
    }
}
