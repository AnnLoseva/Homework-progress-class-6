//
//  ClassPublisherTests.swift
//  Homework progressTests
//
//  "Publish to class" against the in-memory stand-in for the class backend. The real
//  backend's permissions are covered by the SQL suites in supabase/tests.
//

import Foundation
import SwiftData
import Testing
import StudyData
import StudyDomain
@testable import Homework_progress

@Suite("Publish to class")
@MainActor
struct ClassPublisherTests {
    let adminID = UUID()

    func makeAdmin(students: [UUID] = []) async -> (InMemoryServer, AdminStore) {
        let server = InMemoryServer()
        await server.addUser(adminID, isAdmin: true)
        for student in students { await server.addUser(student, isEnrolled: true) }
        return (server, AdminStore(backend: InMemoryConnection(server: server, userID: adminID)))
    }

    func item(_ title: String = "HW1", total: Int? = 9, files: [ClassPublishItem.File] = [],
              courseID: UUID = UUID(uuidString: "6F7C1E2A-0000-4000-8000-000000000001")!) -> ClassPublishItem {
        ClassPublishItem(id: UUID(), title: title,
                         course: .init(id: courseID, name: "מתמטיקה בדידה", englishName: "Discrete Mathematics",
                                       iconName: "CourseDiscrete", colorKey: "plum", sortOrder: 4),
                         weekNumber: 1, weekTitle: "Week 1", orderInWeek: 0, dueDate: nil, totalExercises: total, files: files)
    }

    /// Everything on the server, drafts included, seen by a separate administrator.
    func adminCatalog(_ server: InMemoryServer) async throws -> Catalog {
        let inspector = UUID()
        await server.addUser(inspector, isAdmin: true)
        return try await InMemoryConnection(server: server, userID: inspector).fetchAdminCatalog()
    }

    func pdf(_ text: String = "x") -> Data { Data("%PDF-1.4\n\(text)\n%%EOF\n".utf8) }

    @Test func publishesLessonsCoursesAndPDFsWithoutPrivateProgress() async throws {
        let (server, admin) = await makeAdmin()
        let file = ClassPublishItem.File(id: UUID(), fileName: "Sheet 1.pdf", byteCount: Int64(pdf().count), sortIndex: 0, storedFilename: "a.pdf")
        let homework = item(files: [file])
        let report = await ClassPublisher(admin: admin) { _ in pdf() }.publish([homework], options: .init())

        #expect(report.succeeded, "\(report.failures)")
        #expect(report.lessonsCreated == 1)
        #expect(report.filesUploaded == 1)
        let catalog = try await adminCatalog(server)
        let lesson = try #require(catalog.lesson(homework.id), "the lesson reuses the assignment's id")
        #expect(lesson.status == .published)
        #expect(lesson.category == .required)
        #expect(lesson.exerciseCount == 9)
        #expect(lesson.week == 1)
        #expect(lesson.description.isEmpty, "notes are never published")
        #expect(catalog.courses.map(\.slug) == ["discrete-mathematics"])
        #expect(catalog.courses.first?.colorKey == "berry")
        let attachment = try #require(catalog.attachments(for: lesson.id).first)
        #expect(attachment.id == file.id)
        #expect(attachment.visibility == .restricted)
        #expect(attachment.title == "Sheet 1")
    }

    @Test func publishingAgainUpdatesInsteadOfDuplicating() async throws {
        let (server, admin) = await makeAdmin()
        let file = ClassPublishItem.File(id: UUID(), fileName: "Sheet.pdf", byteCount: Int64(pdf().count), sortIndex: 0, storedFilename: "a.pdf")
        var homework = item(files: [file])
        let publisher = ClassPublisher(admin: admin) { _ in pdf() }
        _ = await publisher.publish([homework], options: .init())

        homework.title = "HW1 (revised)"
        let report = await publisher.publish([homework], options: .init(category: .optional))

        #expect(report.lessonsCreated == 0)
        #expect(report.lessonsUpdated == 1)
        #expect(report.filesUnchanged == 1)
        let catalog = try await adminCatalog(server)
        #expect(catalog.lessons.count == 1)
        #expect(catalog.courses.count == 1)
        #expect(catalog.attachments.count == 1)
        #expect(catalog.lessons.first?.title == "HW1 (revised)")
        #expect(catalog.lessons.first?.category == .required, "an existing lesson keeps its category")
    }

    @Test func aReplacedPDFBecomesANewVersionAndStudentProgressSurvives() async throws {
        let student = UUID()
        let (server, admin) = await makeAdmin(students: [student])
        let fileID = UUID()
        let first = ClassPublishItem.File(id: fileID, fileName: "Sheet.pdf", byteCount: Int64(pdf("a").count), sortIndex: 0, storedFilename: "a.pdf")
        var homework = item(files: [first])
        _ = await ClassPublisher(admin: admin) { _ in pdf("a") }.publish([homework], options: .init())

        let api = InMemoryConnection(server: server, userID: student)
        _ = try await api.saveProgress(LessonProgress(lessonID: homework.id, status: .inProgress, completedExercises: 4))

        homework.files = [.init(id: fileID, fileName: "Sheet.pdf", byteCount: Int64(pdf("longer").count), sortIndex: 0, storedFilename: "b.pdf")]
        let report = await ClassPublisher(admin: admin) { _ in pdf("longer") }.publish([homework], options: .init())

        #expect(report.filesReplaced == 1)
        let attachment = try #require(try await adminCatalog(server).attachments.first)
        #expect(attachment.id == fileID)
        #expect(attachment.version == 2)
        #expect(try await api.fetchProgress().first?.completedExercises == 4)
    }

    @Test func aMissingPDFIsReportedAndTheRestIsPublished() async throws {
        let (server, admin) = await makeAdmin()
        let file = ClassPublishItem.File(id: UUID(), fileName: "Lost.pdf", byteCount: 10, sortIndex: 0, storedFilename: "lost.pdf")
        let report = await ClassPublisher(admin: admin) { _ in nil }.publish([item(files: [file]), item("HW2", total: nil)], options: .init())

        #expect(report.lessonsCreated == 2)
        #expect(report.failures.count == 1)
        let catalog = try await adminCatalog(server)
        #expect(catalog.attachments.isEmpty)
        #expect(catalog.lessons.first { $0.title == "HW2" }?.exerciseCount == 0)
    }

    @Test func aStudentCannotPublish() async throws {
        let server = InMemoryServer()
        let student = UUID()
        await server.addUser(student, isEnrolled: true)
        let admin = AdminStore(backend: InMemoryConnection(server: server, userID: student))
        let report = await ClassPublisher(admin: admin) { _ in nil }.publish([item()], options: .init())
        #expect(!report.succeeded)
        #expect(try await adminCatalog(server).lessons.isEmpty)
    }

    @Test func slugsAreStableForHebrewOnlyCourses() {
        let id = UUID(uuidString: "ABCDEF12-0000-4000-8000-000000000001")!
        let hebrew = ClassPublishItem.CourseInfo(id: id, name: "מבוא לאנליזה", englishName: "", iconName: "x", colorKey: "", sortOrder: 0)
        #expect(ClassPublisher.slug(for: hebrew) == "course-abcdef12")
        var english = hebrew
        english.englishName = "Introduction to Analysis"
        #expect(ClassPublisher.slug(for: english) == "introduction-to-analysis")
    }

    @Test func itemsCopyOnlySharedFieldsFromHomework() throws {
        let env = try TestEnvironment()
        let course = try #require(try env.seed().first)
        let week = env.store.createWeek(title: "Week 3", number: 3, start: date(2026, 11, 1), end: date(2026, 11, 7))
        let assignment = env.store.createAssignment(title: "Targil 3", course: course, week: week, totalExercises: 6)
        assignment.completedExercises = 5
        assignment.notes = "private"

        let item = ClassPublishItem(assignment: assignment, orderInWeek: 2)
        #expect(item.id == assignment.id)
        #expect(item.weekNumber == 3)
        #expect(item.totalExercises == 6)
        #expect(item.course.id == course.id)
        let draft = ClassPublisher.lessonDraft(for: item, courseID: UUID(), category: .required)
        #expect(draft.isValid)
        #expect(draft.description.isEmpty)
        #expect(draft.sortOrder == 2)
    }
}
