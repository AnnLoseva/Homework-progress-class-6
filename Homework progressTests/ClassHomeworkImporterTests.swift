//
//  ClassHomeworkImporterTests.swift
//  Homework progressTests
//
//  "Subscribe to class": class lessons become homework assignments in the right week and
//  course, with their PDFs, without ever overwriting the user's own work.
//

import Foundation
import SwiftData
import Testing
@testable import Homework_progress
import StudyDomain

@MainActor
@Suite("Subscribe to class")
struct ClassHomeworkImporterTests {
    let env: TestEnvironment
    let now = date(2026, 10, 21)
    /// The seeded "Discrete Mathematics" course, as publishing names it in the class catalog.
    let discrete = StudyDomain.Course(slug: "discrete-mathematics", title: "מתמטיקה בדידה",
                                      subtitle: "Discrete Mathematics", colorKey: "berry")

    init() throws {
        env = try TestEnvironment()
        _ = try env.seed()
    }

    func lesson(_ title: String, _ category: LessonCategory, week: Int? = 1, due: Date? = nil,
                exercises: Int = 5, status: LessonStatus = .published, course: StudyDomain.Course? = nil) -> Lesson {
        Lesson(courseID: (course ?? discrete).id, title: title, category: category, status: status, week: week,
               moduleTitle: week.map { "Week \($0)" }, dueAt: due ?? date(2026, 10, 22), exerciseCount: exercises,
               publishedAt: date(2026, 10, 1))
    }

    func importer(failingFiles: Bool = false) throws -> ClassHomeworkImporter {
        let pdf = try env.makePDF(named: "Sheet.pdf")
        return ClassHomeworkImporter(store: env.store, planner: WeekPlanner(), ledger: ClassImportLedger(defaults: env.defaults),
                                     fetchFile: { _ in
                                         if failingFiles { throw URLError(.notConnectedToInternet) }
                                         return pdf
                                     })
    }

    func assignments() throws -> [HomeworkAssignment] {
        try env.context.fetch(FetchDescriptor<HomeworkAssignment>(sortBy: [SortDescriptor(\.title)]))
    }

    @Test func requiredAndOptionalLessonsLandInTheMatchingWeekAndCourse() async throws {
        let week = env.store.createWeek(title: "Week 1", number: 1, start: date(2026, 10, 18), end: date(2026, 10, 24))
        let required = lesson("Sets", .required)
        let optional = lesson("Extra drills", .optional)
        let file = LessonAttachment(lessonID: required.id, title: "Sets", fileName: "Sets.pdf", byteSize: 1000)
        var subject = try importer()

        let report = await subject.run(catalog: Catalog(courses: [discrete], lessons: [required, optional], attachments: [file]), now: now)

        #expect(report.added == 2)
        #expect(report.filesAdded == 1)
        let all = try assignments()
        #expect(Set(all.map(\.id)) == [required.id, optional.id], "assignments reuse the lesson ids")
        #expect(all.allSatisfy { $0.week?.id == week.id })
        #expect(all.allSatisfy { $0.course?.englishName == "Discrete Mathematics" }, "matched to the seeded course")
        let sets = try #require(all.first { $0.id == required.id })
        #expect(sets.totalExercises == 5)
        #expect(sets.dueDate == date(2026, 10, 22))
        #expect(sets.attachmentList.map(\.id) == [file.id])
        #expect(sets.attachmentList.first?.originalFilename == "Sets.pdf")
        #expect(all.first { $0.id == optional.id }?.notes.isEmpty == false, "optional lessons are labelled")
    }

    @Test func aMissingWeekIsCreatedAroundTheDueDate() async throws {
        var subject = try importer()
        _ = await subject.run(catalog: Catalog(courses: [discrete], lessons: [lesson("Logic", .required, week: 4, due: date(2026, 11, 12))]), now: now)

        let week = try #require(try assignments().first?.week)
        #expect(week.number == 4)
        #expect(week.title == "Week 4")
        #expect(WeekPlanner().contains(date(2026, 11, 12), start: week.startDate, end: week.endDate))
    }

    @Test func runningAgainUpdatesSharedFieldsButNeverProgress() async throws {
        let original = lesson("Sets", .required, exercises: 5)
        var subject = try importer()
        _ = await subject.run(catalog: Catalog(courses: [discrete], lessons: [original]), now: now)
        let copy = try #require(try assignments().first)
        copy.apply(copy.exerciseState.settingCompleted(4))
        copy.notes = "my notes"

        var changed = original
        changed.title = "Sets and relations"
        changed.exerciseCount = 3            // below the 4 already done: kept at 5
        changed.dueAt = date(2026, 10, 23)
        let report = await subject.run(catalog: Catalog(courses: [discrete], lessons: [changed]), now: now)

        #expect(report.added == 0)
        #expect(report.updated == 1)
        #expect(try assignments().count == 1)
        #expect(copy.title == "Sets and relations")
        #expect(copy.dueDate == date(2026, 10, 23))
        #expect(copy.totalExercises == 5)
        #expect(copy.completedExercises == 4)
        #expect(copy.notes == "my notes")
    }

    @Test func aDeletedCopyIsNotBroughtBack() async throws {
        let sets = lesson("Sets", .required)
        var subject = try importer()
        _ = await subject.run(catalog: Catalog(courses: [discrete], lessons: [sets]), now: now)
        env.store.delete(try #require(try assignments().first))

        var again = try importer()          // a later launch reads the saved ledger
        let report = await again.run(catalog: Catalog(courses: [discrete], lessons: [sets]), now: now)
        #expect(report.added == 0)
        #expect(try assignments().isEmpty)
    }

    @Test func theAdministratorsOwnHomeworkIsNeverOverwritten() async throws {
        let courses = try env.context.fetch(FetchDescriptor<Homework_progress.Course>())
        let course = try #require(courses.first { $0.englishName == "Discrete Mathematics" })
        let week = env.store.createWeek(title: "Week 1", number: 1, start: date(2026, 10, 18), end: date(2026, 10, 24))
        let own = env.store.createAssignment(title: "My homework", course: course, week: week, totalExercises: 9)
        // Publishing reuses the assignment's id for the lesson.
        let published = Lesson(id: own.id, courseID: discrete.id, title: "Renamed in class", category: .required,
                               status: .published, week: 1, exerciseCount: 2, publishedAt: date(2026, 10, 1))
        var subject = try importer()
        let report = await subject.run(catalog: Catalog(courses: [discrete], lessons: [published]), now: now)

        #expect(report.added == 0 && report.updated == 0)
        #expect(own.title == "My homework")
        #expect(own.totalExercises == 9)
    }

    @Test func draftsAndArchivedLessonsAreSkipped() async throws {
        var subject = try importer()
        let report = await subject.run(catalog: Catalog(courses: [discrete], lessons: [
            lesson("Draft", .required, status: .draft), lesson("Old", .required, status: .archived),
        ]), now: now)
        #expect(report.added == 0)
        #expect(try assignments().isEmpty)
    }

    @Test func pdfsThatCantBeDownloadedYetArriveOnALaterPass() async throws {
        let sets = lesson("Sets", .required)
        let file = LessonAttachment(lessonID: sets.id, title: "Sets", fileName: "Sets.pdf", byteSize: 1000)
        let catalog = Catalog(courses: [discrete], lessons: [sets], attachments: [file])
        var offline = try importer(failingFiles: true)
        let first = await offline.run(catalog: catalog, now: now)
        #expect(first.added == 1 && first.filesPending == 1)
        #expect(try assignments().first?.attachmentList.isEmpty == true)

        var online = try importer()
        let second = await online.run(catalog: catalog, now: now)
        #expect(second.filesAdded == 1 && second.filesPending == 0)
        #expect(try assignments().first?.attachmentList.map(\.id) == [file.id])
    }

    @Test func anUnknownClassCourseBecomesANewHomeworkCourse() async throws {
        let robotics = StudyDomain.Course(slug: "robotics", title: "Robotics", subtitle: "Robots", iconName: "CourseLaptop", colorKey: "lake")
        var subject = try importer()
        _ = await subject.run(catalog: Catalog(courses: [robotics], lessons: [lesson("Motors", .required, course: robotics)]), now: now)

        let course = try #require(try assignments().first?.course)
        #expect(course.name == "Robotics")
        #expect(course.palette == .blue)
        #expect(course.iconName == "CourseLaptop")
    }
}
