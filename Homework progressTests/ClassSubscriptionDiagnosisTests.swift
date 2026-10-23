//
//  ClassSubscriptionDiagnosisTests.swift
//  Homework progressTests
//
//  Regression tests for "the week and the course list stay empty after subscribing": the
//  import ledger shared through iCloud key-value storage must never stop a device from adding
//  class lessons it doesn't have.
//

import Foundation
import SwiftData
import Testing
@testable import Homework_progress
import ClassroomUI
import StudyData
import StudyDomain

@MainActor
@Suite("Subscribe to class: diagnosis of an empty week")
struct ClassSubscriptionDiagnosisTests {
    let planner = WeekPlanner(firstWeekday: 1)
    let now = date(2026, 10, 23, hour: 17)
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent("Diagnosis-\(UUID().uuidString)")

    let algebra = StudyDomain.Course(slug: "linear-algebra-data-representation-a", title: "אלגברה ליניארית וייצוג נתונים - חלק א",
                                     subtitle: "Linear Algebra & Data Representation A", sortOrder: 0)
    let discrete = StudyDomain.Course(slug: "discrete-mathematics", title: "מתמטיקה בדידה",
                                      subtitle: "Discrete Mathematics", sortOrder: 4)
    let lessons: [Lesson]

    init() {
        let (algebra, discrete) = (algebra, discrete)
        func lesson(_ title: String, _ course: StudyDomain.Course, _ exercises: Int) -> Lesson {
            Lesson(courseID: course.id, title: title, category: .optional, status: .published, week: 1,
                   moduleTitle: "Week 1", dueAt: date(2026, 10, 25, hour: 9), exerciseCount: exercises,
                   publishedAt: date(2026, 10, 23), weekStartsOn: "2026-10-18", weekEndsOn: "2026-10-23")
        }
        lessons = [lesson("Targil 1", algebra, 6), lesson("HW1", algebra, 9), lesson("Logic 1", discrete, 9)]
    }

    func server(_ lessons: [Lesson]? = nil) -> InMemoryServer {
        InMemoryServer(catalog: Catalog(courses: [algebra, discrete], lessons: lessons ?? self.lessons))
    }

    func student(_ server: InMemoryServer, network: NetworkSwitch = NetworkSwitch(), name: String = "s") async -> StudentStore {
        let id = UUID()
        await server.addUser(id)
        let store = StudentStore(userID: id, backend: InMemoryConnection(server: server, userID: id, network: network),
                                 snapshots: SnapshotStore(directory: cache.appendingPathComponent(name)), automaticRetry: false)
        await store.loadCache()
        return store
    }

    func pass(_ student: StudentStore, on device: TestEnvironment, cloud: FakeCloudStore? = nil) -> ClassSubscriptionPass {
        ClassSubscriptionPass(student: student, importer: ClassHomeworkImporter(
            store: device.store, planner: planner,
            ledger: ClassImportLedger(settings: SyncedSettings(local: device.defaults, cloud: cloud)),
            fetchFile: { _ in throw URLError(.userAuthenticationRequired) }))
    }

    func assignments(_ device: TestEnvironment) throws -> [HomeworkAssignment] {
        try device.context.fetch(FetchDescriptor<HomeworkAssignment>())
    }

    // THE REGRESSION. The administrator's iPad (development build) has the lessons as its own
    // homework; seeing them records every lesson id in the shared ledger. Another device on the
    // same Apple ID — a TestFlight build, whose CloudKit environment doesn't have that homework —
    // then subscribes: it must add the lessons, not treat them as "deleted by the user".
    @Test func lessonsSeenOnAnotherDeviceAreStillAddedHere() async throws {
        let cloud = FakeCloudStore()
        let server = server()

        let adminsPad = try TestEnvironment()
        let courses = try adminsPad.seed()
        let week = adminsPad.store.createWeek(title: "Week 1", number: 1, start: date(2026, 10, 18), end: date(2026, 10, 23))
        for lesson in lessons {                              // published from this homework: same ids
            adminsPad.store.createAssignment(title: lesson.title, course: courses[0], week: week, id: lesson.id)
        }
        var adminPass = pass(await student(server, name: "admin"), on: adminsPad, cloud: cloud)
        _ = await adminPass.run(refresh: true, now: now)

        let testFlight = try TestEnvironment()               // empty store, no courses
        var subject = pass(await student(server, name: "tf"), on: testFlight, cloud: cloud)
        let outcome = try #require(await subject.run(refresh: true, now: now))

        #expect(Set(try assignments(testFlight).map(\.id)) == Set(lessons.map(\.id)), "every lesson is in the week")
        #expect(try testFlight.context.fetchCount(FetchDescriptor<Homework_progress.Course>()) == 2, "and their courses")
        #expect(outcome.report.added == 3)
    }

    // A lesson the user really deleted stays deleted on every device, and isn't counted as an error.
    @Test func aCopyTheUserDeletedStaysDeletedOnEveryDevice() async throws {
        let cloud = FakeCloudStore()
        let server = server()
        let iPhone = try TestEnvironment()
        var phonePass = pass(await student(server, name: "phone"), on: iPhone, cloud: cloud)
        _ = await phonePass.run(refresh: true, now: now)
        let removed = try #require(try assignments(iPhone).first { $0.title == "HW1" })
        iPhone.store.withClassLedger(SyncedSettings(local: iPhone.defaults, cloud: cloud)).delete(removed)

        _ = await phonePass.run(refresh: false, now: now)
        #expect(!(try assignments(iPhone).contains { $0.title == "HW1" }), "not brought back here")

        let iPad = try TestEnvironment()
        var padPass = pass(await student(server, name: "pad"), on: iPad, cloud: cloud)
        let outcome = try #require(await padPass.run(refresh: true, now: now))
        #expect(Set(try assignments(iPad).map(\.title)) == ["Targil 1", "Logic 1"], "nor on the other device")
        #expect(outcome.diagnostics.removedByUser == 1)
    }

    // The week on screen isn't the lessons' week: they still land in their own week, which the
    // dashboard is moved to, and the current week isn't filled with them.
    @Test func lessonsGoToTheirOwnWeekWhenTodayIsInAnotherWeek() async throws {
        let device = try TestEnvironment()
        _ = try device.seed()
        let current = device.store.createWeek(title: "Week 2", number: 2, start: date(2026, 10, 25), end: date(2026, 10, 31))
        var subject = pass(await student(server()), on: device)
        let outcome = try #require(await subject.run(refresh: true, now: date(2026, 10, 27)))

        #expect(current.assignmentList.isEmpty)
        let target = try #require(try assignments(device).first?.week)
        #expect(target.number == 1 && planner.contains(date(2026, 10, 18), start: target.startDate, end: target.endDate))
        #expect(outcome.weekToShow?.id == target.id, "the dashboard opens the week the lessons went to")
        #expect(outcome.thisWeek == 0)
    }

    @Test func anEmptyCatalogIsASuccessWithNothingToAdd() async throws {
        let device = try TestEnvironment()
        _ = try device.seed()
        var subject = pass(await student(server([])), on: device)
        let outcome = try #require(await subject.run(refresh: true, now: now))
        guard case .done = outcome.phase else { Issue.record("expected success: \(outcome.phase)"); return }
        #expect(outcome.diagnostics.catalogLessons == 0)
        #expect(try assignments(device).isEmpty)
    }

    @Test func aFailedFetchIsShownInTheDiagnostics() async throws {
        let device = try TestEnvironment()
        let network = NetworkSwitch()
        network.failNext(.server("503"))
        var subject = pass(await student(server(), network: network), on: device)
        let outcome = try #require(await subject.run(refresh: true, now: now))
        guard case .failed = outcome.phase else { Issue.record("must not report success"); return }
        #expect(outcome.diagnostics.fetchError != nil)
        #expect(outcome.diagnostics.lines.contains { $0.contains("fetch failed") })
    }

    // The pass doesn't depend on iCloud having caught up; only the trigger waits, and it says why.
    @Test func theTriggerSaysWhyAPassDidntStart() {
        #expect(ClassSyncReadiness.blockers(iCloudCaughtUp: false, subscribed: true, signedIn: true, cacheLoaded: true)
                == ["waiting for the first iCloud import"])
        #expect(ClassSyncReadiness.blockers(iCloudCaughtUp: true, subscribed: false, signedIn: false, cacheLoaded: false)
                == ["subscription is off", "not signed in to the class"])
        #expect(ClassSyncReadiness.blockers(iCloudCaughtUp: true, subscribed: true, signedIn: true, cacheLoaded: true).isEmpty)
    }

    @Test func iCloudThatNeverReportsAnImportStillLetsThePassRun() async throws {
        var caughtUp = false
        let monitor = SyncMonitor(storeKind: .iCloud, catchUpTimeout: .milliseconds(50),
                                  accountAvailable: { true }, onRemoteChange: {})
        monitor.onCaughtUp = { caughtUp = true }
        #expect(!monitor.hasCaughtUp)
        for _ in 0..<60 where !(monitor.hasCaughtUp && caughtUp) { try await Task.sleep(for: .milliseconds(50)) }
        #expect(monitor.hasCaughtUp)
        #expect(caughtUp, "the missing-courses check runs once iCloud has caught up")
    }

    @Test func diagnosticsCountWhatWasFilteredAndWhereLessonsWent() async throws {
        let device = try TestEnvironment()
        _ = try device.seed()
        var draft = lessons[0]
        draft.id = UUID()
        draft.status = .draft
        var subject = pass(await student(server(lessons + [draft])), on: device)
        let outcome = try #require(await subject.run(refresh: true, now: now))
        let d = outcome.diagnostics

        #expect(d.catalogCourses == 2 && d.catalogLessons == 3 && d.activeLessons == 3, "students never get drafts")
        #expect(d.before.assignments == 0 && d.after.assignments == 3)
        #expect(d.after.courses == 5 && d.after.weeks == 1)
        #expect(d.placements.count == 3)
        #expect(Set(d.placements.map(\.week)).count == 1)
        #expect(d.saveError == nil)
        // Nothing personal: counts and random ids only.
        #expect(!d.lines.joined().contains("Targil"))
    }
}
