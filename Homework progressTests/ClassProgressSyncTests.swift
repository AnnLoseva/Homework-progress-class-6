//
//  ClassProgressSyncTests.swift
//  Homework progressTests
//
//  "Subscribe to class", progress half: a copied lesson's progress is the same in Homework and
//  in Class, whichever side it was changed on, against the in-memory class backend.
//

import Foundation
import SwiftData
import Testing
@testable import Homework_progress
import ClassroomUI
import StudyData
import StudyDomain

@MainActor
@Suite("Subscribe to class: progress in step")
struct ClassProgressSyncTests {
    let env: TestEnvironment
    let userID = UUID()
    let discrete = StudyDomain.Course(slug: "discrete-mathematics", title: "מתמטיקה בדידה",
                                      subtitle: "Discrete Mathematics", colorKey: "berry")

    init() throws {
        env = try TestEnvironment()
        _ = try env.seed()
    }

    func lesson(_ title: String, _ category: LessonCategory = .required, exercises: Int = 5) -> Lesson {
        Lesson(courseID: discrete.id, title: title, category: category, status: .published, week: 1,
               moduleTitle: "Week 1", dueAt: date(2026, 10, 22), exerciseCount: exercises,
               publishedAt: date(2026, 10, 1))
    }

    /// A signed-in, enrolled student whose lessons were already copied into Homework.
    func setUp(_ lessons: [Lesson]) async throws -> (server: InMemoryServer, student: StudentStore, sync: ClassProgressSync) {
        let catalog = Catalog(courses: [discrete], lessons: lessons)
        let server = InMemoryServer(catalog: catalog)
        await server.addUser(userID, isEnrolled: true)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("ProgressSync-\(UUID().uuidString)")
        let student = StudentStore(userID: userID, backend: InMemoryConnection(server: server, userID: userID),
                                   snapshots: SnapshotStore(directory: cache), automaticRetry: false)
        await student.start()
        var importer = ClassHomeworkImporter(store: env.store, planner: WeekPlanner(),
                                             ledger: ClassImportLedger(defaults: env.defaults),
                                             fetchFile: { _ in throw URLError(.notConnectedToInternet) })
        _ = await importer.run(catalog: student.catalog)
        return (server, student, ClassProgressSync(store: env.store, student: student, settings: SyncedSettings(local: env.defaults, cloud: nil)))
    }

    func assignment(_ id: UUID) throws -> HomeworkAssignment {
        try #require(try env.context.fetch(FetchDescriptor<HomeworkAssignment>(predicate: #Predicate { $0.id == id })).first)
    }

    @Test func exercisesTickedInHomeworkCountInClass() async throws {
        let sets = lesson("Sets")
        let (server, student, sync) = try await setUp([sets])
        let homework = try assignment(sets.id)
        homework.apply(homework.exerciseState.settingCompleted(3))

        let report = await sync.run()
        await student.sync()

        #expect(report.sentToClass == 1)
        let stored = try #require(await server.storedProgress(userID: userID, lessonID: sets.id))
        #expect(stored.completedExercises == 3)
        #expect(stored.status == .inProgress)
    }

    @Test func exercisesTickedInClassShowInHomework() async throws {
        let sets = lesson("Sets")
        let (_, student, sync) = try await setUp([sets])
        await student.setCompletedExercises(4, lessonID: sets.id)

        let report = await sync.run()

        #expect(report.takenFromClass == 1)
        let homework = try assignment(sets.id)
        #expect(homework.completedExercises == 4)
        #expect(homework.status == .inProgress)
    }

    @Test func completingEitherSideCompletesBothAndThenSettles() async throws {
        let sets = lesson("Sets")
        let logic = lesson("Logic")
        let (_, student, sync) = try await setUp([sets, logic])
        let homework = try assignment(sets.id)
        homework.apply(homework.exerciseState.markedCompleted())
        await student.setStatus(.completed, lessonID: logic.id)

        _ = await sync.run()

        #expect(student.progress(for: sets.id).status == .completed)
        #expect(try assignment(logic.id).status == .completed)
        #expect(try assignment(logic.id).completedExercises == 5)
        let again = await sync.run()
        #expect(again.sentToClass == 0)
        #expect(again.takenFromClass == 0, "nothing flips back and forth")
    }

    @Test func whenBothSidesChangedTheNewerChangeWins() async throws {
        let sets = lesson("Sets")
        let (_, student, sync) = try await setUp([sets])
        _ = await sync.run()
        // Class first (the store's clock), then homework (later): homework wins.
        await student.setCompletedExercises(1, lessonID: sets.id)
        try await Task.sleep(for: .milliseconds(20))
        let homework = try assignment(sets.id)
        homework.apply(homework.exerciseState.settingCompleted(2))

        _ = await sync.run()

        #expect(student.progress(for: sets.id).completedExercises == 2)
        #expect(homework.completedExercises == 2)
    }

    @Test func optionalLessonsAreFollowedOnceAndAnUnfollowStays() async throws {
        let drills = lesson("Extra drills", .optional)
        let (_, student, sync) = try await setUp([drills])

        let first = await sync.run()
        #expect(first.optionalLessonsFollowed == 1)
        #expect(student.subscriptions[drills.id]?.isActive == true)

        await student.setSubscribed(false, lessonID: drills.id)
        let second = await sync.run()
        #expect(second.optionalLessonsFollowed == 0)
        #expect(student.subscriptions[drills.id]?.isActive == false)
    }

    @Test func notesAndUnlinkedHomeworkAreLeftAlone() async throws {
        let sets = lesson("Sets")
        let (_, student, sync) = try await setUp([sets])
        let homework = try assignment(sets.id)
        homework.notes = "my own note"
        let courses = try env.context.fetch(FetchDescriptor<Homework_progress.Course>())
        let week = try #require(homework.week)
        let mine = env.store.createAssignment(title: "Not from class", course: courses[0], week: week, totalExercises: 3)
        mine.apply(mine.exerciseState.settingCompleted(2))
        await student.setCompletedExercises(1, lessonID: sets.id)

        _ = await sync.run()

        #expect(homework.notes == "my own note")
        #expect(student.progress(for: sets.id).notes.isEmpty)
        #expect(mine.completedExercises == 2)
    }
}
